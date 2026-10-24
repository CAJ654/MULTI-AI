import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';
import 'package:multi_ai/addons/antigravity/antigravity_controller.dart';
import 'package:multi_ai/addons/antigravity/antigravity_settings.dart';
import 'package:multi_ai/api_client.dart';
import 'package:multi_ai/model_pool.dart';

class _FakeApi extends ApiClient {
  final sent = <String>[];

  @override
  Future<List<ModelInfo>> fetchModels() async => const [ModelInfo(id: 'alpha', name: 'Alpha')];

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
  }) async {
    sent.add('$model:$message');
    return 'pong';
  }
}

class _NoDownloads extends ThrowingModelDownloadManager {
  const _NoDownloads();

  @override
  Future<ModelCacheEntry?> get(String cacheKey, {String? cacheDirectory}) async => null;
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  late _FakeApi api;
  late ModelPool pool;
  late InMemoryAntigravitySettingsStore store;
  late AntigravityController controller;

  setUp(() async {
    api = _FakeApi();
    pool = ModelPool(api: api, downloadManager: const _NoDownloads());
    await pool.refresh();
    store = InMemoryAntigravitySettingsStore();
    // Port 0 so tests never fight over 8200.
    await store.save((await store.load()).copyWith(port: 0));
    controller = AntigravityController(modelPool: pool, store: store);
    await _settle();
  });

  tearDown(() async {
    controller.dispose();
    pool.dispose();
  });

  Future<HttpClientResponse> get(String path, {String? token}) async {
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(Uri.parse('${controller.baseUrl}$path'));
    request.headers.set('authorization', 'Bearer ${token ?? controller.settings.bearerToken}');
    return request.close();
  }

  test('starts stopped, loads and keeps the saved settings', () {
    expect(controller.state, AntigravityServerState.stopped);
    expect(controller.settings.port, 0);
    expect(controller.settings.bearerToken, hasLength(64));
  });

  test('start serves pool models over HTTP and logs the request; stop shuts it down', () async {
    await controller.start();
    expect(controller.running, isTrue);

    final r = await get('/models');
    expect(r.statusCode, 200);
    final body = jsonDecode(await r.transform(utf8.decoder).join()) as Map<String, dynamic>;
    expect([for (final m in body['data'] as List) (m as Map)['id']], contains('alpha'));
    await _settle();
    expect(controller.log.single.path, '/v1/models');

    await controller.stop();
    expect(controller.state, AntigravityServerState.stopped);
    await expectLater(get('/models'), throwsA(isA<SocketException>()));
  });

  test('a chat completion reaches the pool and back', () async {
    await controller.start();
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.postUrl(Uri.parse('${controller.baseUrl}/chat/completions'));
    request.headers.set('authorization', 'Bearer ${controller.settings.bearerToken}');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'model': 'alpha',
      'messages': [
        {'role': 'user', 'content': 'ping'},
      ],
    }));
    final response = await request.close();
    final body = jsonDecode(await response.transform(utf8.decoder).join()) as Map<String, dynamic>;
    expect((((body['choices'] as List).single as Map)['message'] as Map)['content'], 'pong');
    expect(api.sent, ['alpha:ping']);
  });

  test('regenerating the key invalidates the old one immediately and persists', () async {
    await controller.start();
    final old = controller.settings.bearerToken;
    await controller.regenerateToken();
    expect(controller.settings.bearerToken, isNot(old));
    expect((await store.load()).bearerToken, controller.settings.bearerToken);
    expect((await get('/models', token: old)).statusCode, 401);
    expect((await get('/models')).statusCode, 200);
  });

  test('a taken port lands in the error state with a message', () async {
    final blocker = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(blocker.close);
    await store.save((await store.load()).copyWith(port: blocker.port));
    final second = AntigravityController(modelPool: pool, store: store);
    addTearDown(second.dispose);
    await _settle();
    await second.start();
    expect(second.state, AntigravityServerState.error);
    expect(second.error, contains('already in use'));
  });

  test('the port cannot change while running', () async {
    await controller.start();
    await controller.setPort(9999);
    expect(controller.settings.port, 0);
  });
}
