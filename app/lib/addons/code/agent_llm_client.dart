import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart' show CancelToken;

import '../../api_client.dart';
import '../../model_pool.dart';

/// Matches Qwen2.5's Hermes-style tool-call tag:
/// `<tool_call>{"name": "...", "arguments": {...}}</tool_call>`. Only the
/// first well-formed match in a reply is honoured — see [AgentLlmClient]'s
/// doc for why a v1 turn never acts on more than one tool call.
final _toolCallPattern =
    RegExp(r'<tool_call>\s*(\{.*?\})\s*</tool_call>', dotAll: true);

/// Adapts [ModelPool.generate] — a bare prompt-in/text-out call with no
/// system-message channel, no native tool-calling, and no real streaming —
/// to dart_agent_core's [LLMClient] interface.
///
/// [StatefulAgent] hands every call a growing `messages` list: an optional
/// leading [SystemMessage], then the whole run's [UserMessage]/[ModelMessage]/
/// [FunctionExecutionResultMessage] history, plus a `tools` list describing
/// what's callable. None of that maps onto [ModelPool.generate]'s
/// `{model, prompt, history, attachments}` shape, so this class's whole job is
/// flattening one into the other — the same kind of hand-rolled prompt
/// plumbing `OrchestrationController`'s `_sequentialPrompt`/`_synthesisPrompt`
/// already do for the same underlying reason: no structured channel exists
/// below this layer.
///
/// Tool calls are elicited by prompting, not a real function-calling API: the
/// tool list (name/description/JSON-schema) is rendered as text ahead of the
/// first user turn, instructing the model to answer with a
/// `<tool_call>{"name":...,"arguments":{...}}</tool_call>` tag when it wants
/// to use one. That is Qwen2.5's own trained tool-call format, which is why
/// the Code tab defaults to a Qwen2.5-Coder model (see
/// `code_agent_controller.dart`) — the parser here targets what that model
/// family actually learned to produce, not an arbitrary format.
///
/// A turn only ever acts on the *first* well-formed tag in a reply: letting a
/// single generation request several tools at once would mean the
/// one-request/one-decision approval-dialog flow (`tool_approval.dart`) has
/// to present more than one choice per prompt, which it isn't built for.
class AgentLlmClient implements LLMClient {
  AgentLlmClient({required this.pool, required this.model});

  final ModelPool pool;
  final ModelInfo model;

  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) =>
      _call(messages, tools ?? const []);

  @override
  Future<Stream<StreamingMessage>> stream(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    // ModelPool.generate returns the whole reply at once — there is no
    // token-by-token source to forward. CodeAgentController always calls
    // StatefulAgent.run(useStream: false), so this path isn't exercised in
    // practice, but it has to behave correctly rather than just compile.
    final message = await _call(messages, tools ?? const []);
    return Stream.value(StreamingMessage(modelMessage: message));
  }

  Future<ModelMessage> _call(List<LLMMessage> messages, List<Tool> tools) async {
    final (history, prompt) = _flatten(messages, tools);
    final raw = await pool.generate(model: model, prompt: prompt, history: history);
    return _parseReply(raw);
  }

  /// Turns dart_agent_core's message list into the `(history, prompt)` shape
  /// [ModelPool.generate] takes. The last message becomes [prompt]; every turn
  /// derived from an earlier message becomes [history].
  (List<ChatTurn>, String) _flatten(List<LLMMessage> messages, List<Tool> tools) {
    final systemText = messages.whereType<SystemMessage>().firstOrNull?.content;
    final preamble = _preamble(systemText, tools);
    var preambleAttached = preamble == null;
    final turns = <ChatTurn>[];

    String withPreambleIfNeeded(String text) {
      if (preambleAttached) return text;
      preambleAttached = true;
      return '$preamble\n\n$text';
    }

    for (final message in messages) {
      if (message is SystemMessage) {
        // Its content is already folded into the preamble above rather than
        // sent as its own turn — ModelPool.generate has no system-role
        // channel, so there is nowhere else to put it.
        continue;
      } else if (message is UserMessage) {
        turns.add(ChatTurn(
          isUser: true,
          text: withPreambleIfNeeded(_renderUserContent(message.contents)),
        ));
      } else if (message is ModelMessage) {
        turns.add(ChatTurn(isUser: false, text: _renderModelMessage(message)));
      } else if (message is FunctionExecutionResultMessage) {
        for (final result in message.results) {
          turns.add(ChatTurn(
            isUser: true,
            text: 'Tool result for ${result.name}'
                '${result.isError ? ' (error)' : ''}:\n'
                '${_renderContentParts(result.content)}',
          ));
        }
      }
    }

    if (turns.isEmpty) {
      // Shouldn't happen — StatefulAgent always seeds history with at least
      // one UserMessage before the first call — but a bare preamble beats
      // crashing on an empty list.
      return (const [], preamble ?? '');
    }

    final prompt = turns.removeLast().text;
    return (turns, prompt);
  }

  /// Combines the run's [SystemMessage] content (agent instructions — see
  /// `code_agent_controller.dart`'s `_systemPrompt`) with the tool-call
  /// instructions below into one block, prepended to the first real turn.
  /// Both pieces have nowhere else to go: [ModelPool.generate] has neither a
  /// system-role channel nor a `tools` parameter.
  String? _preamble(String? systemText, List<Tool> tools) {
    final parts = <String>[
      if (systemText != null && systemText.trim().isNotEmpty) systemText.trim(),
      if (_toolInstructions(tools) case final instructions?) instructions,
    ];
    return parts.isEmpty ? null : parts.join('\n\n');
  }

  String? _toolInstructions(List<Tool> tools) {
    if (tools.isEmpty) return null;
    final buffer = StringBuffer()
      ..writeln('You have access to the following tools. To call one, reply '
          'with EXACTLY this and nothing else — no other text before or after '
          'it:')
      ..writeln('<tool_call>')
      ..writeln('{"name": "<tool name>", "arguments": {<arguments as JSON>}}')
      ..writeln('</tool_call>')
      ..writeln()
      ..writeln('Call at most one tool per reply. If you do not need a tool, '
          'reply normally with plain text instead.')
      ..writeln()
      ..writeln('Available tools:');
    for (final tool in tools) {
      buffer
        ..writeln('- ${tool.name}: ${tool.description}')
        ..writeln('  Parameters (JSON Schema): ${jsonEncode(tool.parameters)}');
    }
    return buffer.toString();
  }

  String _renderUserContent(List<UserContentPart> contents) =>
      _renderContentParts(contents);

  String _renderContentParts(List<UserContentPart> contents) => contents
      .whereType<TextPart>()
      .map((p) => p.text)
      .join('\n');

  /// Reconstructs the text a prior [ModelMessage] "said" so it appears
  /// faithfully in the next call's history — including re-serializing a tool
  /// call this same client parsed out of raw text on an earlier turn, so the
  /// model can see what it already tried rather than losing that turn.
  String _renderModelMessage(ModelMessage message) {
    if (message.functionCalls.isNotEmpty) {
      final call = message.functionCalls.first;
      return '<tool_call>\n'
          '{"name": "${call.name}", "arguments": ${call.arguments}}\n'
          '</tool_call>';
    }
    return message.textOutput ?? '';
  }

  ModelMessage _parseReply(String raw) {
    final match = _toolCallPattern.firstMatch(raw);
    if (match == null) {
      return ModelMessage(model: model.id, textOutput: raw, stopReason: 'stop');
    }
    try {
      final decoded = jsonDecode(match.group(1)!);
      if (decoded is! Map<String, dynamic>) {
        return ModelMessage(model: model.id, textOutput: raw, stopReason: 'stop');
      }
      final name = decoded['name'];
      if (name is! String || name.isEmpty) {
        return ModelMessage(model: model.id, textOutput: raw, stopReason: 'stop');
      }
      final arguments = decoded['arguments'];
      return ModelMessage(
        model: model.id,
        functionCalls: [
          FunctionCall(
            id: 'call_${DateTime.now().microsecondsSinceEpoch}',
            name: name,
            arguments: arguments is String ? arguments : jsonEncode(arguments ?? {}),
          ),
        ],
        stopReason: 'tool_calls',
      );
    } on FormatException {
      // Malformed JSON inside the tag — treat as a final text answer rather
      // than crashing the run. The raw (broken) tag stays visible to the user
      // in the transcript, which is more honest than swallowing it silently.
      return ModelMessage(model: model.id, textOutput: raw, stopReason: 'stop');
    }
  }
}
