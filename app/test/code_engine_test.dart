import 'package:flutter_test/flutter_test.dart';

import 'package:multi_ai/addons/code/code_engine.dart';
import 'package:multi_ai/addons/code/llama_server_supervisor.dart';
import 'package:multi_ai/addons/code/opencode_client.dart';
import 'package:multi_ai/addons/code/opencode_process_supervisor.dart';
import 'package:multi_ai/api_client.dart';

class _FakeLlama extends LlamaServerSupervisor {
  final started = <String>[];

  @override
  Future<void> start(String ggufPath, {Duration timeout = const Duration(seconds: 90)}) async {
    started.add(ggufPath);
  }

  @override
  Future<void> stop() async {}
}

class _FakeOpencode extends OpencodeProcessSupervisor {
  final starts = <Set<String>>[];

  @override
  Future<void> start({
    Set<String> serverModelIds = const {},
    Duration timeout = const Duration(seconds: 20),
  }) async {
    starts.add(serverModelIds);
  }

  @override
  Future<void> stop() async {}
}

class _NoopClient implements OpencodeClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const _server = ModelInfo(id: 'qwen3_8b', name: 'Qwen3 8B', hasServerWeights: true);

void main() {
  late _FakeLlama llama;
  late _FakeOpencode opencode;

  LocalCodeEngine build(Future<Set<String>> Function() fetch) {
    llama = _FakeLlama();
    opencode = _FakeOpencode();
    return LocalCodeEngine(
      llamaServer: llama,
      opencode: opencode,
      client: _NoopClient(),
      fetchServerModelIds: fetch,
    );
  }

  test('a server model gets the server provider and its own id', () {
    final engine = build(() async => {});
    expect(engine.providerIdFor(_server), OpencodeProcessSupervisor.serverProviderId);
    expect(engine.modelIdFor(_server), 'qwen3_8b');
  });

  test('an on-device model keeps the local provider and fixed id', () {
    final engine = build(() async => {});
    const onDevice = ModelInfo(id: 'x', name: 'X', gguf: 'hf://a/b/c.gguf');
    expect(engine.providerIdFor(onDevice), OpencodeProcessSupervisor.providerId);
    expect(engine.modelIdFor(onDevice), OpencodeProcessSupervisor.modelId);
  });

  test('a server model skips llama-server and registers the backend roster with opencode',
      () async {
    final engine = build(() async => {'qwen3_8b', 'qwen3_4b'});
    await engine.ensureRunning(model: _server);
    expect(llama.started, isEmpty);
    expect(opencode.starts.single, {'qwen3_8b', 'qwen3_4b'});
  });

  test('a server model the backend does not serve is a clear StateError', () async {
    final engine = build(() async => {'something_else'});
    await expectLater(engine.ensureRunning(model: _server), throwsStateError);
    expect(opencode.starts, isEmpty);
  });

  test('an unreachable backend is a StateError that says so', () async {
    final engine = build(() async => throw Exception('connection refused'));
    await expectLater(
      engine.ensureRunning(model: _server),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('connection refused'))),
    );
    expect(opencode.starts, isEmpty);
  });
}
