import 'dart:async';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';

// Deliberately chat_types.dart rather than api_client.dart: this file must stay
// free of Flutter so tool/verify_on_device.dart can drive the real engine under
// plain `dart run`. api_client.dart pulls package:flutter/foundation.dart.
import 'chat_types.dart';

/// Built-in on-device model: small enough to download quickly and run on a
/// phone. Always in the model list, even when the backend is unreachable.
const String onDeviceModelId = '_on_device_qwen2_5_0_5b';
const String onDeviceModelName = 'Qwen2.5 0.5B';
const String onDeviceModelSource =
    'hf://Qwen/Qwen2.5-0.5B-Instruct-GGUF/qwen2.5-0.5b-instruct-q4_k_m.gguf';
const String onDeviceModelParams = '0.5B';
const double onDeviceModelSizeGb = 0.49;
const String onDeviceModelModality = 'Text';
const int onDeviceModelContextTokens = 32768;
const String onDeviceModelLicense = 'Apache 2.0';
const String onDeviceModelStrengths =
    "Alibaba's smallest Qwen2.5 chat model, quantized to run entirely on-device with no "
    'network after the first download — lightest reasoning in the roster, built for speed.';
const String onDeviceModelSpeedProfile = 'Very fast, lightweight intelligence';

/// Models at or above this size get the hard-stop treatment on [stop] — see
/// [_hardStopGrace]. Below it, a cooperative cancel lands fast enough that
/// paying for a reload would be the slower option.
const double _hardStopMinSizeGb = 4.0;

/// How long a cancelled generation gets to wind itself down before the engine
/// is torn down. Sized to comfortably clear one decode step — the worker polls
/// the cancel flag once per generated token, so a healthy loop on a slow
/// partially-offloaded 11B (~1-3 tok/s) still wins this race and keeps the
/// model resident. Firing means the worker is wedged somewhere that never
/// polls, and the reload cost is worth paying.
const Duration _hardStopGrace = Duration(seconds: 3);

/// GPU offload counts to try, in order, when loading a model.
///
/// llamadart defaults to `gpuLayers: 999` — offload everything — which is right
/// for every model small enough to leave room beside its own weights. It isn't
/// right for the ones that nearly fill VRAM on their own: gpt-oss-20b's MXFP4
/// GGUF is ~11.3GB against ~11.7GB free on a 12GB card, so the weights fit and
/// then `llama_init_from_model` has nothing left for the KV cache, the compute
/// buffers, or the CUDA context. llama.cpp reports that as a context-creation
/// failure *after* a successful model load, which reads like a broken file
/// rather than an allocation that came up short.
///
/// There's no portable way to ask how much VRAM is free from here (0.8.11
/// exposes no such query, and the answer would be wrong on the phone targets
/// anyway), so this backs off instead of predicting: full offload, then
/// three-quarters of a typical layer stack, then a third, then pure CPU.
/// llama.cpp clamps a count above the model's layer count, so the first entry
/// keeps small models on exactly the path they took before — they succeed on
/// attempt one and never see the rest. Re-loading is cheap next to a hard
/// failure: the GGUF is already in the download cache, so a retry is a local
/// mmap, not a re-download.
const List<int> _gpuLayerLadder = [999, 24, 12, 0];

/// Per-model overrides for GGUFs whose metadata doesn't describe how the model
/// was actually trained to be prompted.
///
/// llama.cpp reads `tokenizer.chat_template` out of the GGUF and, when the key
/// is absent, silently falls back to ChatML. That fallback is wrong for any
/// model that predates ChatML: it gets fed `<|im_start|>` markers it never saw
/// in training, and — because it has no `<|im_end|>` token to emit — nothing
/// ever trips end-of-turn, so it free-associates over the unfamiliar markup
/// before (or instead of) answering.
///
/// Keyed by exact source string: the prompt shape is a property of the specific
/// GGUF build, and a different conversion of the same model may well carry
/// correct metadata.
///
/// Note this cannot be expressed as a chat *template*. `ModelParams.chatTemplate`
/// looks like the natural home for it and is silently ineffective here:
/// `LlamaEngine.create` renders its prompt Dart-side in `ChatTemplateRenderer`,
/// which reads `tokenizer.chat_template` straight out of the GGUF metadata and
/// never consults the model params. (llama_cpp_service's `applyChatTemplate`
/// does honour them, but `create` doesn't go through it.) So a quirked model
/// takes the low-level raw-prompt path instead — see [_buildRawPrompt].
final Map<String, _ModelQuirks> _quirksBySource = {
  // maddes8cht's Falcon-7B-Instruct conversion ships no chat template, so
  // llama.cpp falls back to ChatML. Falcon-7B-Instruct predates ChatML and was
  // trained on a bare `User:`/`Assistant:` transcript; fed `<|im_start|>` it
  // echoes the question back, emits stray markers, and degenerates into
  // repeating `<|im_start|>assistant` forever. Verified against the model.
  'hf://maddes8cht/tiiuae-falcon-7b-instruct-gguf/tiiuae-falcon-7b-instruct-Q4_K_M.gguf':
      _ModelQuirks(
        buildPrompt: _falconTranscript,
        // A plain transcript has no end-of-turn token, so the only thing marking
        // the end of a reply is the model starting the next speaker's line. It
        // reliably writes `\nUser` there — with no colon, since generation is
        // cut before it gets that far — so match on that rather than `\nUser:`.
        stopSequences: ['\nUser', '\nAssistant'],
      ),
};

/// Renders history plus the current turn as the `User:`/`Assistant:` transcript
/// TII trained Falcon-7B-Instruct on, ending on a bare `Assistant:` for the
/// model to continue.
String _falconTranscript(List<ChatTurn> history, String prompt) {
  final buf = StringBuffer();
  for (final turn in history) {
    buf.writeln('${turn.isUser ? 'User' : 'Assistant'}: ${turn.text}');
  }
  buf.write('User: $prompt\nAssistant:');
  return buf.toString();
}

/// Prompt-shaping overrides for one GGUF build. See [_quirksBySource].
class _ModelQuirks {
  const _ModelQuirks({required this.buildPrompt, this.stopSequences = const []});

  /// Builds the complete raw prompt, bypassing chat templating entirely.
  final String Function(List<ChatTurn> history, String prompt) buildPrompt;

  /// Strings that end generation, for models with no end-of-turn token.
  final List<String> stopSequences;
}

/// Stand-in returned when a model decodes nothing at all, so the chat shows
/// *something* rather than an empty bubble.
///
/// Named rather than inlined because it is a successful return value, not an
/// error: anything checking whether generation actually produced text has to
/// compare against this exact string, and a second copy of the literal would
/// silently stop matching the day this wording changes.
const String emptyResponseSentinel = '(model returned an empty response)';

/// Roughly 4096 tokens of prior conversation, at ~4 characters per token.
/// Matches the server's `_MAX_HISTORY_TOKENS` so a chat behaves the same
/// whichever side answers it.
const int _historyCharBudget = 4096 * 4;

/// Runs GGUF models locally via llamadart/llama.cpp — no server, and no
/// network after a model's first download. Server-roster models can opt in
/// by declaring a `_GGUF_SOURCE` (surfaced as `gguf` in /api/models).
class OnDeviceEngine {
  LlamaEngine? _engine;
  String? _loadedSource;
  String? _loadedMmproj;
  void Function()? _cancelActive;

  /// Completes when an orphaned generation (cancelled, but still listened to
  /// so the grace timer can observe it finishing) has fully torn down. A new
  /// generate() waits on this so two decode loops never overlap.
  Future<void>? _teardown;

  /// Which [_gpuLayerLadder] rung the resident model actually loaded at, or
  /// null if nothing is loaded. Diagnostic only — the app doesn't branch on it,
  /// but it's the difference between "fast" and "crawling on CPU", so the
  /// verification harness records it per model.
  int? get loadedGpuLayers => _loadedGpuLayers;
  int? _loadedGpuLayers;

  Future<void> _ensureLoaded(String source, {String? mmproj}) async {
    if (_engine != null && _loadedSource == source && _loadedMmproj == mmproj) return;
    // Only one model stays resident — a 20B GGUF and friends don't co-tenant
    // nicely in laptop/phone RAM.
    await _engine?.dispose();
    _engine = null;
    _loadedMmproj = null;

    Object? lastError;
    StackTrace? lastStack;
    for (final gpuLayers in _gpuLayerLadder) {
      final engine = LlamaEngine(LlamaBackend());
      try {
        await engine.loadModelSource(
          ModelSource.parse(source),
          modelParams: ModelParams(gpuLayers: gpuLayers),
        );
        if (mmproj != null) {
          // The projector is a second GGUF that has to be on disk before
          // loadMultimodalProjector can take it — it wants a local path, not a
          // ModelSource, so the download goes through the engine's own manager.
          final entry = await engine.modelDownloadManager.ensureModel(ModelSource.parse(mmproj));
          await engine.loadMultimodalProjector(entry.filePath);
          _loadedMmproj = mmproj;
        }
        _engine = engine;
        _loadedSource = source;
        _loadedGpuLayers = gpuLayers;
        return;
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        _loadedMmproj = null;
        _loadedGpuLayers = null;
        await engine.dispose();
      }
    }
    Error.throwWithStackTrace(lastError!, lastStack!);
  }

  Future<String> generate(
    String prompt, {
    String source = onDeviceModelSource,
    double? sizeGb,
    String? mmproj,
    List<Attachment> attachments = const [],
    List<ChatTurn> history = const [],
    int maxTokens = 1024,
    void Function(String chunk)? onToken,
  }) async {
    // A previous stop() may still be winding down; two concurrent decode loops
    // on one engine would interleave their tokens.
    await _teardown;
    await _ensureLoaded(source, mmproj: mmproj);
    final quirks = _quirksBySource[source];
    final buffer = StringBuffer();
    final done = Completer<String>();
    final finished = Completer<void>();
    void markFinished() {
      if (!finished.isCompleted) finished.complete();
    }

    // A cap, not a target — generation still stops at end-of-turn, so short
    // replies stay fast; this just avoids truncating long ones.
    final params = GenerationParams(
      maxTokens: maxTokens,
      temp: 0.7,
      stopSequences: quirks?.stopSequences ?? const [],
    );
    final fitted = _fitHistory(history);

    // Both branches produce plain text chunks, so everything downstream —
    // buffering, onToken, cancellation — is shared.
    final Stream<String> tokens;
    if (quirks != null) {
      // Raw-prompt path: this model's GGUF describes a prompt shape it wasn't
      // trained on, so the transcript is built here instead. Text-only, which
      // is all these models offer — [_buildMessage]'s media handling belongs to
      // the templated path.
      tokens = _engine!.generate(quirks.buildPrompt(fitted, prompt), params: params);
    } else {
      tokens = _engine!
          .create(
            [
              for (final turn in fitted)
                LlamaChatMessage.fromText(
                  role: turn.isUser ? LlamaChatRole.user : LlamaChatRole.assistant,
                  text: turn.text,
                ),
              _buildMessage(prompt, attachments),
            ],
            params: params,
          )
          .map((chunk) => chunk.choices.first.delta.content ?? '');
    }

    final sub = tokens.listen(
          null,
          onDone: () {
            if (!done.isCompleted) done.complete(buffer.toString());
            markFinished();
          },
          onError: (Object e, StackTrace st) {
            if (!done.isCompleted) done.completeError(e, st);
            markFinished();
          },
        );
    // onToken fires per decoded chunk. The engine itself doesn't need it — the
    // buffer is what gets returned — but it's the only signal from outside that
    // decoding is still progressing, which is what lets a caller tell a slow
    // model apart from a wedged one.
    sub.onData((text) {
      buffer.write(text);
      onToken?.call(text);
    });

    // Complete with whatever was generated so far so the pending future never
    // hangs, then stop the token loop. Both stop paths return immediately —
    // the caller's UI must not wait on llama.cpp noticing.
    _cancelActive = () {
      if (!done.isCompleted) done.complete(buffer.toString());
      if ((sizeGb ?? 0) < _hardStopMinSizeGb) {
        // Small model: cancelling the subscription trips the same cancel flag
        // via llamadart's onCancel, and a fast decode loop sees it within a
        // token or two.
        sub.cancel();
        markFinished();
        return;
      }
      // Large model: the worker polls the cancel flag only once per generated
      // token, and not at all during prompt eval — on a partially-offloaded
      // 11B that can be seconds of pegged CPU. Ask nicely, keep listening so
      // onDone/onError tells us it really stopped, and kill the worker isolate
      // if it doesn't. Cancelling the subscription here would detach that
      // signal, so it is deliberately left alive.
      _engine?.cancelGeneration();
      _teardown = _hardStopAfterGrace(sub, finished);
    };
    try {
      final reply = _trimStopMarker(await done.future, quirks?.stopSequences ?? const []).trim();
      return reply.isEmpty ? emptyResponseSentinel : reply;
    } finally {
      _cancelActive = null;
    }
  }

  /// Strips a trailing stop sequence off a finished reply.
  ///
  /// llama.cpp's decode loop yields each token's bytes downstream *before* it
  /// tests them against the stop sequences, and never retracts what it already
  /// emitted — so the text that triggered the stop is always in the buffer by
  /// the time generation halts. Declaring a stop sequence ends generation; it
  /// does not keep the marker out of the reply. That cleanup has to happen
  /// here.
  ///
  /// Only a trailing match is removed: a marker in the middle of a reply is
  /// something the model chose to write, not the artifact this exists to hide.
  String _trimStopMarker(String reply, List<String> stopSequences) {
    var out = reply.trimRight();
    // One pass per sequence isn't enough — trimming `<|im_end|>` can uncover a
    // `\nUser:` that preceded it — so keep going until nothing more matches.
    var trimmed = true;
    while (trimmed) {
      trimmed = false;
      for (final stop in stopSequences) {
        if (stop.isNotEmpty && out.endsWith(stop)) {
          out = out.substring(0, out.length - stop.length).trimRight();
          trimmed = true;
        }
      }
    }
    return out;
  }

  /// Trims the oldest turns so a long chat can't overrun the context window.
  ///
  /// Measured in characters, not tokens: there's no tokenizer on this side of
  /// the boundary (llama.cpp owns it, behind the FFI), and roughly 4 characters
  /// per token is close enough for a budget whose job is only to bound growth.
  /// Deliberately conservative — overshooting costs a truncated reply, while
  /// undershooting only costs a little recall.
  List<ChatTurn> _fitHistory(List<ChatTurn> history) {
    var budget = _historyCharBudget;
    final kept = <ChatTurn>[];
    // Walk backwards so the newest turns — the ones the reply depends on —
    // are the ones that survive.
    for (final turn in history.reversed) {
      budget -= turn.text.length;
      if (budget < 0) break;
      kept.insert(0, turn);
    }
    // Never open on an assistant turn: a reply with no question above it
    // reads as the model talking to itself.
    while (kept.isNotEmpty && !kept.first.isUser) {
      kept.removeAt(0);
    }
    return kept;
  }

  /// Builds the user turn. Plain text stays on the text-only constructor —
  /// the same call this used before multimodal existed — so a model with no
  /// projector loaded takes exactly the path it always did.
  ///
  /// Media goes through as bytes rather than a path: an attachment may have
  /// come from a recording or a picker that only handed back bytes, and
  /// llamadart decodes either. Audio takes encoded bytes (WAV/MP3) on the same
  /// footing as raw samples, so a clip needs no decoding on this side.
  ///
  /// Passing audio through is not the same as promising it works: the loaded
  /// projector decides that, and llama.cpp answers it at runtime via
  /// `mtmd_support_audio`. Which modalities a model *offers* is gated earlier,
  /// off the roster's `input_modalities` — a model whose GGUF repo ships no
  /// audio-capable projector should never declare `audio` in the first place.
  LlamaChatMessage _buildMessage(String prompt, List<Attachment> attachments) {
    final images = attachments.where((a) => a.kind == AttachmentKind.image);
    final audio = attachments.where((a) => a.kind == AttachmentKind.audio);
    if (images.isEmpty && audio.isEmpty) {
      return LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt);
    }
    return LlamaChatMessage.withContent(
      role: LlamaChatRole.user,
      content: [
        for (final image in images) LlamaImageContent(bytes: Uint8List.fromList(image.bytes)),
        for (final clip in audio) LlamaAudioContent(bytes: Uint8List.fromList(clip.bytes)),
        LlamaTextContent(prompt),
      ],
    );
  }

  /// Waits out [_hardStopGrace] for a cancelled generation to end on its own;
  /// disposes the engine if it doesn't. The next [generate] then reloads the
  /// model, which is the price of guaranteeing the worker is gone.
  ///
  /// Note this is a backstop, not a preemption: llamadart's dispose waits for
  /// the worker to ack before killing its isolate, and the worker finishes any
  /// in-flight generation first. It bounds a wedged worker (prompt eval never
  /// polls the cancel flag at all) rather than interrupting a running decode.
  /// Either way the caller is already unblocked — this runs off [_teardown].
  Future<void> _hardStopAfterGrace(
    StreamSubscription<dynamic> sub,
    Completer<void> finished,
  ) async {
    final stopped = await Future.any([
      finished.future.then((_) => true),
      Future<bool>.delayed(_hardStopGrace, () => false),
    ]);
    if (stopped) {
      await sub.cancel();
      return;
    }
    await sub.cancel();
    await dispose();
  }

  /// Stops the in-flight generation, if any. The pending [generate] future
  /// completes with the partial text produced so far, synchronously — large
  /// models then tear down in the background via [_hardStopAfterGrace].
  void stop() => _cancelActive?.call();

  Future<void> dispose() async {
    await _engine?.dispose();
    _engine = null;
    _loadedSource = null;
    _loadedMmproj = null;
    _loadedGpuLayers = null;
  }
}
