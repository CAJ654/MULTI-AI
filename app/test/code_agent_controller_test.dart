import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';

import 'package:multi_ai/addons/code/code_agent_controller.dart';
import 'package:multi_ai/addons/code/code_session_store.dart';
import 'package:multi_ai/addons/code/project_root_source.dart';
import 'package:multi_ai/addons/code/tool_approval.dart';
import 'package:multi_ai/api_client.dart';
import 'package:multi_ai/model_pool.dart';

/// Returns each entry in [replies] in order, one per call, then repeats the
/// last one — a coding turn is usually a request/response pair (a tool call,
/// then a final answer), so tests script exactly that sequence.
class _RecordingApi extends ApiClient {
  _RecordingApi(this._models, this.replies);

  final List<ModelInfo> _models;
  final List<String> replies;
  int _replyIndex = 0;
  final calls = <String>[];

  /// When set, sendChat waits on this instead of returning — lets a test hold
  /// a run open to exercise stop().
  Completer<String>? gate;

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
  }) async {
    calls.add(message);
    final g = gate;
    if (g != null) return g.future;
    final reply = replies[_replyIndex.clamp(0, replies.length - 1)];
    if (_replyIndex < replies.length - 1) _replyIndex++;
    return reply;
  }
}

class _NoDownloads extends ThrowingModelDownloadManager {
  const _NoDownloads();

  @override
  Future<ModelCacheEntry?> get(String cacheKey, {String? cacheDirectory}) async => null;
}

class _FakeRootSource implements ProjectRootSource {
  _FakeRootSource(this.path);
  final String? path;

  @override
  Future<String?> pickDirectory() async => path;
}

/// Returns each path in [paths] in order, one per call, then repeats the
/// last one — for tests exercising a second `pickProjectRoot()` that lands
/// somewhere new.
class _SequentialRootSource implements ProjectRootSource {
  _SequentialRootSource(this.paths);
  final List<String> paths;
  int _index = 0;

  @override
  Future<String?> pickDirectory() async {
    final path = paths[_index.clamp(0, paths.length - 1)];
    if (_index < paths.length - 1) _index++;
    return path;
  }
}

const _alpha = ModelInfo(id: 'alpha', name: 'Alpha');

String _toolCall(String name, Map<String, dynamic> args) {
  final entries = args.entries.map((e) => '"${e.key}": "${e.value}"').join(', ');
  return '<tool_call>\n{"name": "$name", "arguments": {$entries}}\n</tool_call>';
}

Future<(CodeAgentController, _RecordingApi, Directory)> _buildReady(
  List<String> replies, {
  String? root,
}) async {
  final tempRoot = root == null ? await Directory.systemTemp.createTemp('code_agent_test') : null;
  final api = _RecordingApi([_alpha], replies);
  final pool = ModelPool(api: api, downloadManager: const _NoDownloads());
  await pool.refresh();
  final controller = CodeAgentController(
    pool: pool,
    projectRootSource: _FakeRootSource(root ?? tempRoot!.path),
  )..start();
  await controller.pickProjectRoot();
  controller.selectModel('alpha');
  return (controller, api, tempRoot ?? Directory(root!));
}

void main() {
  test('canSend needs both a project root and a model', () async {
    final api = _RecordingApi([_alpha], ['ok']);
    final pool = ModelPool(api: api, downloadManager: const _NoDownloads());
    await pool.refresh();
    final tempRoot = await Directory.systemTemp.createTemp('code_agent_test');
    addTearDown(() => tempRoot.delete(recursive: true));

    final controller = CodeAgentController(
      pool: pool,
      projectRootSource: _FakeRootSource(tempRoot.path),
    )..start();
    expect(controller.canSend, isFalse);

    await controller.pickProjectRoot();
    expect(controller.canSend, isFalse, reason: 'no model chosen yet');

    controller.selectModel('alpha');
    expect(controller.canSend, isTrue);
  });

  test('a tool-call turn followed by a final answer updates the transcript in order', () async {
    final (controller, api, root) = await _buildReady([
      _toolCall('list_dir', {'path': '.'}),
      'Found some files.',
    ]);
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/a.txt').create();

    await controller.send('list the files');

    expect(controller.running, isFalse);
    expect(controller.error, isNull);
    expect(controller.transcript, hasLength(3));
    expect(controller.transcript[0], isA<UserTranscriptEntry>());
    final toolEntry = controller.transcript[1] as ToolCallTranscriptEntry;
    expect(toolEntry.name, 'list_dir');
    expect(toolEntry.status, ToolCallStatus.done);
    expect(toolEntry.resultText, contains('a.txt'));
    final answer = controller.transcript[2] as AssistantTextTranscriptEntry;
    expect(answer.text, 'Found some files.');
  });

  test('a gated tool call waits for approval before touching the filesystem', () async {
    final (controller, _, root) = await _buildReady([
      _toolCall('write_file', {'path': 'out.txt', 'content': 'hello'}),
      'Done.',
    ]);
    addTearDown(() => root.delete(recursive: true));

    ToolApprovalRequest? request;
    controller.approvalRequests.listen((r) => request = r);

    final run = controller.send('write a file');
    // Let the event loop advance to the point where the hook has pushed the
    // approval request and is awaiting a decision. A zero-duration delay
    // isn't enough on its own — send() awaits a real directory listing
    // (CodeAgentController._describeProjectRoot) before the model even sees
    // the message, and that's genuine dart:io I/O rather than a microtask.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(request, isNotNull);
    expect(request!.toolName, 'write_file');
    expect(await File('${root.path}/out.txt').exists(), isFalse);
    final toolEntry = controller.transcript.whereType<ToolCallTranscriptEntry>().single;
    expect(toolEntry.status, ToolCallStatus.awaitingApproval);

    request!.completer.complete(ToolApprovalDecision.allowOnce);
    await run;

    expect(await File('${root.path}/out.txt').readAsString(), 'hello');
    expect(toolEntry.status, ToolCallStatus.done);
  });

  test('denying a gated call refuses it without running the tool, and the model still replies',
      () async {
    final (controller, _, root) = await _buildReady([
      _toolCall('write_file', {'path': 'out.txt', 'content': 'hello'}),
      'Okay, skipping that.',
    ]);
    addTearDown(() => root.delete(recursive: true));

    ToolApprovalRequest? request;
    controller.approvalRequests.listen((r) => request = r);

    final run = controller.send('write a file');
    // See the identical wait in the test above — send() awaits a real
    // directory listing before the model runs, so this needs actual elapsed
    // time, not just a microtask turn.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    request!.completer.complete(ToolApprovalDecision.deny);
    await run;

    expect(await File('${root.path}/out.txt').exists(), isFalse);
    final toolEntry = controller.transcript.whereType<ToolCallTranscriptEntry>().single;
    expect(toolEntry.status, ToolCallStatus.denied);
    final answer = controller.transcript.whereType<AssistantTextTranscriptEntry>().single;
    expect(answer.text, 'Okay, skipping that.');
  });

  test('allowForSession means a second call to the same tool in the same run is not re-prompted',
      () async {
    final (controller, _, root) = await _buildReady([
      _toolCall('write_file', {'path': 'a.txt', 'content': '1'}),
      _toolCall('write_file', {'path': 'b.txt', 'content': '2'}),
      'Wrote both files.',
    ]);
    addTearDown(() => root.delete(recursive: true));

    final requests = <ToolApprovalRequest>[];
    controller.approvalRequests.listen(requests.add);

    final run = controller.send('write two files');
    // See the identical wait above — send() awaits a real directory listing
    // before the model runs, so this needs actual elapsed time.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(requests, hasLength(1));
    requests.single.completer.complete(ToolApprovalDecision.allowForSession);

    await run;

    // Only ever prompted once, even though write_file ran twice.
    expect(requests, hasLength(1));
    expect(await File('${root.path}/a.txt').readAsString(), '1');
    expect(await File('${root.path}/b.txt').readAsString(), '2');
  });

  test('a failing tool does not sink the run — the model still gets a chance to answer',
      () async {
    final (controller, _, root) = await _buildReady([
      _toolCall('read_file', {'path': 'missing.txt'}),
      'That file does not exist.',
    ]);
    addTearDown(() => root.delete(recursive: true));

    await controller.send('read missing.txt');

    expect(controller.error, isNull);
    final toolEntry = controller.transcript.whereType<ToolCallTranscriptEntry>().single;
    expect(toolEntry.status, ToolCallStatus.error);
    final answer = controller.transcript.whereType<AssistantTextTranscriptEntry>().single;
    expect(answer.text, 'That file does not exist.');
  });

  test('stop() ends the run and discards a late-arriving reply', () async {
    final (controller, api, root) = await _buildReady(['hang']);
    addTearDown(() => root.delete(recursive: true));

    api.gate = Completer<String>();
    final run = controller.send('hang on');
    await Future<void>.delayed(Duration.zero);
    expect(controller.running, isTrue);

    controller.stop();
    expect(controller.running, isFalse);

    // Even if the held call now resolves with a normal reply, it must not
    // land in the transcript.
    api.gate!.complete('too late');
    await run;

    expect(
      controller.transcript.whereType<AssistantTextTranscriptEntry>(),
      isEmpty,
    );
  });

  test('stop() denies a pending approval so the agent loop does not hang forever', () async {
    final (controller, _, root) = await _buildReady([
      _toolCall('write_file', {'path': 'out.txt', 'content': 'hello'}),
      'Done.',
    ]);
    addTearDown(() => root.delete(recursive: true));

    final run = controller.send('write a file');
    await Future<void>.delayed(Duration.zero);
    expect(controller.running, isTrue);

    controller.stop();
    // The run's own future must complete promptly rather than hang on the
    // approval it will now never receive from a UI.
    await run.timeout(const Duration(seconds: 5));

    expect(await File('${root.path}/out.txt').exists(), isFalse);
  });

  group('history', () {
    test('a second send continues the same session — one conversation, not two', () async {
      final (controller, _, root) = await _buildReady(['first reply', 'second reply']);
      addTearDown(() => root.delete(recursive: true));

      await controller.send('hello');
      await controller.send('again');

      expect(controller.sessions.where((s) => s.transcript.isNotEmpty), hasLength(1));
      expect(controller.transcript, hasLength(4)); // user, assistant, user, assistant
    });

    test('picking a new project root starts a fresh session, keeping the old one in history',
        () async {
      final api = _RecordingApi([_alpha], ['ok', 'ok']);
      final pool = ModelPool(api: api, downloadManager: const _NoDownloads());
      await pool.refresh();
      final rootA = await Directory.systemTemp.createTemp('code_agent_test_a');
      final rootB = await Directory.systemTemp.createTemp('code_agent_test_b');
      addTearDown(() => rootA.delete(recursive: true));
      addTearDown(() => rootB.delete(recursive: true));

      final controller = CodeAgentController(
        pool: pool,
        projectRootSource: _SequentialRootSource([rootA.path, rootB.path]),
      )..start();
      await controller.pickProjectRoot();
      controller.selectModel('alpha');
      await controller.send('in project A');

      await controller.pickProjectRoot(); // now lands on rootB
      expect(controller.transcript, isEmpty);
      await controller.send('in project B');

      final answered = controller.sessions.where((s) => s.transcript.isNotEmpty).toList();
      expect(answered, hasLength(2));
      expect(answered.map((s) => s.projectRoot), [rootB.path, rootA.path]);
    });

    test('selecting a different model starts a fresh session', () async {
      final api = _RecordingApi([_alpha, const ModelInfo(id: 'beta', name: 'Beta')], ['ok']);
      final pool = ModelPool(api: api, downloadManager: const _NoDownloads());
      await pool.refresh();
      final root = await Directory.systemTemp.createTemp('code_agent_test');
      addTearDown(() => root.delete(recursive: true));

      final controller = CodeAgentController(
        pool: pool,
        projectRootSource: _FakeRootSource(root.path),
      )..start();
      await controller.pickProjectRoot();
      controller.selectModel('alpha');
      await controller.send('with alpha');

      controller.selectModel('beta');
      expect(controller.transcript, isEmpty);
      await controller.send('with beta');

      expect(controller.sessions.where((s) => s.transcript.isNotEmpty), hasLength(2));
    });

    test('newSession reuses the empty slot instead of piling up duplicates', () async {
      final (controller, _, root) = await _buildReady(['ok']);
      addTearDown(() => root.delete(recursive: true));
      final before = controller.sessions.length;

      controller.newSession();
      controller.newSession();

      expect(controller.sessions.length, before);
      expect(controller.transcript, isEmpty);
    });

    test('deleteSession removes a conversation and falls back to another one', () async {
      final (controller, _, root) = await _buildReady(['first reply']);
      addTearDown(() => root.delete(recursive: true));
      await controller.send('hello');
      controller.newSession();
      await controller.send('a different conversation');

      controller.deleteSession(0); // the active ("a different conversation") one
      final remaining = controller.sessions.where((s) => s.transcript.isNotEmpty).toList();
      expect(remaining, hasLength(1));
      expect((remaining.single.transcript.first as UserTranscriptEntry).text, 'hello');
    });

    test(
        'a conversation persists through InMemoryCodeSessionStore and reloads into a fresh '
        'controller, ready to continue', () async {
      final sharedStore = InMemoryCodeSessionStore();
      final api = _RecordingApi([_alpha], [
        _toolCall('list_dir', {'path': '.'}),
        'Found some files.',
        'A follow-up answer.',
      ]);
      final pool = ModelPool(api: api, downloadManager: const _NoDownloads());
      await pool.refresh();
      final root = await Directory.systemTemp.createTemp('code_agent_test');
      addTearDown(() => root.delete(recursive: true));

      final first = CodeAgentController(
        pool: pool,
        projectRootSource: _FakeRootSource(root.path),
        store: sharedStore,
      )..start();
      await first.pickProjectRoot();
      first.selectModel('alpha');
      await first.send('list the files');

      final second = CodeAgentController(
        pool: pool,
        projectRootSource: _FakeRootSource(root.path),
        store: sharedStore,
      )..start();
      await Future<void>.delayed(Duration.zero); // let the stored history load

      final restored = second.sessions.firstWhere((s) => s.transcript.isNotEmpty);
      expect(restored.title, 'list the files');
      expect(
        restored.transcript.whereType<AssistantTextTranscriptEntry>().last.text,
        'Found some files.',
      );

      // Set up the picker (this reuses the still-empty initial session, not
      // `restored`), then explicitly switch to the restored conversation and
      // continue it — its real AgentState history rides along, not just the
      // display transcript, so the model sees the earlier turns as context.
      await second.pickProjectRoot();
      second.selectModel('alpha');
      second.selectSession(second.sessions.indexOf(restored));
      await second.send('and now?');

      expect(
        restored.transcript.whereType<AssistantTextTranscriptEntry>().last.text,
        'A follow-up answer.',
      );
    });
  });
}
