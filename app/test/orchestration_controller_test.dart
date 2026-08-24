import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';

import 'package:multi_ai/addons/orchestration/orchestration_controller.dart';
import 'package:multi_ai/addons/orchestration/orchestration_store.dart';
import 'package:multi_ai/api_client.dart';
import 'package:multi_ai/model_pool.dart';

/// Records every chat request and returns a canned, identifiable reply, so a
/// test can assert both what each model was asked and how answers threaded
/// between them. Every model reports as cached so the pool counts it
/// downloadable.
class _RecordingApi extends ApiClient {
  _RecordingApi(this._models);

  final List<ModelInfo> _models;
  final List<({String model, String message})> calls = [];

  /// When set, sendChat waits on this instead of returning — lets a test hold a
  /// run open to exercise stop().
  Completer<String>? gate;

  /// Model ids whose sendChat should throw, standing in for a load/generation
  /// failure on that model.
  final Set<String> failFor = {};

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
    calls.add((model: model, message: message));
    if (failFor.contains(model)) throw Exception('$model failed to load');
    final g = gate;
    if (g != null) return g.future;
    return '[$model answers]';
  }
}

/// Never reports a cache hit — the pool's built-in on-device Qwen entry then
/// counts as not-downloaded and stays out of the council, so the tests deal
/// only with the server models they declared.
class _NoDownloads extends ThrowingModelDownloadManager {
  const _NoDownloads();

  @override
  Future<ModelCacheEntry?> get(String cacheKey, {String? cacheDirectory}) async => null;
}

Future<(OrchestrationController, _RecordingApi)> _buildReady(
  List<ModelInfo> models,
) async {
  final api = _RecordingApi(models);
  final pool = ModelPool(api: api, downloadManager: const _NoDownloads());
  await pool.refresh();
  return (OrchestrationController(pool: pool)..start(), api);
}

const _a = ModelInfo(id: 'alpha', name: 'Alpha');
const _b = ModelInfo(id: 'beta', name: 'Beta');
const _c = ModelInfo(id: 'gamma', name: 'Gamma');

void main() {
  test('only downloaded server models are offered, not the built-in on-device',
      () async {
    final (controller, _) = await _buildReady([_a, _b]);
    expect(controller.availableModels.map((m) => m.id), ['alpha', 'beta']);
  });

  test('canAsk needs a lead plus at least one other member', () async {
    final (controller, _) = await _buildReady([_a, _b]);
    expect(controller.canAsk, isFalse);

    controller.toggleSelected('alpha'); // first pick becomes lead
    expect(controller.leadId, 'alpha');
    expect(controller.canAsk, isFalse, reason: 'lead alone has nobody to synthesize');

    controller.toggleSelected('beta');
    expect(controller.canAsk, isTrue);
  });

  test('parallel: every member answers the raw question, lead synthesizes all',
      () async {
    final (controller, api) = await _buildReady([_a, _b, _c]);
    controller.toggleSelected('alpha'); // lead
    controller.toggleSelected('beta');
    controller.toggleSelected('gamma');

    await controller.ask('what is 2+2?');

    // Beta and Gamma answered; each saw only the raw question.
    final beta = api.calls.firstWhere((c) => c.model == 'beta');
    final gamma = api.calls.firstWhere((c) => c.model == 'gamma');
    expect(beta.message, 'what is 2+2?');
    expect(gamma.message, 'what is 2+2?');

    // Alpha (lead) synthesized, and its prompt carried both answers.
    final lead = api.calls.firstWhere((c) => c.model == 'alpha');
    expect(lead.message, contains('[beta answers]'));
    expect(lead.message, contains('[gamma answers]'));
    expect(lead.message, contains('what is 2+2?'));

    expect(controller.synthesisStep!.text, '[alpha answers]');
    expect(controller.synthesisStep!.status, StepStatus.done);
    expect(controller.running, isFalse);
  });

  test('sequential: a later member sees the earlier answer', () async {
    final (controller, api) = await _buildReady([_a, _b, _c]);
    controller.setMode(DeliberationMode.sequential);
    controller.toggleSelected('alpha'); // lead
    controller.toggleSelected('beta');
    controller.toggleSelected('gamma');

    await controller.ask('pick a number');

    // Members run in selection order: beta first with just the question,
    // gamma second having seen beta's answer.
    final beta = api.calls.firstWhere((c) => c.model == 'beta');
    final gamma = api.calls.firstWhere((c) => c.model == 'gamma');
    expect(beta.message, 'pick a number');
    expect(gamma.message, contains('[beta answers]'));
  });

  test('a failing member does not sink the run — the lead synthesizes the rest',
      () async {
    final (controller, api) = await _buildReady([_a, _b, _c]);
    api.failFor.add('beta');
    controller.toggleSelected('alpha'); // lead
    controller.toggleSelected('beta'); // will fail
    controller.toggleSelected('gamma');

    await controller.ask('q');

    // Beta is flagged failed; the run still completes on gamma alone.
    final betaStep = controller.memberSteps.firstWhere((s) => s.model.id == 'beta');
    expect(betaStep.status, StepStatus.error);
    expect(controller.error, isNull);
    expect(controller.synthesisStep!.status, StepStatus.done);

    // The synthesis prompt carries gamma's answer but not the failed beta's.
    final lead = api.calls.firstWhere((c) => c.model == 'alpha');
    expect(lead.message, contains('[gamma answers]'));
    expect(lead.message, isNot(contains('[beta answers]')));
  });

  test('if every member fails, the run reports it and never synthesizes',
      () async {
    final (controller, api) = await _buildReady([_a, _b]);
    api.failFor.add('beta');
    controller.toggleSelected('alpha'); // lead
    controller.toggleSelected('beta'); // the only member, and it fails

    await controller.ask('q');

    expect(controller.error, isNotNull);
    expect(controller.synthesisStep!.status, isNot(StepStatus.done));
    // The lead was never asked to synthesize nothing.
    expect(api.calls.any((c) => c.model == 'alpha'), isFalse);
  });

  test('stop() ends the run and discards the in-flight answer', () async {
    final (controller, api) = await _buildReady([_a, _b]);
    controller.toggleSelected('alpha'); // lead
    controller.toggleSelected('beta');

    // Hold beta's generation open so the run parks mid-flight.
    api.gate = Completer<String>();
    final run = controller.ask('hang');
    await Future<void>.delayed(Duration.zero);
    expect(controller.running, isTrue);

    controller.stop();
    expect(controller.running, isFalse);

    // Even if the held call now resolves, its result must not land.
    api.gate!.complete('[beta answers]');
    await run;
    expect(controller.synthesisStep!.status, isNot(StepStatus.done));
    expect(controller.memberSteps.single.status, isNot(StepStatus.done));
  });

  test('deselecting the lead promotes another member', () async {
    final (controller, _) = await _buildReady([_a, _b]);
    controller.toggleSelected('alpha'); // lead
    controller.toggleSelected('beta');
    expect(controller.leadId, 'alpha');

    controller.toggleSelected('alpha'); // deselect the lead
    expect(controller.selectedIds, {'beta'});
    expect(controller.leadId, 'beta');
  });

  group('history', () {
    test('asking a second question starts a new session, leaving the first in history',
        () async {
      final (controller, _) = await _buildReady([_a, _b]);
      controller.toggleSelected('alpha'); // lead
      controller.toggleSelected('beta');

      await controller.ask('first question');
      expect(controller.sessions.where((s) => s.hasRun), hasLength(1));

      await controller.ask('second question');

      final answered = controller.sessions.where((s) => s.hasRun).toList();
      expect(answered, hasLength(2));
      // Newest run is active and on top; the first one is preserved below it.
      expect(controller.question, 'second question');
      expect(answered.map((s) => s.question), ['second question', 'first question']);
    });

    test('newSession reuses the empty slot instead of piling up duplicates', () async {
      final (controller, _) = await _buildReady([_a, _b]);
      final before = controller.sessions.length;

      controller.newSession();
      controller.newSession();

      expect(controller.sessions.length, before);
      expect(controller.hasRun, isFalse);
    });

    test('selectSession switches which run is shown without disturbing the others',
        () async {
      final (controller, _) = await _buildReady([_a, _b]);
      controller.toggleSelected('alpha');
      controller.toggleSelected('beta');
      await controller.ask('first question');
      await controller.ask('second question');

      // Index 0 is the newest ("second question"); index 1 is the first run.
      controller.selectSession(1);
      expect(controller.question, 'first question');

      controller.selectSession(0);
      expect(controller.question, 'second question');
    });

    test('deleteSession removes a run and falls back to another one', () async {
      final (controller, _) = await _buildReady([_a, _b]);
      controller.toggleSelected('alpha');
      controller.toggleSelected('beta');
      await controller.ask('first question');
      await controller.ask('second question');

      controller.deleteSession(0); // the active ("second question") run
      expect(controller.sessions.where((s) => s.hasRun).map((s) => s.question),
          ['first question']);
    });

    test('a run persists through InMemoryOrchestrationStore and reloads into a fresh controller',
        () async {
      final sharedStore = InMemoryOrchestrationStore();
      final api = _RecordingApi([_a, _b]);
      final pool = ModelPool(api: api, downloadManager: const _NoDownloads());
      await pool.refresh();

      final first = OrchestrationController(pool: pool, store: sharedStore);
      first.start();
      await Future<void>.delayed(Duration.zero); // let the empty initial load settle
      first.toggleSelected('alpha'); // lead
      first.toggleSelected('beta');
      await first.ask('what is 2+2?');

      final second = OrchestrationController(pool: pool, store: sharedStore);
      second.start();
      await Future<void>.delayed(Duration.zero); // let the stored history load

      final restored = second.sessions.firstWhere((s) => s.hasRun);
      expect(restored.question, 'what is 2+2?');
      expect(restored.synthesisStep!.text, '[alpha answers]');
    });
  });
}
