import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';

/// Small on-device GGUF good enough for retrieval over a notebook's sources —
/// MIT-licensed, 384-dim, ~45MB at this quantization. Not a chat model, so it
/// deliberately stays out of `model_pool.dart`'s roster/dropdown entirely —
/// mirrors `on_device_engine.dart`'s own `onDeviceModelSource`, which is
/// likewise a plain Dart constant rather than something read off the server
/// catalog.
const String embeddingModelSource =
    'hf://ggml-org/bge-small-en-v1.5-Q8_0-GGUF/bge-small-en-v1.5-q8_0.gguf';

/// Runs the embedding GGUF in its own resident [LlamaEngine] slot, separate
/// from [OnDeviceEngine]'s chat-model slot (`on_device_engine.dart`) — a
/// notebook ingest running while the user chats must not evict, or be
/// evicted by, the chat model; the two models need to co-reside. Embedding
/// has no chat-template/history/attachment complexity and no GPU-layer
/// ladder to retry (this model is tiny next to the VRAM pressure that ladder
/// exists to handle), so this is deliberately a much smaller class than
/// `OnDeviceEngine`, not a copy of it.
class EmbeddingEngine {
  EmbeddingEngine({this.downloadManager});

  /// Threaded in on Android exactly like `OnDeviceEngine.downloadManager` —
  /// see `model_pool.dart`'s `androidModelCacheDirectory()`. Null elsewhere.
  ModelDownloadManager? downloadManager;

  LlamaEngine? _engine;

  Future<void> _ensureLoaded() async {
    if (_engine != null) return;
    final engine = LlamaEngine(LlamaBackend(), modelDownloadManager: downloadManager);
    await engine.loadModelSource(
      ModelSource.parse(embeddingModelSource),
      modelParams: const ModelParams(),
    );
    _engine = engine;
  }

  /// Embeds [text] as a unit-length vector. Downloads and loads the model on
  /// first call (through [downloadManager], if set) and keeps it resident
  /// afterward.
  Future<Float32List> embed(String text) async {
    await _ensureLoaded();
    final vector = await _engine!.embed(text, normalize: true);
    return Float32List.fromList(vector);
  }

  Future<void> dispose() async {
    await _engine?.dispose();
    _engine = null;
  }
}
