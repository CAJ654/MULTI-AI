import 'package:flutter_test/flutter_test.dart';

import 'package:multi_ai/addons/orchestration/orchestration_controller.dart';
import 'package:multi_ai/api_client.dart';

void main() {
  test('a finished council run survives a JSON round-trip', () {
    final session = OrchestrationSession()
      ..question = 'what is 2+2?'
      ..mode = DeliberationMode.sequential
      ..memberSteps = [
        CouncilStep(const ModelInfo(id: 'beta', name: 'Beta'))
          ..text = 'four'
          ..status = StepStatus.done,
        CouncilStep(const ModelInfo(id: 'gamma', name: 'Gamma'))
          ..text = 'network error'
          ..status = StepStatus.error,
      ]
      ..synthesisStep = (CouncilStep(const ModelInfo(id: 'alpha', name: 'Alpha'))
        ..text = 'The answer is four.'
        ..status = StepStatus.done);

    final restored = OrchestrationSession.fromJson(session.toJson());

    expect(restored.question, 'what is 2+2?');
    expect(restored.mode, DeliberationMode.sequential);
    expect(restored.memberSteps, hasLength(2));
    expect(restored.memberSteps[0].model.id, 'beta');
    expect(restored.memberSteps[0].text, 'four');
    expect(restored.memberSteps[0].status, StepStatus.done);
    expect(restored.memberSteps[1].status, StepStatus.error);
    expect(restored.synthesisStep!.model.name, 'Alpha');
    expect(restored.synthesisStep!.text, 'The answer is four.');
    expect(restored.hasRun, isTrue);
  });

  test('a run-level failure survives the round-trip', () {
    final session = OrchestrationSession()
      ..question = 'q'
      ..memberSteps = [
        CouncilStep(const ModelInfo(id: 'beta', name: 'Beta'))..status = StepStatus.error,
      ]
      ..error = 'Every council member failed to answer, so there was nothing to synthesize.';

    final restored = OrchestrationSession.fromJson(session.toJson());
    expect(restored.error, session.error);
    expect(restored.synthesisStep, isNull);
  });

  test('a step interrupted mid-run loads as failed rather than stuck running', () {
    final session = OrchestrationSession()
      ..question = 'q'
      ..memberSteps = [
        CouncilStep(const ModelInfo(id: 'beta', name: 'Beta'))..status = StepStatus.running,
      ];

    final restored = OrchestrationSession.fromJson(session.toJson());
    expect(restored.memberSteps.single.status, StepStatus.error);
  });

  test('an unstarted session round-trips with a null question and hasRun false', () {
    final restored = OrchestrationSession.fromJson(OrchestrationSession().toJson());
    expect(restored.question, isNull);
    expect(restored.hasRun, isFalse);
    expect(restored.memberSteps, isEmpty);
  });
}
