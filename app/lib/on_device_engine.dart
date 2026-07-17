import 'dart:async';

import 'package:llamadart/llamadart.dart';

/// Built-in on-device model: small enough to download quickly and run on a
/// phone. Always in the model list, even when the backend is unreachable.
const String onDeviceModelId = '_on_device_qwen2_5_0_5b';
const String onDeviceModelName = 'Qwen2.5 0.5B (on-device)';
const String onDeviceModelSource =
    'hf://Qwen/Qwen2.5-0.5B-Instruct-GGUF/qwen2.5-0.5b-instruct-q4_k_m.gguf';

/// Runs GGUF models locally via llamadart/llama.cpp — no server, and no
/// network after a model's first download. Server-roster models can opt in
/// by declaring a `_GGUF_SOURCE` (surfaced as `gguf` in /api/models).
class OnDeviceEngine {
  LlamaEngine? _engine;
  String? _loadedSource;
  void Function()? _cancelActive;

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

  Future<String> generate(String prompt, {String source = onDeviceModelSource}) async {
    await _ensureLoaded(source);
    final buffer = StringBuffer();
    final done = Completer<String>();
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
          },
          onError: (Object e, StackTrace st) {
            if (!done.isCompleted) done.completeError(e, st);
          },
        );
    sub.onData((chunk) => buffer.write(chunk.choices.first.delta.content ?? ''));
    // Cancelling the stream subscription stops the token loop; complete with
    // whatever was generated so far so the pending future doesn't hang.
    _cancelActive = () {
      sub.cancel();
      if (!done.isCompleted) done.complete(buffer.toString());
    };
    try {
      final reply = (await done.future).trim();
      return reply.isEmpty ? '(model returned an empty response)' : reply;
    } finally {
      _cancelActive = null;
    }
  }

  /// Stops the in-flight generation, if any. The pending [generate] future
  /// completes with the partial text produced so far.
  void stop() => _cancelActive?.call();

  Future<void> dispose() async {
    await _engine?.dispose();
    _engine = null;
    _loadedSource = null;
  }
}
