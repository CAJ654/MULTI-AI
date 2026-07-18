import 'dart:async';

import 'package:llamadart/llamadart.dart';

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

/// Runs GGUF models locally via llamadart/llama.cpp — no server, and no
/// network after a model's first download. Server-roster models can opt in
/// by declaring a `_GGUF_SOURCE` (surfaced as `gguf` in /api/models).
class OnDeviceEngine {
  LlamaEngine? _engine;
  String? _loadedSource;
  void Function()? _cancelActive;

  /// Completes when an orphaned generation (cancelled, but still listened to
  /// so the grace timer can observe it finishing) has fully torn down. A new
  /// generate() waits on this so two decode loops never overlap.
  Future<void>? _teardown;

  Future<void> _ensureLoaded(String source) async {
    if (_engine != null && _loadedSource == source) return;
    // Only one model stays resident — a 20B GGUF and friends don't co-tenant
    // nicely in laptop/phone RAM.
    await _engine?.dispose();
    _engine = null;
    final engine = LlamaEngine(LlamaBackend());
    await engine.loadModelSource(ModelSource.parse(source));
    _engine = engine;
    _loadedSource = source;
  }

  Future<String> generate(
    String prompt, {
    String source = onDeviceModelSource,
    double? sizeGb,
  }) async {
    // A previous stop() may still be winding down; two concurrent decode loops
    // on one engine would interleave their tokens.
    await _teardown;
    await _ensureLoaded(source);
    final buffer = StringBuffer();
    final done = Completer<String>();
    final finished = Completer<void>();
    void markFinished() {
      if (!finished.isCompleted) finished.complete();
    }

    final sub = _engine!
        .create(
          [LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt)],
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
  }
}
