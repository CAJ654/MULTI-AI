import 'dart:async';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';

import 'api_client.dart' show Attachment, AttachmentKind, ChatTurn;

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
        return;
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        _loadedMmproj = null;
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
  }) async {
    // A previous stop() may still be winding down; two concurrent decode loops
    // on one engine would interleave their tokens.
    await _teardown;
    await _ensureLoaded(source, mmproj: mmproj);
    final buffer = StringBuffer();
    final done = Completer<String>();
    final finished = Completer<void>();
    void markFinished() {
      if (!finished.isCompleted) finished.complete();
    }

    final sub = _engine!
        .create(
          [
            for (final turn in _fitHistory(history))
              LlamaChatMessage.fromText(
                role: turn.isUser ? LlamaChatRole.user : LlamaChatRole.assistant,
                text: turn.text,
              ),
            _buildMessage(prompt, attachments),
          ],
          // A cap, not a target — generation still stops at end-of-turn, so
          // short replies stay fast; this just avoids truncating long ones.
          params: const GenerationParams(maxTokens: 1024, temp: 0.7),
        )
        .listen(
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
    sub.onData((chunk) => buffer.write(chunk.choices.first.delta.content ?? ''));

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
      final reply = (await done.future).trim();
      return reply.isEmpty ? '(model returned an empty response)' : reply;
    } finally {
      _cancelActive = null;
    }
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
  /// Images go through as bytes rather than a path: an attachment may have
  /// come from a recording or a picker that only handed back bytes, and
  /// llamadart decodes either.
  LlamaChatMessage _buildMessage(String prompt, List<Attachment> attachments) {
    final images = attachments.where((a) => a.kind == AttachmentKind.image);
    if (images.isEmpty) {
      return LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt);
    }
    return LlamaChatMessage.withContent(
      role: LlamaChatRole.user,
      content: [
        for (final image in images) LlamaImageContent(bytes: Uint8List.fromList(image.bytes)),
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
  }
}
