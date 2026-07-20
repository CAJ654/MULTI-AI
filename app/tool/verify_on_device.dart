// Headless smoke test for the on-device GGUF roster.
//
// Loads each model through the *real* `OnDeviceEngine` — the same code path the
// app uses, including the GPU-offload ladder and the multimodal projector — and
// asks it one question. Answers "does this model actually load and generate?",
// which for 21 of the 22 roster entries has never been established: they were
// added in bulk as `_GGUF_SOURCE` declarations and never run.
//
// Run from the `app/` directory, which is where llamadart's native libraries
// resolve from (`.dart_tool/lib`, staged by the build hook):
//
//   dart run tool/verify_on_device.dart --preflight
//   dart run tool/verify_on_device.dart --wave 0
//
// If the native libraries don't resolve, point at them explicitly:
//   $env:LLAMADART_NATIVE_LIB_DIR = "<repo>\app\.dart_tool\lib"
//
// NEVER run `dart pub get` in app/ — pubspec.yaml declares an SDK-sourced
// Flutter dependency that plain pub cannot resolve, and a partial rewrite of
// .dart_tool/ destroys the native-asset state this script depends on. Use
// `flutter pub get`.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data' show BytesBuilder;

import 'package:llamadart/llamadart.dart';
import 'package:multi_ai/chat_types.dart';
import 'package:multi_ai/on_device_engine.dart';

// ---------------------------------------------------------------------------
// Deadlines
//
// All but the last are *stall* deadlines, not wall-clock budgets. A 14B model
// running fully on CPU is legitimately slow — minutes per reply — and a
// wall-clock timeout would fail it for being slow rather than for being broken.
// What distinguishes broken is that nothing moves at all.
// ---------------------------------------------------------------------------

/// No bytes received for this long — the socket is dead, not the download slow.
/// 63GB of weights legitimately takes ~90 minutes.
const Duration _downloadStall = Duration(seconds: 120);

/// Covers load *and* prompt eval, because from outside the engine those are one
/// opaque stretch: `generate` exposes no load-complete signal, and prompt eval
/// emits no tokens, so nothing distinguishes them until the first token lands.
///
/// Sized for the sum rather than for either alone. Load is an mmap plus backend
/// init — seconds to ~60s even for a 12GB GGUF — and the prompt is under 100
/// tokens, which even pure-CPU eval clears in seconds. So this is a loose
/// backstop against a wedged worker (OnDeviceEngine notes that prompt eval never
/// polls the cancel flag), not a precision instrument. Once tokens start,
/// [_interTokenStall] takes over and is far tighter.
const Duration _loadDeadline = Duration(seconds: 900);

/// Between tokens. Worst realistic case is a 14B fully on CPU at ~1-2 tok/s.
const Duration _interTokenStall = Duration(seconds: 45);

/// Backstop. Hitting this is NOT a failure — see [_Status.passTruncated].
const Duration _absoluteCap = Duration(seconds: 600);

/// Asked of every model. Deliberately trivial: this is a smoke test of the
/// loading and decoding stack, not a benchmark of the model.
const String _question = 'What is the capital of France? Reply in one short sentence.';
const String _questionKeyword = 'paris';

const String _visionQuestion =
    'What shape and what color is in this image? Answer in one short sentence.';
const List<String> _visionKeywords = ['circle', 'red'];

/// The clip is a pure 440Hz tone, so there is nothing to transcribe. The
/// question asks for a description instead, and the keywords accept any of the
/// reasonable ways to say "a steady tone" — including naming the note, since
/// 440Hz is concert A.
const String _audioQuestion = 'Describe this sound in one short sentence.';
const List<String> _audioKeywords = ['tone', 'beep', 'hum', 'note', 'pitch', 'frequency', 'sine'];

/// How many `_GGUF_SOURCE` files the roster holds (24 since the two Gemma 4
/// entries landed). Asserting the count turns a regex that silently stopped
/// matching into a loud failure — without it, the "parse the .pyx files so
/// there's one source of truth" design degrades into quietly verifying fewer
/// models than you think. Bump it deliberately when the roster grows.
const int _expectedPyxRosterSize = 24;

void main(List<String> argv) async {
  final args = _Args.parse(argv);
  final repoRoot = _findRepoRoot();
  if (repoRoot == null) {
    stderr.writeln('Could not locate the repo root (no Multi-AI/multi_ai/models directory).');
    stderr.writeln('Run this from the app/ directory: dart run tool/verify_on_device.dart');
    exit(2);
  }

  final roster = _parseRoster(repoRoot);
  final manifestFile = File(args.manifestPath ?? '${Directory.current.path}/tool/.verify_results.json');
  final manifest = _Manifest.load(manifestFile);

  if (args.report) {
    stdout.write(manifest.toMarkdown());
    return;
  }

  final selected = _select(roster, args);
  if (selected.isEmpty) {
    stderr.writeln('No models matched the selection.');
    exit(2);
  }

  final downloads = DefaultModelDownloadManager();

  if (args.preflight) {
    await _preflight(selected, downloads);
    return;
  }

  stdout.writeln('Verifying ${selected.length} model(s). Manifest: ${manifestFile.path}\n');
  for (var i = 0; i < selected.length; i++) {
    final entry = selected[i];
    final prior = manifest.records[entry.id];
    if (!args.force && prior != null && prior.isPass && prior.matchesSource(entry)) {
      stdout.writeln('[${i + 1}/${selected.length}] ${entry.id}: skipped (already passed)');
      continue;
    }
    stdout.writeln('[${i + 1}/${selected.length}] ${entry.id}  (${entry.sizeGb} GB declared)');

    final record = await _verifyOne(entry, downloads, args);
    manifest.records[entry.id] = record;
    // Flushed after every model, not at the end: a native crash in llama.cpp
    // takes down the whole Dart VM, and a CUDA fault can poison every
    // subsequent load. Losing the run must not mean losing the results.
    manifest.save(manifestFile);

    stdout.writeln('    -> ${record.summaryLine()}\n');
  }

  stdout.writeln(manifest.toMarkdown());
}

// ---------------------------------------------------------------------------
// Verification
// ---------------------------------------------------------------------------

Future<_Record> _verifyOne(_RosterEntry entry, ModelDownloadManager downloads, _Args args) async {
  final record = _Record(
    id: entry.id,
    source: entry.source,
    mmproj: entry.mmproj,
    declaredSizeGb: entry.sizeGb,
    timestamp: DateTime.now().toUtc().toIso8601String(),
  );

  // Phase A — fetch, deliberately outside the engine.
  //
  // OnDeviceEngine.loadModelSource downloads *inside* its await, so a timeout
  // wrapped around it cannot tell a 90-minute download from a wedged CUDA init.
  // Worse, the GPU-offload ladder catches every exception, so a 404 would be
  // retried at all four rungs. Fetching first makes the load phase a pure mmap
  // and gives a bad URL a clean, unambiguous verdict.
  var mmprojOk = entry.mmproj != null;
  if (!args.skipDownload) {
    try {
      await _fetch(downloads, entry.source, 'weights', record);
    } catch (e) {
      record.status = _Status.downloadFail;
      record.error = '$e';
      record.errorClass = e.runtimeType.toString();
      return record;
    }
    if (entry.mmproj != null) {
      try {
        await _fetch(downloads, entry.mmproj!, 'projector', record);
      } catch (e) {
        // A broken projector must not mask working text weights — record it and
        // carry on text-only.
        mmprojOk = false;
        record.mmprojError = '$e';
        stdout.writeln('    projector fetch failed, continuing text-only: $e');
      }
    }
  }
  if (args.downloadOnly) {
    record.status = _Status.downloaded;
    return record;
  }

  // Phase B — load and generate through the real engine.
  final engine = OnDeviceEngine();
  try {
    await _runOne(
      engine: engine,
      entry: entry,
      prompt: _question,
      keywords: const [_questionKeyword],
      attachments: const [],
      mmproj: null, // text-only pass never loads the projector
      maxTokens: args.maxTokens,
      into: record,
    );

    // Vision pass. A separate load: _ensureLoaded's cache key includes the
    // projector, so text-only and with-projector are different residents.
    if (entry.mmproj != null && mmprojOk && record.isPass) {
      // Driven off what the model *claims* rather than off the projector's mere
      // presence, so a wrongly declared modality surfaces as a failed probe.
      // That is the failure this whole change exists to prevent.
      if (entry.claimsImage) {
        record.vision = await _probe(
          engine: engine,
          entry: entry,
          label: 'vision',
          prompt: _visionQuestion,
          keywords: _visionKeywords,
          attachment: Attachment(
            kind: AttachmentKind.image,
            bytes: _redCirclePng(),
            mimeType: 'image/png',
            name: 'red_circle.png',
          ),
          maxTokens: args.maxTokens,
        );
      }
      if (entry.claimsAudio) {
        record.audio = await _probe(
          engine: engine,
          entry: entry,
          label: 'audio',
          prompt: _audioQuestion,
          keywords: _audioKeywords,
          attachment: Attachment(
            kind: AttachmentKind.audio,
            bytes: _sineWav(),
            mimeType: 'audio/wav',
            name: 'tone_440hz.wav',
          ),
          maxTokens: args.maxTokens,
        );
      }
    } else if (entry.mmproj != null && !mmprojOk) {
      record.status = _Status.mmprojFail;
    }
  } catch (e) {
    record.status = _Status.loadFail;
    record.error = '$e';
    record.errorClass = e.runtimeType.toString();
  } finally {
    // One model resident at a time. Unconditional, so a failure doesn't leave
    // weights pinned in VRAM for the next model to collide with.
    await engine.dispose();
  }
  return record;
}

/// Runs one modality probe (image or audio) as its own load.
///
/// Separate from the text pass because `_ensureLoaded`'s cache key includes the
/// projector, so with-projector and text-only are different residents. A failure
/// here is recorded against the probe, never against the text result — a model
/// whose vision is broken has still demonstrably loaded and generated.
Future<_Record> _probe({
  required OnDeviceEngine engine,
  required _RosterEntry entry,
  required String label,
  required String prompt,
  required List<String> keywords,
  required Attachment attachment,
  required int maxTokens,
}) async {
  final record = _Record(
    id: '${entry.id} ($label)',
    source: entry.source,
    mmproj: entry.mmproj,
    declaredSizeGb: entry.sizeGb,
    timestamp: DateTime.now().toUtc().toIso8601String(),
  );
  try {
    await _runOne(
      engine: engine,
      entry: entry,
      prompt: prompt,
      keywords: keywords,
      attachments: [attachment],
      mmproj: entry.mmproj,
      maxTokens: maxTokens,
      into: record,
    );
  } catch (e) {
    record.status = _Status.loadFail;
    record.error = '$e';
    record.errorClass = e.runtimeType.toString();
  }
  stdout.writeln('    $label -> ${record.summaryLine()}');
  return record;
}

/// One load + generate, with the stall watchdogs armed. Fills [into].
Future<void> _runOne({
  required OnDeviceEngine engine,
  required _RosterEntry entry,
  required String prompt,
  required List<String> keywords,
  required List<Attachment> attachments,
  required String? mmproj,
  required int maxTokens,
  required _Record into,
}) async {
  final clock = Stopwatch()..start();
  Duration? firstToken;
  var tokens = 0;
  Timer? watchdog;
  Timer? capTimer;
  String? stopReason;

  void arm(Duration d, String reason) {
    watchdog?.cancel();
    watchdog = Timer(d, () {
      stopReason = reason;
      // stop(), not Future.timeout: this routes through the engine's designed
      // cancellation path, which completes the pending future with the partial
      // text AND tears the worker down. A bare timeout would leave the decode
      // loop running into the next model.
      engine.stop();
    });
  }

  // The load has no token stream to watch, so it gets a plain deadline.
  arm(_loadDeadline, 'load_stall');
  capTimer = Timer(_absoluteCap, () {
    stopReason ??= 'absolute_cap';
    engine.stop();
  });

  String reply;
  try {
    reply = await engine.generate(
      prompt,
      source: entry.source,
      sizeGb: entry.sizeGb,
      mmproj: mmproj,
      attachments: attachments,
      maxTokens: maxTokens,
      onToken: (chunk) {
        // First token marks the end of load + prompt eval, which is why
        // firstTokenSeconds is reported rather than a separate load time: the
        // two are not separable from out here.
        firstToken ??= clock.elapsed;
        tokens++;
        arm(_interTokenStall, 'token_stall');
      },
    );
  } finally {
    watchdog?.cancel();
    capTimer.cancel();
  }
  clock.stop();

  // Rearm note: the first-token deadline is enforced by arming _loadDeadline
  // then, once loading is known complete (first token), switching to the
  // inter-token stall. A model that loads but never emits will trip
  // _loadDeadline, which is the longer and therefore safe bound.
  into.gpuLayersUsed = engine.loadedGpuLayers;
  into.firstTokenSeconds = firstToken == null ? null : firstToken!.inMilliseconds / 1000.0;
  into.generateSeconds = clock.elapsed.inMilliseconds / 1000.0;
  into.tokensEmitted = tokens;
  if (firstToken != null && clock.elapsed > firstToken!) {
    final decodeSeconds = (clock.elapsed - firstToken!).inMilliseconds / 1000.0;
    if (decodeSeconds > 0) into.tokensPerSecond = tokens / decodeSeconds;
  }
  into.stopReason = stopReason ?? 'eos';
  into.replyPreview = reply.length > 300 ? '${reply.substring(0, 300)}...' : reply;
  _judge(reply, prompt, keywords, stopReason, into);
}

/// Decides pass/fail. Deliberately lenient about *content* and strict about
/// *liveness*: several roster models are base models that ramble or emit
/// `<think>` blocks, and failing them would be measuring model quality rather
/// than whether the stack works.
void _judge(
  String reply,
  String prompt,
  List<String> keywords,
  String? stopReason,
  _Record into,
) {
  // The engine returns this as a successful String, not an error. Comparing
  // against the exported constant rather than a copied literal is what keeps a
  // silently-empty model from reporting a 38-character "reply".
  if (reply.trim() == emptyResponseSentinel) {
    into.status = _Status.empty;
    return;
  }
  if (stopReason == 'token_stall' || stopReason == 'load_stall') {
    into.status = _Status.hung;
    return;
  }

  final cleaned = reply
      .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<\|[^|]*\|>'), '')
      .trim();
  if (cleaned.length < 20) {
    into.status = _Status.empty;
    return;
  }

  final normReply = cleaned.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final normPrompt = prompt.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (normReply == normPrompt || normReply.startsWith(normPrompt)) {
    into.status = _Status.echo;
    return;
  }

  into.keywordHit = keywords.any((k) => normReply.contains(k));
  // Capped while still producing tokens means it loaded and generated, which is
  // the entire question being asked. Only stalls are failures.
  into.status = stopReason == 'absolute_cap' ? _Status.passTruncated : _Status.pass;
}

Future<void> _fetch(
  ModelDownloadManager downloads,
  String source,
  String label,
  _Record record,
) async {
  final clock = Stopwatch()..start();
  var lastBytes = 0;
  var lastProgressAt = DateTime.now();
  var lastPrintedPercent = -1;

  final entry = await downloads.ensureModel(
    ModelSource.parse(source),
    onProgress: (p) {
      final now = DateTime.now();
      if (p.receivedBytes > lastBytes) {
        lastBytes = p.receivedBytes;
        lastProgressAt = now;
      } else if (now.difference(lastProgressAt) > _downloadStall) {
        // Surfaced rather than thrown: ensureModel owns the HTTP call, so the
        // honest thing is to report the stall and let its own error surface.
        stdout.writeln('    WARNING: $label download stalled '
            '${now.difference(lastProgressAt).inSeconds}s with no bytes');
        lastProgressAt = now;
      }
      final pct = p.fraction == null ? -1 : (p.fraction! * 100).floor();
      if (pct >= 0 && pct != lastPrintedPercent && pct % 10 == 0) {
        lastPrintedPercent = pct;
        stdout.writeln('    $label $pct%  (${_gb(p.receivedBytes)} GB)');
      }
    },
  );
  clock.stop();
  if (label == 'weights') {
    record.downloadSeconds = clock.elapsed.inMilliseconds / 1000.0;
    record.downloadedBytes = entry.bytes;
  }
}

Future<void> _preflight(List<_RosterEntry> roster, ModelDownloadManager downloads) async {
  stdout.writeln('Preflight — cache status only, nothing is downloaded.\n');
  var cached = 0;
  var missingGb = 0.0;
  stdout.writeln('  status    size    model');
  for (final e in roster) {
    final hit = await downloads.get(ModelSource.parse(e.source).cacheKey);
    String projector = '';
    if (e.mmproj != null) {
      final p = await downloads.get(ModelSource.parse(e.mmproj!).cacheKey);
      projector = p == null ? '  [mmproj: missing]' : '  [mmproj: cached]';
    }
    if (hit != null) {
      cached++;
      stdout.writeln('  cached  ${_pad(e.sizeGb)}  ${e.id}$projector');
    } else {
      missingGb += e.sizeGb;
      stdout.writeln('  --      ${_pad(e.sizeGb)}  ${e.id}$projector');
    }
  }
  stdout.writeln('\n$cached of ${roster.length} cached. '
      '${missingGb.toStringAsFixed(1)} GB to download for the rest.');
}

// ---------------------------------------------------------------------------
// Roster
// ---------------------------------------------------------------------------

class _RosterEntry {
  _RosterEntry({
    required this.id,
    required this.source,
    required this.sizeGb,
    this.mmproj,
    this.modalities = const {'text'},
  });

  final String id;
  final String source;
  final String? mmproj;
  final double sizeGb;

  /// From `_INPUT_MODALITIES`. Drives which probes run — a model is only asked
  /// to look at an image or listen to a clip if it claims it can, so a wrongly
  /// declared modality shows up as a failed probe rather than being skipped.
  final Set<String> modalities;

  bool get claimsImage => modalities.contains('image');
  bool get claimsAudio => modalities.contains('audio');
}

/// Reads the roster out of the Cython model definitions so this script and the
/// server agree by construction.
///
/// Three traps, all load-bearing:
///  - Glob `.pyx` only. The generated `.c` files sit in the same directory and
///    embed the same literals in docstring comments; including them doubles the
///    roster.
///  - `ministral_3_3b_on_device.pyx` wraps its projector URI in a parenthesized
///    multi-line string, so the pattern has to tolerate `= (\n  "..."`.
///  - `size_gb` lives inside the `get_info()` body, not at module level.
List<_RosterEntry> _parseRoster(String repoRoot) {
  final dir = Directory('$repoRoot/Multi-AI/multi_ai/models');
  final sourceRe = RegExp(r'^_GGUF_SOURCE\s*=\s*\(?\s*"([^"]+)"', multiLine: true);
  final mmprojRe = RegExp(r'^_GGUF_MMPROJ_SOURCE\s*=\s*\(?\s*"([^"]+)"', multiLine: true);
  final sizeRe = RegExp(r'"size_gb"\s*:\s*([\d.]+)');
  // Matches the whole tuple; individual tokens are pulled out below. Mirrors
  // the server's own rule (`_input_modalities`) that "text" is always implied.
  final modalitiesRe = RegExp(r'^_INPUT_MODALITIES\s*=\s*\(([^)]*)\)', multiLine: true);
  final tokenRe = RegExp(r'"(\w+)"');

  final entries = <_RosterEntry>[];
  final unmatched = <String>[];
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.pyx'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final text = file.readAsStringSync();
    final source = sourceRe.firstMatch(text)?.group(1);
    if (source == null) continue; // server-only model, not part of this roster
    final id = file.uri.pathSegments.last.replaceAll('.pyx', '');
    final size = double.tryParse(sizeRe.firstMatch(text)?.group(1) ?? '');
    if (size == null) unmatched.add('$id (no size_gb)');
    final declared = modalitiesRe.firstMatch(text)?.group(1);
    entries.add(_RosterEntry(
      id: id,
      source: source,
      mmproj: mmprojRe.firstMatch(text)?.group(1),
      sizeGb: size ?? 0,
      modalities: {
        'text',
        if (declared != null)
          for (final m in tokenRe.allMatches(declared)) m.group(1)!,
      },
    ));
  }

  if (entries.length != _expectedPyxRosterSize) {
    stderr.writeln('Roster parse found ${entries.length} models, expected '
        '$_expectedPyxRosterSize. A regex probably stopped matching after a '
        'model file changed shape — fix the parser rather than the constant, '
        'unless the roster genuinely changed size.');
    exit(3);
  }
  if (unmatched.isNotEmpty) {
    stderr.writeln('Warning: incomplete metadata for ${unmatched.join(", ")}');
  }

  // The built-in model is declared only in Dart and has no .pyx, so the parse
  // above cannot see it. It is also the cheapest possible check that the
  // harness itself works, so it goes first.
  entries.insert(
    0,
    _RosterEntry(id: '_builtin_qwen2_5_0_5b', source: onDeviceModelSource, sizeGb: onDeviceModelSizeGb),
  );
  return entries;
}

/// Ordering that derisks before spending ~63GB: everything already cached
/// first, then the resumable partials, then ascending size.
const Map<int, List<String>> _waves = {
  0: [
    '_builtin_qwen2_5_0_5b',
    'gemma3n_on_device',
    'gptOSS',
    'falcon2_11b_on_device',
  ],
  1: [
    // Gemma 4 E2B leads: it is the only entry that exercises audio at all, and
    // at 3.11GB + 0.99GB projector it is the cheapest way to find out whether
    // the whole multimodal path works before larger models depend on it.
    'gemma4_e2b_on_device',
    'gemma_3_4b_on_device',
    'deepseek_r1_distill_1_5b_on_device',
    'gemma1_on_device',
    'gemma4_e4b_on_device',
  ],
  2: [
    'gemma3_on_device',
    'llama_3_2_1b_on_device',
    'falcon_h1_on_device',
    'gemma2_on_device',
    'llama_3_2_3b_on_device',
    'falcon3_on_device',
    'ministral_3_3b_on_device',
  ],
  3: [
    'mistral_7b_on_device',
    'falcon_mamba_7b_on_device',
    'falcon_7b_on_device',
    'qwen3_8b_on_device',
    'llama3_on_device',
    'llama3_1_on_device',
    'ministral_3_8b_on_device',
  ],
  4: [
    'mistral_nemo_12b_on_device',
    'ministral_3_14b_on_device',
  ],
};

List<_RosterEntry> _select(List<_RosterEntry> roster, _Args args) {
  var out = roster;
  if (args.wave != null) {
    final ids = _waves[args.wave!] ?? const [];
    out = [
      for (final id in ids)
        ...out.where((e) => e.id == id),
    ];
  }
  if (args.only.isNotEmpty) {
    out = out.where((e) => args.only.contains(e.id)).toList();
  }
  if (args.maxSizeGb != null) {
    out = out.where((e) => e.sizeGb <= args.maxSizeGb!).toList();
  }
  return out;
}

// ---------------------------------------------------------------------------
// Results
// ---------------------------------------------------------------------------

class _Status {
  static const pass = 'pass';
  static const passTruncated = 'pass_truncated';
  static const empty = 'empty';
  static const echo = 'echo';
  static const hung = 'hung';
  static const loadFail = 'load_fail';
  static const downloadFail = 'download_fail';
  static const mmprojFail = 'mmproj_fail';
  static const downloaded = 'downloaded';
}

class _Record {
  _Record({
    required this.id,
    required this.source,
    required this.declaredSizeGb,
    required this.timestamp,
    this.mmproj,
  });

  final String id;
  final String source;
  final String? mmproj;
  final double declaredSizeGb;
  final String timestamp;

  String status = _Status.loadFail;
  int? gpuLayersUsed;
  double? downloadSeconds;
  int? downloadedBytes;
  double? firstTokenSeconds;
  double? generateSeconds;
  int? tokensEmitted;
  double? tokensPerSecond;
  String? stopReason;
  bool keywordHit = false;
  String replyPreview = '';
  String? error;
  String? errorClass;
  String? mmprojError;

  /// Per-modality probe results, each a full record of its own load. Null means
  /// the model never claimed that modality, which is different from failing it.
  _Record? vision;
  _Record? audio;

  bool get isPass => status == _Status.pass || status == _Status.passTruncated;

  bool matchesSource(_RosterEntry e) => source == e.source && mmproj == e.mmproj;

  String summaryLine() {
    if (!isPass) return '$status${error == null ? '' : ': $error'}';
    final layers = gpuLayersUsed == null ? '?' : '$gpuLayersUsed';
    final tps = tokensPerSecond == null ? '?' : tokensPerSecond!.toStringAsFixed(1);
    final kw = keywordHit ? '' : ' (no keyword)';
    return '$status$kw  gpuLayers=$layers  $tps tok/s  "${_firstLine(replyPreview)}"';
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': 1,
        'id': id,
        'source': source,
        if (mmproj != null) 'mmproj': mmproj,
        'declaredSizeGb': declaredSizeGb,
        'status': status,
        'gpuLayersUsed': gpuLayersUsed,
        'downloadSeconds': downloadSeconds,
        'downloadedBytes': downloadedBytes,
        'firstTokenSeconds': firstTokenSeconds,
        'generateSeconds': generateSeconds,
        'tokensEmitted': tokensEmitted,
        'tokensPerSecond': tokensPerSecond,
        'stopReason': stopReason,
        'keywordHit': keywordHit,
        'replyPreview': replyPreview,
        'error': error,
        'errorClass': errorClass,
        'mmprojError': mmprojError,
        'timestamp': timestamp,
        if (vision != null) 'vision': vision!.toJson(),
        if (audio != null) 'audio': audio!.toJson(),
      };

  static _Record fromJson(Map<String, dynamic> j) {
    final r = _Record(
      id: j['id'] as String,
      source: j['source'] as String,
      mmproj: j['mmproj'] as String?,
      declaredSizeGb: (j['declaredSizeGb'] as num?)?.toDouble() ?? 0,
      timestamp: j['timestamp'] as String? ?? '',
    );
    r.status = j['status'] as String? ?? _Status.loadFail;
    r.gpuLayersUsed = j['gpuLayersUsed'] as int?;
    r.downloadSeconds = (j['downloadSeconds'] as num?)?.toDouble();
    r.downloadedBytes = j['downloadedBytes'] as int?;
    r.firstTokenSeconds = (j['firstTokenSeconds'] as num?)?.toDouble();
    r.generateSeconds = (j['generateSeconds'] as num?)?.toDouble();
    r.tokensEmitted = j['tokensEmitted'] as int?;
    r.tokensPerSecond = (j['tokensPerSecond'] as num?)?.toDouble();
    r.stopReason = j['stopReason'] as String?;
    r.keywordHit = j['keywordHit'] as bool? ?? false;
    r.replyPreview = j['replyPreview'] as String? ?? '';
    r.error = j['error'] as String?;
    r.errorClass = j['errorClass'] as String?;
    r.mmprojError = j['mmprojError'] as String?;
    final v = j['vision'];
    if (v is Map<String, dynamic>) r.vision = _Record.fromJson(v);
    final a = j['audio'];
    if (a is Map<String, dynamic>) r.audio = _Record.fromJson(a);
    return r;
  }
}

class _Manifest {
  _Manifest(this.records);

  final Map<String, _Record> records;

  static _Manifest load(File f) {
    if (!f.existsSync()) return _Manifest({});
    try {
      final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      return _Manifest({
        for (final e in raw.entries) e.key: _Record.fromJson(e.value as Map<String, dynamic>),
      });
    } catch (e) {
      stderr.writeln('Could not read manifest (${f.path}): $e — starting fresh.');
      return _Manifest({});
    }
  }

  void save(File f) {
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        for (final e in records.entries) e.key: e.value.toJson(),
      }),
    );
  }

  String toMarkdown() {
    final buf = StringBuffer();
    final rows = records.values.toList()
      ..sort((a, b) => b.declaredSizeGb.compareTo(a.declaredSizeGb));
    buf.writeln('\n| Model | GB | GPU layers | First token | Gen | tok/s | Verdict | Reply |');
    buf.writeln('|---|---|---|---|---|---|---|---|');
    for (final r in rows) {
      buf.writeln('| `${r.id}` | ${r.declaredSizeGb} | ${r.gpuLayersUsed ?? "—"} '
          '| ${_secs(r.firstTokenSeconds)} | ${_secs(r.generateSeconds)} '
          '| ${r.tokensPerSecond?.toStringAsFixed(1) ?? "—"} | ${r.status}'
          '${r.isPass && !r.keywordHit ? " (no keyword)" : ""} '
          '| ${_firstLine(r.replyPreview)} |');
    }
    final multimodal = rows.where((r) => r.vision != null || r.audio != null).toList();
    if (multimodal.isNotEmpty) {
      buf.writeln('\n| Model | Modality | Verdict | Reply |');
      buf.writeln('|---|---|---|---|');
      for (final r in multimodal) {
        for (final probe in [('image', r.vision), ('audio', r.audio)]) {
          if (probe.$2 == null) continue;
          buf.writeln('| `${r.id}` | ${probe.$1} | ${probe.$2!.status}'
              '${probe.$2!.isPass && !probe.$2!.keywordHit ? " (no keyword)" : ""} '
              '| ${_firstLine(probe.$2!.replyPreview)} |');
        }
      }
    }
    final counts = <String, int>{};
    for (final r in rows) {
      counts[r.status] = (counts[r.status] ?? 0) + 1;
    }
    buf.writeln('\n${counts.entries.map((e) => "${e.value} ${e.key}").join(", ")}');
    return buf.toString();
  }
}

// ---------------------------------------------------------------------------
// Test image
// ---------------------------------------------------------------------------

/// A 64x64 red circle on white, encoded as PNG at runtime.
///
/// Generated rather than embedded as a base64 blob so it is verifiably correct —
/// a hand-pasted literal can't be eyeballed. Matches the stimulus the server-side
/// vision checks used, so on-device results are directly comparable.
List<int> _redCirclePng() {
  const size = 64;
  const r = 24;
  final raw = BytesBuilder();
  for (var y = 0; y < size; y++) {
    raw.addByte(0); // PNG per-scanline filter: none
    for (var x = 0; x < size; x++) {
      final dx = x - size / 2;
      final dy = y - size / 2;
      final inside = dx * dx + dy * dy <= r * r;
      raw.add(inside ? const [220, 30, 30] : const [255, 255, 255]);
    }
  }

  List<int> chunk(String type, List<int> body) {
    final out = BytesBuilder();
    out.add(_be32(body.length));
    final typed = <int>[...ascii.encode(type), ...body];
    out.add(typed);
    out.add(_be32(_crc32(typed)));
    return out.takeBytes();
  }

  return [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ...chunk('IHDR', [
      ..._be32(size), ..._be32(size),
      8, // bit depth
      2, // colour type: truecolour RGB
      0, 0, 0,
    ]),
    ...chunk('IDAT', ZLibCodec().encode(raw.takeBytes())),
    ...chunk('IEND', const []),
  ];
}

/// One second of a 440Hz sine at 16kHz mono, as a 16-bit PCM WAV.
///
/// Same stimulus the server-side audio check used, so the two results are
/// comparable. A pure tone exercises decode -> projector -> audio encoder end to
/// end, which is the question here; it says nothing about transcription quality
/// on real speech, and a model that describes it as a beep has passed.
///
/// 16kHz because that is what mtmd's audio path expects — `llama.cpp` resamples
/// otherwise, adding a variable this probe doesn't need.
List<int> _sineWav() {
  const sampleRate = 16000;
  const seconds = 1;
  const freq = 440.0;
  const count = sampleRate * seconds;

  final pcm = BytesBuilder();
  for (var i = 0; i < count; i++) {
    // 0.3 amplitude: loud enough to be unambiguous, quiet enough not to clip.
    final v = (math.sin(2 * math.pi * freq * i / sampleRate) * 0.3 * 32767).round();
    pcm.addByte(v & 0xFF);
    pcm.addByte((v >> 8) & 0xFF);
  }
  final data = pcm.takeBytes();

  List<int> le32(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
  List<int> le16(int v) => [v & 0xFF, (v >> 8) & 0xFF];

  return [
    ...ascii.encode('RIFF'), ...le32(36 + data.length), ...ascii.encode('WAVE'),
    ...ascii.encode('fmt '), ...le32(16),
    ...le16(1), // PCM, uncompressed
    ...le16(1), // mono
    ...le32(sampleRate),
    ...le32(sampleRate * 2), // byte rate: rate * channels * bytesPerSample
    ...le16(2), // block align
    ...le16(16), // bits per sample
    ...ascii.encode('data'), ...le32(data.length), ...data,
  ];
}

List<int> _be32(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

// ---------------------------------------------------------------------------
// Plumbing
// ---------------------------------------------------------------------------

class _Args {
  bool preflight = false;
  bool report = false;
  bool force = false;
  bool downloadOnly = false;
  bool skipDownload = false;
  int? wave;
  double? maxSizeGb;
  int maxTokens = 128;
  String? manifestPath;
  Set<String> only = {};

  static _Args parse(List<String> argv) {
    final a = _Args();
    for (var i = 0; i < argv.length; i++) {
      final arg = argv[i];
      String next() => ++i < argv.length ? argv[i] : '';
      switch (arg) {
        case '--preflight':
          a.preflight = true;
        case '--report':
          a.report = true;
        case '--force':
          a.force = true;
        case '--download-only':
          a.downloadOnly = true;
        case '--skip-download':
          a.skipDownload = true;
        case '--wave':
          a.wave = int.tryParse(next());
        case '--max-size-gb':
          a.maxSizeGb = double.tryParse(next());
        case '--max-tokens':
          a.maxTokens = int.tryParse(next()) ?? 128;
        case '--manifest':
          a.manifestPath = next();
        case '--only':
          a.only = next().split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();
        case '--help' || '-h':
          stdout.writeln(_usage);
          exit(0);
        default:
          stderr.writeln('Unknown flag: $arg\n\n$_usage');
          exit(2);
      }
    }
    return a;
  }
}

const String _usage = '''
Usage: dart run tool/verify_on_device.dart [flags]   (run from app/)

  --preflight         Report cache status only; downloads nothing.
  --wave <0-4>        Run a predefined derisking wave (0 = cached only).
  --only <id,id>      Restrict to named models.
  --max-size-gb <n>   Skip anything larger.
  --download-only     Fetch weights, skip load/generate.
  --skip-download     Load/generate only against already-cached weights.
  --force             Re-verify models the manifest already records as passing.
  --max-tokens <n>    Generation cap (default 128).
  --manifest <path>   Results file (default tool/.verify_results.json).
  --report            Print the table from the existing manifest and exit.
''';

/// Walks up from the CWD looking for the models directory, so the script works
/// whether it's run from `app/` or the repo root.
String? _findRepoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    if (Directory('${dir.path}/Multi-AI/multi_ai/models').existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

String _firstLine(String s) {
  final line = s.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  final flat = line.trim().replaceAll('|', r'\|');
  return flat.length > 90 ? '${flat.substring(0, 90)}...' : flat;
}

String _secs(double? d) => d == null ? '—' : '${d.toStringAsFixed(1)}s';
String _pad(double gb) => gb.toStringAsFixed(2).padLeft(6);
String _gb(int bytes) => (bytes / (1024 * 1024 * 1024)).toStringAsFixed(2);
