import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';

import 'package:multi_ai/addons/chat/chat_controller.dart';
import 'package:multi_ai/api_client.dart';
import 'package:multi_ai/chat_store.dart';
import 'package:multi_ai/model_pool.dart';
import 'package:multi_ai/thinking_settings.dart';

/// Answers every chat request with a canned, identifiable reply.
class _RecordingApi extends ApiClient {
  _RecordingApi(this._models);
  final List<ModelInfo> _models;

  @override
  Future<List<ModelInfo>> fetchModels() async => _models;

  @override
  Future<DeviceSpecs> fetchDeviceSpecs() async => const DeviceSpecs();

  @override
  Future<ServerModelCacheStatus> getServerModelCacheStatus(String modelId) async =>
      const ServerModelCacheStatus(cached: true);

  @override
  Future<String> sendChat({
    required String model,
    required String message,
    List<Attachment> attachments = const [],
    List<ChatTurn> history = const [],
  }) async =>
      '[$model answers]';
}

/// Reports every cache-status check as a hit, so the pool counts the
/// declared server model as downloadable without touching real disk.
class _AlwaysDownloaded extends ThrowingModelDownloadManager {
  const _AlwaysDownloaded();

  @override
  Future<ModelCacheEntry?> get(String cacheKey, {String? cacheDirectory}) async {
    final now = DateTime.now();
    return ModelCacheEntry(
      sourceCanonicalKey: cacheKey,
      cacheKey: cacheKey,
      fileName: 'fake.gguf',
      filePath: 'fake.gguf',
      createdAt: now,
      updatedAt: now,
    );
  }
}

const _model = ModelInfo(id: 'alpha', name: 'Alpha');

void main() {
  test('a sent message persists through InMemoryChatStore and reloads into a fresh controller', () async {
    // Same store instance shared between two independent controllers — this
    // is what a real app restart looks like: a new ChatController reading
    // whatever the previous one last saved.
    final sharedStore = InMemoryChatStore();

    final api = _RecordingApi([_model]);
    final pool = ModelPool(api: api, downloadManager: const _AlwaysDownloaded());
    await pool.refresh();

    final first = ChatController(
      pool: pool,
      store: sharedStore,
      thinkingSettingsStore: InMemoryThinkingSettingsStore(),
    );
    await first.start();
    first.selectModel(_model);
    first.textController.text = 'What is the capital of France?';
    await first.send();

    expect(first.session.messages, isNotEmpty);
    expect(first.session.messages.first.text, 'What is the capital of France?');

    final second = ChatController(
      pool: pool,
      store: sharedStore,
      thinkingSettingsStore: InMemoryThinkingSettingsStore(),
    );
    await second.start();

    // The fresh controller starts with one empty session on top (same rule
    // newSession() follows), then the restored history below it.
    final restored = second.sessions.firstWhere((s) => s.messages.isNotEmpty);
    expect(restored.messages.first.text, 'What is the capital of France?');
    expect(restored.messages.first.isUser, isTrue);
    expect(restored.messages.any((m) => m.text == '[alpha answers]'), isTrue);
  });
}
