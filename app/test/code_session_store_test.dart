import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:multi_ai/addons/code/code_agent_controller.dart';
import 'package:multi_ai/addons/code/code_session_store.dart';

void main() {
  test('a transcript with every entry kind survives a JSON round-trip', () {
    final tool = ToolCallTranscriptEntry(
      id: 'call_1',
      name: 'write_file',
      argumentsJson: '{"path":"out.txt"}',
    )
      ..status = ToolCallStatus.done
      ..resultText = 'Wrote 5 characters to out.txt.';

    final session = CodeSession(
      title: 'write a file',
      transcript: [
        UserTranscriptEntry('write a file'),
        tool,
        AssistantTextTranscriptEntry('Done.'),
      ],
    )..projectRoot = 'C:/projects/demo'
      ..modelId = 'alpha'
      ..modelName = 'Alpha';

    final restored = CodeSession.fromJson(session.toJson());

    expect(restored.title, 'write a file');
    expect(restored.projectRoot, 'C:/projects/demo');
    expect(restored.modelId, 'alpha');
    expect(restored.modelName, 'Alpha');
    expect(restored.transcript, hasLength(3));
    expect(restored.transcript[0], isA<UserTranscriptEntry>());
    expect((restored.transcript[0] as UserTranscriptEntry).text, 'write a file');
    final restoredTool = restored.transcript[1] as ToolCallTranscriptEntry;
    expect(restoredTool.id, 'call_1');
    expect(restoredTool.name, 'write_file');
    expect(restoredTool.status, ToolCallStatus.done);
    expect(restoredTool.resultText, 'Wrote 5 characters to out.txt.');
    expect((restored.transcript[2] as AssistantTextTranscriptEntry).text, 'Done.');
  });

  test('a tool call interrupted mid-run loads as failed rather than stuck', () {
    final session = CodeSession(transcript: [
      ToolCallTranscriptEntry(id: 'call_1', name: 'run_command', argumentsJson: '{}')
        ..status = ToolCallStatus.awaitingApproval,
    ]);

    final restored = CodeSession.fromJson(session.toJson());
    final entry = restored.transcript.single as ToolCallTranscriptEntry;
    expect(entry.status, ToolCallStatus.error);
  });

  test("the underlying AgentState's message history round-trips", () async {
    final state = AgentState.empty();
    state.history.messages.add(UserMessage.text('hello'));
    state.history.messages.add(ModelMessage(model: 'alpha', textOutput: 'hi there'));

    final session = CodeSession(agentState: state);
    final restored = CodeSession.fromJson(session.toJson());

    expect(restored.agentState.history.messages, hasLength(2));
    expect(restored.agentState.sessionId, state.sessionId);
  });

  test('an unknown transcript entry type is skipped rather than failing the whole load', () {
    final json = {
      'transcript': [
        {'type': 'user', 'text': 'hi'},
        {'type': 'from_a_future_version', 'text': 'unknown'},
      ],
      'agentState': AgentState.empty().toJson(),
    };

    final restored = CodeSession.fromJson(json);
    expect(restored.transcript, hasLength(1));
    expect((restored.transcript.single as UserTranscriptEntry).text, 'hi');
  });

  test('an empty session round-trips with a null title and empty transcript', () {
    final restored = CodeSession.fromJson(CodeSession().toJson());
    expect(restored.title, isNull);
    expect(restored.transcript, isEmpty);
    expect(restored.projectRoot, isNull);
  });
}
