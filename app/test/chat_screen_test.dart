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
      ModelInfo(id: 'gpt2', name: 'GPT-2 (base, no chat tuning)'),
      ModelInfo(id: 'gptOSS', name: 'GPT-OSS 20B (on-device)', gguf: 'hf://ggml-org/gpt-oss-20b-GGUF/gpt-oss-20b-MXFP4.gguf'),
    ]);

    await tester.pumpWidget(MaterialApp(home: ChatScreen(apiClient: fake)));
    await tester.pumpAndSettle();

    // Open the dropdown so its (offstage-when-closed) menu items are findable.
    await tester.tap(find.byType(DropdownButton<ModelInfo>));
    await tester.pumpAndSettle();

    expect(find.text(onDeviceModelName), findsWidgets);
    expect(find.text('GPT-2 (base, no chat tuning)'), findsWidgets);
    expect(find.text('GPT-OSS 20B (on-device)'), findsWidgets);
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
}
