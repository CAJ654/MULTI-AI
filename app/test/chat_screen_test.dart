import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:multi_ai/api_client.dart';
import 'package:multi_ai/chat_screen.dart';
import 'package:multi_ai/on_device_engine.dart';

/// Returns canned models instead of calling the real backend.
class _FakeApiClient extends ApiClient {
  _FakeApiClient(this.models);

  final List<ModelInfo> models;

  @override
  Future<List<ModelInfo>> fetchModels() async => models;

  // Never resolves, so a send leaves the UI in the "thinking" state for the
  // test to inspect.
  @override
  Future<String> sendChat({required String model, required String message}) => Completer<String>().future;

  // Model detail screens for server-backed models query cache status on
  // open; stub it out so tests never make a real network call.
  @override
  Future<ServerModelCacheStatus> getServerModelCacheStatus(String modelId) async =>
      const ServerModelCacheStatus(cached: false);
}

/// Default test surface (800x600) is too short for the chat screen's
/// suggestion cards and overflows; match a realistic desktop window.
void _useDesktopSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('dropdown shows the on-device model plus every server model', (tester) async {
    _useDesktopSurface(tester);

    final fake = _FakeApiClient(const [
      ModelInfo(id: 'gpt2', name: 'GPT-2'),
      ModelInfo(id: 'gptOSS', name: 'GPT-OSS 20B', gguf: 'hf://ggml-org/gpt-oss-20b-GGUF/gpt-oss-20b-MXFP4.gguf'),
    ]);

    await tester.pumpWidget(MaterialApp(home: ChatScreen(apiClient: fake)));
    await tester.pumpAndSettle();

    // Open the dropdown so its (offstage-when-closed) menu items are findable.
    await tester.tap(find.byType(DropdownButton<ModelInfo>));
    await tester.pumpAndSettle();

    expect(find.text(onDeviceModelName), findsWidgets);
    expect(find.text('GPT-2'), findsWidgets);
    expect(find.text('GPT-OSS 20B'), findsWidgets);
  });

  testWidgets('falls back to the on-device model only when the backend is unreachable', (tester) async {
    _useDesktopSurface(tester);

    final fake = _FakeApiClient(const []);
    // fetchModels() succeeding with an empty list still exercises the merge
    // path; a real unreachable backend throws instead, which _loadModels
    // catches the same way — either way only the on-device entry should show.

    await tester.pumpWidget(MaterialApp(home: ChatScreen(apiClient: fake)));
    await tester.pumpAndSettle();

    expect(find.text(onDeviceModelName), findsOneWidget);
  });

  testWidgets('Models tab lists params/size and Chat tab keeps the New Chat button', (tester) async {
    _useDesktopSurface(tester);

    final fake = _FakeApiClient(const [
      ModelInfo(id: 'gpt2', name: 'GPT-2', params: '124M', sizeGb: 0.55),
    ]);

    await tester.pumpWidget(MaterialApp(home: ChatScreen(apiClient: fake)));
    await tester.pumpAndSettle();

    // Chat tab is the default: New Chat button visible, no model metadata yet.
    expect(find.widgetWithText(FilledButton, 'New Chat'), findsOneWidget);
    expect(find.textContaining('params'), findsNothing);

    await tester.tap(find.text('Models'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'New Chat'), findsNothing);
    // The top-bar dropdown also shows the (unrelated) selected model's name
    // in its closed state, so this may match more than just the tab's card.
    expect(find.text(onDeviceModelName), findsWidgets);
    expect(find.textContaining('$onDeviceModelParams params'), findsOneWidget);
    expect(find.text('GPT-2'), findsOneWidget);
    expect(find.textContaining('124M params'), findsOneWidget);

    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'New Chat'), findsOneWidget);
  });

  testWidgets('tapping a model card opens its detail page with the full spec', (tester) async {
    _useDesktopSurface(tester);

    final fake = _FakeApiClient(const [
      ModelInfo(
        id: 'gpt2',
        name: 'GPT-2',
        params: '124M',
        sizeGb: 0.55,
        modality: 'Text',
        contextTokens: 1024,
        license: 'MIT',
        strengths: 'A raw base model, mostly useful as a speed baseline.',
        speedProfile: 'Very fast, minimal intelligence',
      ),
    ]);

    await tester.pumpWidget(MaterialApp(home: ChatScreen(apiClient: fake)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Models'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GPT-2'));
    await tester.pumpAndSettle();

    expect(find.text('Modality'), findsOneWidget);
    expect(find.text('Text'), findsOneWidget);
    expect(find.text('Core Strengths & Intelligence Profile'), findsOneWidget);
    expect(find.text('A raw base model, mostly useful as a speed baseline.'), findsOneWidget);
    expect(find.text('Intelligence-to-Speed Ratio'), findsOneWidget);
    expect(find.text('Very fast, minimal intelligence'), findsOneWidget);
    expect(find.text('Context Window'), findsOneWidget);
    expect(find.textContaining('1K tokens'), findsWidgets);
    expect(find.text('Open Source License'), findsOneWidget);
    expect(find.text('MIT'), findsOneWidget);
    expect(find.text('124M'), findsOneWidget);
  });

  testWidgets('sending a message shows the thinking row without crashing', (tester) async {
    _useDesktopSurface(tester);

    final fake = _FakeApiClient(const [ModelInfo(id: 'gpt2', name: 'GPT-2')]);

    await tester.pumpWidget(MaterialApp(home: ChatScreen(apiClient: fake)));
    await tester.pumpAndSettle();

    // The dropdown defaults to the on-device model; switch to the (never
    // resolving) server model so the send goes through _api.sendChat.
    await tester.tap(find.byType(DropdownButton<ModelInfo>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GPT-2').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    // The thinking row's rotating indicator starts a periodic timer, so
    // settle with an explicit pump instead of pumpAndSettle (which would
    // wait forever for a timer that never stops on its own).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
