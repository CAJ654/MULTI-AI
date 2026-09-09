import 'package:llamadart/llamadart.dart';

import '../../api_client.dart' show ModelInfo;
import '../../model_pool.dart';
import 'llama_server_supervisor.dart';
import 'opencode_client.dart';
import 'opencode_process_supervisor.dart';

/// What `CodeAgentController` needs to run a turn: somewhere to talk opencode
/// over HTTP ([client]), the provider/model ids that endpoint is registered
/// under, and a way to make sure both backing processes are up before using
/// it. Abstract so the controller stays unit-testable without spawning real
/// subprocesses — mirrors how `ProjectRootSource` is faked for the same
/// reason. [LocalCodeEngine] is the real implementation.
abstract class CodeEngine {
  OpencodeClient get client;
  String get providerId;
  String get modelId;

  /// Resolves [model]'s cached GGUF file, starts/reuses `llama-server` for
  /// it, then starts/reuses `opencode serve` — in that order, so opencode is
  /// never asked to relay a message before there's a model behind it.
  ///
  /// Throws [StateError] if [model] isn't an on-device model — the Code tab
  /// only supports on-device (GGUF) models; server-side (`_REPO_ID`)
  /// transformers models have no OpenAI-compatible tool-calling endpoint
  /// today. See the README's "Code tab" section.
  Future<void> ensureRunning({required ModelInfo model});

  Future<void> stop();
}

/// Composes the two child processes the opencode-backed Code tab needs —
/// `llama-server` (serving the selected on-device model) and `opencode
/// serve` (running the actual agent loop against it). Lazy and
/// reuse-or-restart, mirroring `server.pyx`'s `_ensure_colibri_running`:
/// nothing spawns until the first message is sent, and an already-correct
/// process is left alone rather than bounced.
class LocalCodeEngine implements CodeEngine {
  LocalCodeEngine({
    LlamaServerSupervisor? llamaServer,
    OpencodeProcessSupervisor? opencode,
    OpencodeClient? client,
  })  : _llamaServer = llamaServer ?? LlamaServerSupervisor(),
        _opencode = opencode ?? OpencodeProcessSupervisor(),
        client = client ?? HttpOpencodeClient(baseUrl: OpencodeProcessSupervisor.baseUrl);

  final LlamaServerSupervisor _llamaServer;
  final OpencodeProcessSupervisor _opencode;

  @override
  final OpencodeClient client;

  @override
  String get providerId => OpencodeProcessSupervisor.providerId;
  @override
  String get modelId => OpencodeProcessSupervisor.modelId;

  @override
  Future<void> ensureRunning({required ModelInfo model}) async {
    final source = ModelPool.localSourceOf(model);
    if (source == null) {
      throw StateError(
        '${model.name} has no on-device weights — the Code tab only works '
        'with on-device (GGUF) models.',
      );
    }
    final ggufPath = await _resolveGgufPath(source);
    await _llamaServer.start(ggufPath);
    await _opencode.start();
  }

  Future<String> _resolveGgufPath(String hfSource) async {
    // The same cache llamadart's own on-device chat engine uses (see
    // on_device_engine.dart's identical ensureModel call for its mmproj
    // file) — a cache hit here, not a fresh download, since the Code tab
    // only lists models `ModelPool` already reports as downloaded.
    final manager = DefaultModelDownloadManager();
    final entry = await manager.ensureModel(ModelSource.parse(hfSource));
    return entry.filePath;
  }

  @override
  Future<void> stop() async {
    await _opencode.stop();
    await _llamaServer.stop();
    await client.close();
  }
}
