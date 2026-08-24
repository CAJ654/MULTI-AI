import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';

import 'package:multi_ai/addons/code/code_agent_controller.dart';
import 'package:multi_ai/addons/code/code_agent_pane.dart';
import 'package:multi_ai/addons/code/code_session_store.dart';
import 'package:multi_ai/addons/code/project_root_source.dart';
import 'package:multi_ai/api_client.dart';
import 'package:multi_ai/model_pool.dart';

class _RecordingApi extends ApiClient {
  _RecordingApi(this._models, this.replies);

  final List<ModelInfo> _models;
  final List<String> replies;
  int _replyIndex = 0;

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

/// Fake picker — no real dialog blocks under `flutter test`, matching how
/// AttachmentSource is faked for chat's widget tests.
class _FakeRootSource implements ProjectRootSource {
  _FakeRootSource(this.path);
  final String path;

  @override
  Future<String?> pickDirectory() async => path;
}

const _alpha = ModelInfo(id: 'alpha', name: 'Alpha');

String _toolCall(String name, Map<String, dynamic> args) {
  final entries = args.entries.map((e) => '"${e.key}": "${e.value}"').join(', ');
  return '<tool_call>\n{"name": "$name", "arguments": {$entries}}\n</tool_call>';
}

Future<(CodeAgentController, Directory)> _buildReady(
  WidgetTester tester,
  List<String> replies,
) async {
  final root = await Directory.systemTemp.createTemp('code_addon_widget_test');
  final api = _RecordingApi([_alpha], replies);
  final pool = ModelPool(api: api, downloadManager: const _NoDownloads());
  await pool.refresh();
  final controller = CodeAgentController(
    pool: pool,
    projectRootSource: _FakeRootSource(root.path),
    store: InMemoryCodeSessionStore(),
  )..start();
  await controller.pickProjectRoot();
  controller.selectModel('alpha');

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: CodeAgentPane(controller: controller)),
  ));
  await tester.pump();

  return (controller, root);
}

void main() {
  // Every test body below runs inside tester.runAsync(): the agent loop does
  // real file I/O (temp directories, reading/writing/listing real files
  // through agent_tools.dart), and flutter_test's default zone otherwise
  // never lets that resolve — a real async gap outside Flutter's own fake
  // clock hangs forever unless it's escaped into runAsync, per
  // https://api.flutter.dev/flutter/flutter_test/WidgetTester/runAsync.html.
  // pumpWidget/pump/tap all still work as normal from inside that callback.

  testWidgets('a completed tool-call turn renders a collapsed row and the final answer',
      (tester) async {
    await tester.runAsync(() async {
      final (controller, root) = await _buildReady(tester, [
        _toolCall('list_dir', {'path': '.'}),
        'Found some files.',
      ]);
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/a.txt').create();

      await controller.send('list the files');
      await tester.pumpAndSettle();

      // Collapsed by default: the tool name is visible, the JSON arguments
      // and result are not until it's expanded.
      expect(find.textContaining('list_dir'), findsOneWidget);
      expect(find.text('Found some files.'), findsOneWidget);
      expect(find.text('Done', skipOffstage: false), findsOneWidget); // status chip

      await tester.tap(find.textContaining('list_dir'));
      await tester.pumpAndSettle();

      expect(find.textContaining('a.txt'), findsWidgets);
    });
  });

  testWidgets('a gated tool call shows the approval dialog, and Deny refuses it',
      (tester) async {
    await tester.runAsync(() async {
      final (controller, root) = await _buildReady(tester, [
        _toolCall('write_file', {'path': 'out.txt', 'content': 'hello'}),
        'Okay, skipping that.',
      ]);
      addTearDown(() => root.delete(recursive: true));

      unawaited(controller.send('write a file'));
      // Approval is decided by the hook mid-`send()`, a real `Future` chain
      // running outside Flutter's fake clock (see this file's `runAsync`
      // doc comment) — pumpAndSettle() alone only pumps rendering frames, it
      // doesn't drive that chain forward, so it needs a real event-loop gap
      // first to reach the point where the approval dialog is pushed. A
      // zero-duration delay isn't enough on its own: send() awaits a real
      // directory listing (CodeAgentController._describeProjectRoot) before
      // the model even sees the message, and that's genuine dart:io I/O.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(find.text('Approve action'), findsOneWidget);
      expect(find.textContaining('write_file'), findsWidgets);

      await tester.tap(find.text('Deny'));
      // Same real-async gap as above: resuming the awaited completer and
      // running the model's follow-up reply happens on the real event loop,
      // not on a pumped frame. A zero-duration delay only guarantees one
      // microtask turn — real dart:io callbacks (the write below) resolve
      // via the OS, so this needs actual elapsed time, not just a turn.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(find.text('Approve action'), findsNothing);
      expect(await File('${root.path}/out.txt').exists(), isFalse);
      expect(find.text('Okay, skipping that.'), findsOneWidget);
    });
  });

  testWidgets('Allow once on a gated call runs the tool and closes the dialog', (tester) async {
    await tester.runAsync(() async {
      final (controller, root) = await _buildReady(tester, [
        _toolCall('write_file', {'path': 'out.txt', 'content': 'hello'}),
        'Done.',
      ]);
      addTearDown(() => root.delete(recursive: true));

      unawaited(controller.send('write a file'));
      // See the identical wait in the test above — send() awaits a real
      // directory listing before the model runs, so this needs actual
      // elapsed time, not just a microtask turn.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(find.text('Approve action'), findsOneWidget);

      await tester.tap(find.text('Allow once'));
      // Same real-async gap as above: the resumed write_file call and the
      // model's follow-up reply run on the real event loop, not a pumped
      // frame — and the write is a real dart:io call, so this needs actual
      // elapsed time, not just one microtask turn.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(find.text('Approve action'), findsNothing);
      expect(await File('${root.path}/out.txt').readAsString(), 'hello');
      expect(find.text('Done.'), findsOneWidget);
    });
  });
}
