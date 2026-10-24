import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';

import 'package:multi_ai/api_client.dart';
import 'package:multi_ai/code_tool_support.dart';
import 'package:multi_ai/model_detail_screen.dart';
import 'package:multi_ai/model_pool.dart';
import 'package:multi_ai/on_device_engine.dart' show onDeviceModelId;

class _FakeApi extends ApiClient {
  @override
  Future<List<ModelInfo>> fetchModels() async => const [];

  @override
  Future<DeviceSpecs> fetchDeviceSpecs() async => const DeviceSpecs();
}

class _NoDownloads extends ThrowingModelDownloadManager {
  const _NoDownloads();

  @override
  Future<ModelCacheEntry?> get(String cacheKey, {String? cacheDirectory}) async => null;
}

/// Every model file's id, the way the backend reports it, minus the Colibri
/// models — those run in an external engine the Code tab never lists.
List<String> _assessableModelIds() {
  final dir = Directory('../Multi-AI/multi_ai/models');
  final ids = <String>[];
  for (final file in dir.listSync().whereType<File>()) {
    if (!file.path.endsWith('.pyx')) continue;
    final id = file.uri.pathSegments.last.replaceAll('.pyx', '');
    if (id == '__init__') continue;
    if (RegExp(r'^_EXTERNAL_ENDPOINT\s*=', multiLine: true).hasMatch(file.readAsStringSync())) {
      continue;
    }
    ids.add(id);
  }
  return ids;
}

void main() {
  test('every model file has a verdict, so a new model cannot silently go unassessed', () {
    final ids = _assessableModelIds();
    expect(ids, isNotEmpty, reason: 'found no model files — is the test running from app/?');
    final missing = ids.where((id) => codeToolVerdictFor(id) == null).toList();
    expect(missing, isEmpty, reason: 'no Code-tab verdict for: $missing');
  });

  test('every on-device roster entry has a verdict', () {
    final roster = jsonDecode(File('assets/on_device_roster.json').readAsStringSync())
        as Map<String, dynamic>;
    final ids = [for (final m in roster['models'] as List<dynamic>) (m as Map)['id'] as String];
    final missing = ids.where((id) => codeToolVerdictFor(id) == null).toList();
    expect(missing, isEmpty, reason: 'no Code-tab verdict for: $missing');
  });

  test('an on-device sibling shares its server entry\'s verdict', () {
    expect(codeToolVerdictFor('qwen3_8b_on_device'), same(codeToolVerdictFor('qwen3_8b')));
    expect(codeToolVerdictFor('qwen3_8b_on_device'), isNotNull);
  });

  test('the built-in on-device model and Colibri/unknown ids', () {
    expect(codeToolVerdictFor(onDeviceModelId)?.support, CodeToolSupport.works);
    expect(codeToolVerdictFor('kimi_k3_colibri'), isNull);
    expect(codeToolVerdictFor('not_a_model'), isNull);
  });

  test('verdicts match what testing found', () {
    expect(codeToolVerdictFor('gemma_4_e2b')?.support, CodeToolSupport.works);
    expect(codeToolVerdictFor('qwen3_1_7b')?.support, CodeToolSupport.works);
    expect(codeToolVerdictFor('qwen2_5_coder_7b')?.support, CodeToolSupport.unlikely);
    expect(codeToolVerdictFor('gemma_3_1b')?.support, CodeToolSupport.unlikely);
    expect(codeToolVerdictFor('llama_3_2_1b')?.support, CodeToolSupport.uncertain);
    expect(codeToolVerdictFor('qwen3_8b')?.support, CodeToolSupport.shouldWork);
  });

  test('an untested negative is "unlikely", never claimed as a failure', () {
    expect(codeToolVerdictFor('gemma_3_1b')!.label, "Doesn't work");
    expect(codeToolVerdictFor('gemma_3_27b')!.tested, isFalse);
    expect(codeToolVerdictFor('gemma_3_27b')!.label, 'Unlikely to work');
  });

  Future<void> pumpDetail(WidgetTester tester, ModelInfo model) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pool = ModelPool(api: _FakeApi(), downloadManager: const _NoDownloads());
    await tester.pumpWidget(MaterialApp(
      home: ModelDetailScreen(
        model: model,
        runsInApp: true,
        pool: pool,
        source: 'hf://x/y/z.gguf',
        downloadManager: const _NoDownloads(),
      ),
    ));
    await tester.pump();
  }

  testWidgets('the detail page shows the verdict for a tested model', (tester) async {
    await pumpDetail(tester, const ModelInfo(id: 'gemma_4_e2b', name: 'Gemma 4 E2B'));
    expect(find.text('In the Code tab: Works'), findsOneWidget);
    expect(find.textContaining('5 of 5'), findsOneWidget);
    expect(find.text('Tested'), findsOneWidget);
  });

  testWidgets('the detail page flags an untested model as inferred', (tester) async {
    await pumpDetail(tester, const ModelInfo(id: 'qwen3_8b_on_device', name: 'Qwen3 8B'));
    expect(find.text('In the Code tab: Should work'), findsOneWidget);
    expect(find.textContaining('Not tested'), findsOneWidget);
  });

  testWidgets('the detail page warns for a model that cannot call tools', (tester) async {
    await pumpDetail(tester, const ModelInfo(id: 'gemma_3_1b', name: 'Gemma 3 1B'));
    expect(find.text("In the Code tab: Doesn't work"), findsOneWidget);
    expect(find.textContaining('invents its contents'), findsOneWidget);
  });

  testWidgets('the detail page shows nothing for a model that was not assessed', (tester) async {
    await pumpDetail(tester, const ModelInfo(id: 'some_new_model', name: 'New'));
    expect(find.textContaining('In the Code tab'), findsNothing);
  });
}
