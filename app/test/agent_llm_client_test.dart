import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:multi_ai/addons/code/agent_llm_client.dart';
import 'package:multi_ai/api_client.dart';
import 'package:multi_ai/model_pool.dart';

/// Records every chat request — model, prompt, and history — and returns a
/// scripted reply, so a test can assert exactly what [AgentLlmClient]
/// flattened dart_agent_core's message list into.
class _RecordingApi extends ApiClient {
  final calls = <({String model, String message, List<ChatTurn> history})>[];
  String reply = 'ok';

  @override
  Future<String> sendChat({
    required String model,
    required String message,
    List<Attachment> attachments = const [],
    List<ChatTurn> history = const [],
  }) async {
    calls.add((model: model, message: message, history: history));
    return reply;
  }
}

const _model = ModelInfo(id: 'alpha', name: 'Alpha');

Tool _tool(String name) => Tool(
      name: name,
      description: '$name does things',
      parameters: const {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
        },
      },
    );

void main() {
  late _RecordingApi api;
  late AgentLlmClient client;

  setUp(() {
    api = _RecordingApi();
    client = AgentLlmClient(pool: ModelPool(api: api), model: _model);
  });

  test('a lone user message with no tools becomes the prompt, no preamble', () async {
    await client.generate(
      [UserMessage.text('hello')],
      modelConfig: ModelConfig(model: _model.id),
    );

    final call = api.calls.single;
    expect(call.model, 'alpha');
    expect(call.message, 'hello');
    expect(call.history, isEmpty);
  });

  test('earlier turns become history, the last message becomes the prompt', () async {
    await client.generate(
      [
        UserMessage.text('first'),
        ModelMessage(model: 'alpha', textOutput: 'first reply'),
        UserMessage.text('second'),
      ],
      modelConfig: ModelConfig(model: _model.id),
    );

    final call = api.calls.single;
    expect(call.message, 'second');
    // ChatTurn has no ==, so compare the fields a test can actually assert on.
    expect(call.history.map((t) => (t.isUser, t.text)), [
      (true, 'first'),
      (false, 'first reply'),
    ]);
  });

  test('a system message is folded into the first user turn as a preamble, not sent standalone',
      () async {
    await client.generate(
      [SystemMessage('be concise'), UserMessage.text('hello')],
      modelConfig: ModelConfig(model: _model.id),
    );

    final call = api.calls.single;
    // The system content never rides as its own history turn — there is no
    // system-role channel in ChatTurn — so it must be folded into the one
    // real turn instead of silently dropped.
    expect(call.history, isEmpty);
    expect(call.message, contains('be concise'));
    expect(call.message, endsWith('hello'));
  });

  test('non-empty tools render a <tool_call> instruction preamble naming each tool', () async {
    await client.generate(
      [UserMessage.text('go')],
      tools: [_tool('read_file'), _tool('list_dir')],
      modelConfig: ModelConfig(model: _model.id),
    );

    final prompt = api.calls.single.message;
    expect(prompt, contains('<tool_call>'));
    expect(prompt, contains('read_file'));
    expect(prompt, contains('list_dir'));
    expect(prompt, endsWith('go'));
  });

  test('a well-formed <tool_call> reply parses into a single FunctionCall', () async {
    api.reply = '<tool_call>\n'
        '{"name": "read_file", "arguments": {"path": "a.txt"}}\n'
        '</tool_call>';

    final result = await client.generate(
      [UserMessage.text('read a.txt')],
      tools: [_tool('read_file')],
      modelConfig: ModelConfig(model: _model.id),
    );

    expect(result.textOutput, isNull);
    expect(result.functionCalls, hasLength(1));
    final call = result.functionCalls.single;
    expect(call.name, 'read_file');
    expect(jsonDecode(call.arguments), {'path': 'a.txt'});
  });

  test('a plain-text reply has no function calls', () async {
    api.reply = 'The answer is 4.';

    final result = await client.generate(
      [UserMessage.text('what is 2+2?')],
      modelConfig: ModelConfig(model: _model.id),
    );

    expect(result.textOutput, 'The answer is 4.');
    expect(result.functionCalls, isEmpty);
  });

  test('malformed JSON inside a tool_call tag falls back to a text answer rather than crashing',
      () async {
    api.reply = '<tool_call>{not valid json}</tool_call>';

    final result = await client.generate(
      [UserMessage.text('go')],
      tools: [_tool('read_file')],
      modelConfig: ModelConfig(model: _model.id),
    );

    expect(result.functionCalls, isEmpty);
    expect(result.textOutput, api.reply);
  });

  test('a FunctionExecutionResultMessage becomes a labeled synthetic user turn', () async {
    await client.generate(
      [
        UserMessage.text('list the dir'),
        ModelMessage(
          model: 'alpha',
          functionCalls: [FunctionCall(id: '1', name: 'list_dir', arguments: '{"path":"."}')],
        ),
        FunctionExecutionResultMessage(results: [
          FunctionExecutionResult(
            id: '1',
            name: 'list_dir',
            isError: false,
            arguments: '{"path":"."}',
            content: [TextPart('file dir  lib\nfile  pubspec.yaml')],
          ),
        ]),
      ],
      modelConfig: ModelConfig(model: _model.id),
    );

    final call = api.calls.single;
    // The tool result is the last message, so it becomes the live prompt.
    expect(call.message, contains('Tool result for list_dir'));
    expect(call.message, contains('pubspec.yaml'));
    // The model's own prior tool call is preserved in history as the tag it
    // originally "said", not lost or replaced with something else.
    expect(call.history, hasLength(2));
    expect(call.history[0].isUser, isTrue);
    expect(call.history[0].text, 'list the dir');
    expect(call.history[1].isUser, isFalse);
    expect(call.history[1].text, contains('<tool_call>'));
    expect(call.history[1].text, contains('list_dir'));
  });

  test('an isError tool result is labeled as an error in the synthetic turn', () async {
    await client.generate(
      [
        UserMessage.text('read missing.txt'),
        ModelMessage(
          model: 'alpha',
          functionCalls: [FunctionCall(id: '1', name: 'read_file', arguments: '{}')],
        ),
        FunctionExecutionResultMessage(results: [
          FunctionExecutionResult(
            id: '1',
            name: 'read_file',
            isError: true,
            arguments: '{}',
            content: [TextPart('File not found: missing.txt')],
          ),
        ]),
      ],
      modelConfig: ModelConfig(model: _model.id),
    );

    expect(api.calls.single.message, contains('Tool result for read_file (error)'));
  });
}
