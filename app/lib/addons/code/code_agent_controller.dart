import 'dart:async';
import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:flutter/foundation.dart';

import '../../api_client.dart';
import '../../model_pool.dart';
import 'agent_llm_client.dart';
import 'agent_tools.dart';
import 'code_session_store.dart';
import 'project_root_source.dart';
import 'tool_approval.dart';

/// Where one tool call is in its lifecycle — see [ToolCallTranscriptEntry].
enum ToolCallStatus { running, awaitingApproval, done, error, denied }

/// One row in the Code tab's transcript.
sealed class CodeTranscriptEntry {
  Map<String, dynamic> toJson();
}

class UserTranscriptEntry extends CodeTranscriptEntry {
  UserTranscriptEntry(this.text);
  final String text;

  @override
  Map<String, dynamic> toJson() => {'type': 'user', 'text': text};
}

class AssistantTextTranscriptEntry extends CodeTranscriptEntry {
  AssistantTextTranscriptEntry(this.text);
  final String text;

  @override
  Map<String, dynamic> toJson() => {'type': 'assistant', 'text': text};
}

/// A tool call and its eventual result. Mutable status/result fields — mirrors
/// `CouncilStep` in orchestration_controller.dart — so the same object updates
/// in place as approval, execution, and the result each land, rather than the
/// transcript needing a rebuilt list on every step.
class ToolCallTranscriptEntry extends CodeTranscriptEntry {
  ToolCallTranscriptEntry({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });

  final String id;
  final String name;
  final String argumentsJson;
  ToolCallStatus status = ToolCallStatus.running;
  String resultText = '';

  @override
  Map<String, dynamic> toJson() => {
        'type': 'tool',
        'id': id,
        'name': name,
        'argumentsJson': argumentsJson,
        'status': status.name,
        'resultText': resultText,
      };
}

/// Rebuilds one transcript row from disk. Null for a `type` this build
/// doesn't know — a history file written by a newer version shouldn't make
/// the whole session fail to load, mirroring `_attachmentFromJson` in
/// `chat_store.dart`.
///
/// A tool call loaded as `running`/`awaitingApproval` was interrupted mid-run
/// (the app closed before it resolved) and can never resume — surfaced as
/// failed rather than a permanently spinning row.
CodeTranscriptEntry? codeTranscriptEntryFromJson(Map<String, dynamic> json) {
  switch (json['type'] as String?) {
    case 'user':
      return UserTranscriptEntry(json['text'] as String? ?? '');
    case 'assistant':
      return AssistantTextTranscriptEntry(json['text'] as String? ?? '');
    case 'tool':
      final entry = ToolCallTranscriptEntry(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        argumentsJson: json['argumentsJson'] as String? ?? '',
      );
      final status = ToolCallStatus.values
          .firstWhere((s) => s.name == json['status'], orElse: () => ToolCallStatus.error);
      entry.status =
          status == ToolCallStatus.running || status == ToolCallStatus.awaitingApproval
              ? ToolCallStatus.error
              : status;
      entry.resultText = json['resultText'] as String? ?? '';
      return entry;
    default:
      return null;
  }
}

const _systemPrompt = '''
You are a coding assistant working inside a real project on the user's
machine. You have direct read/write access to every file in it through your
tools — the user cannot see or paste file contents for you, so never ask them
to share, paste, or describe a file, and never ask what the project is about
or what it contains. For ANY question about the project — not just before
making a change — look yourself first: call list_dir, glob_search, or
read_file rather than asking the user or saying you need more information.
Prefer small, targeted edits over rewriting whole files. Explain what you did
briefly after making a change rather than narrating each step in advance.
''';

/// Drives the Code tab's agent loop: one [StatefulAgent] per [send] call,
/// wired to [ModelPool] through [AgentLlmClient] and to [agentTools] through
/// an approval-gating [AgentHook]. Keeps every past conversation as a
/// [CodeSession] so the sidebar can show a history of them, the same way
/// `ChatController` keeps past chats and `OrchestrationController` keeps past
/// council runs.
///
/// Shaped like `OrchestrationController` on purpose — a `ChangeNotifier`, a
/// `_runGeneration` guard so a result from a run [stop] already ended can't
/// land, and every state change wrapped in `notifyListeners()`. Unlike the
/// Council (fresh per question), a session's underlying [AgentState] persists
/// across [send] calls: the Code tab is a continuing conversation, the same
/// way Claude Code's own session is, not a series of one-shot questions — and
/// because [AgentState] round-trips through JSON, reselecting a past session
/// and sending another message continues that same conversation with full
/// context, not just a replayed log.
class CodeAgentController extends ChangeNotifier {
  CodeAgentController({
    required this.pool,
    ProjectRootSource? projectRootSource,
    CodeSessionStore? store,
  })  : _rootSource = projectRootSource ?? DefaultProjectRootSource(),
        _store = store ?? FileCodeSessionStore();

  final ModelPool pool;
  final ProjectRootSource _rootSource;
  final CodeSessionStore _store;

  String? _projectRoot;
  String? get projectRoot => _projectRoot;

  /// Cache for [_describeProjectRoot], keyed by the root it was read for —
  /// re-listing the directory on every single [send] would add a real disk
  /// I/O round-trip to every message for no benefit once the conversation is
  /// underway, so this is refreshed only when [_projectRoot] changes.
  String? _cachedRootListing;
  String? _cachedRootListingFor;

  ModelInfo? _selectedModel;
  ModelInfo? get selectedModel => _selectedModel;

  final _sessions = <CodeSession>[CodeSession()];
  int _activeSession = 0;

  List<CodeSession> get sessions => List.unmodifiable(_sessions);
  int get activeSessionIndex => _activeSession;
  CodeSession get session => _sessions[_activeSession];

  List<CodeTranscriptEntry> get transcript => List.unmodifiable(session.transcript);

  bool _running = false;
  bool get running => _running;

  int _runGeneration = 0;

  String? get error => session.error;

  final _approvals = StreamController<ToolApprovalRequest>.broadcast();
  Stream<ToolApprovalRequest> get approvalRequests => _approvals.stream;

  /// Tool names already blanket-approved for the rest of the active
  /// session's conversation — cleared whenever the active session changes.
  final _sessionAllowed = <String>{};

  /// The approval currently awaiting a decision, if any — completed with
  /// [ToolApprovalDecision.deny] by [stop] so a run stopped mid-approval
  /// doesn't leave its `agent.run()` future hanging forever.
  Completer<ToolApprovalDecision>? _pendingApproval;

  /// Models this device actually has weights for — same gate the chat picker
  /// and Orchestration's member list use.
  List<ModelInfo> get availableModels => pool.downloaded;

  bool get canSend => !_running && _projectRoot != null && _selectedModel != null;

  void start() {
    pool.addListener(_onPoolChanged);
    _onPoolChanged();
    unawaited(_loadStoredSessions());
  }

  Future<void> _loadStoredSessions() async {
    final stored = await _store.load();
    if (stored.isEmpty) return;
    // Keep the fresh empty session on top and resume with history below it.
    _sessions.addAll(stored);
    notifyListeners();
  }

  /// Drops the selected model if it's no longer downloaded — left alone
  /// mid-run so a delete on the Models tab can't yank a model out from under
  /// an in-flight turn, matching `OrchestrationController._onPoolChanged`.
  void _onPoolChanged() {
    if (!_running && pool.ready) {
      final selected = _selectedModel;
      if (selected != null && !pool.downloadedIds.contains(selected.id)) {
        _selectedModel = null;
      }
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- sessions

  void newSession() {
    // Reuse an existing empty session (they're hidden from the sidebar, so
    // stacking up duplicates would leak invisible entries).
    final existing = _sessions.indexWhere((s) => s.transcript.isEmpty);
    _setActiveSession(existing >= 0 ? existing : null);
  }

  void selectSession(int index) => _setActiveSession(index);

  void deleteSession(int index) {
    _sessions.removeAt(index);
    if (_sessions.isEmpty) _sessions.add(CodeSession());
    if (_activeSession >= _sessions.length) {
      _activeSession = _sessions.length - 1;
    } else if (index < _activeSession) {
      _activeSession -= 1;
    }
    _sessionAllowed.clear();
    notifyListeners();
    _store.save(_sessions);
  }

  /// Switches the active session to [index], or inserts a fresh empty one at
  /// the top when null. Tool approvals are scoped to one conversation, so
  /// they're cleared on every switch.
  void _setActiveSession(int? index) {
    if (index == null) {
      _sessions.insert(0, CodeSession());
      _activeSession = 0;
    } else {
      _activeSession = index;
    }
    _sessionAllowed.clear();
    notifyListeners();
  }

  Future<void> pickProjectRoot() async {
    if (_running) return;
    final path = await _rootSource.pickDirectory();
    if (path == null) return;
    _projectRoot = path;
    // A different project starts a new conversation.
    newSession();
  }

  void selectModel(String id) {
    if (_running) return;
    final model = pool.models.where((m) => m.id == id).firstOrNull;
    if (model == null || model.id == _selectedModel?.id) return;
    _selectedModel = model;
    // A different model starts a new conversation.
    newSession();
  }

  /// Builds a fresh [StatefulAgent] for this one [send] call, bound to
  /// [generation] and [session] via [_CodeAgentHook]'s closure — the hook
  /// checks [generation] against [_runGeneration] before every transcript
  /// mutation and before letting a gated tool actually execute, so a result
  /// from a run [stop] already ended can never land or take effect.
  /// [session]'s [AgentState] is reused across calls so the conversation
  /// itself continues; only the disposable wiring around it — client, tools,
  /// hook — is rebuilt.
  ///
  /// [rootListing] (from [_describeProjectRoot]) is folded into the system
  /// prompt rather than left for the model to fetch via `list_dir` itself —
  /// a small local model asked something open-ended like "tell me about this
  /// project" reliably answers from nothing rather than deciding on its own
  /// that it should call a tool first, so baseline awareness of what's in the
  /// project has to be handed to it up front.
  StatefulAgent _buildAgent(int generation, CodeSession session, String? rootListing) {
    return StatefulAgent(
      name: 'code_agent',
      client: AgentLlmClient(pool: pool, model: _selectedModel!),
      modelConfig: ModelConfig(model: _selectedModel!.id),
      state: session.agentState,
      tools: buildAgentTools(projectRoot: _projectRoot!),
      systemPrompts: [
        _systemPrompt,
        if (rootListing != null) 'Top-level contents of the project root:\n$rootListing',
      ],
      hooks: [_CodeAgentHook(this, generation, session)],
      // No sub-agent delegation in v1 — disabling this also keeps
      // dart_agent_core from injecting its delegate_task tool, which would
      // otherwise sit alongside the five actual tools and give a small local
      // model one more (unused) way to go off-script.
      disableSubAgents: true,
    );
  }

  /// Best-effort non-recursive listing of the project root, or null if it
  /// can't be read (e.g. deleted out from under the app mid-session) — a
  /// failure here shouldn't block sending a message, just fall back to the
  /// model needing to call `list_dir` itself. Cached per [_projectRoot] (see
  /// [_cachedRootListing]); a null result from a failed read is deliberately
  /// not cached so a transient failure gets retried on the next [send]
  /// rather than sticking for the rest of the session.
  Future<String?> _describeProjectRoot() async {
    if (_cachedRootListingFor == _projectRoot) return _cachedRootListing;
    try {
      final listing = await listDirectoryContents(_projectRoot!, '.');
      _cachedRootListing = listing;
      _cachedRootListingFor = _projectRoot;
      return listing;
    } catch (_) {
      return null;
    }
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (!canSend || trimmed.isEmpty) return;

    final generation = ++_runGeneration;
    _running = true;
    final session = this.session;
    session.error = null;
    session.title ??= trimmed;
    session.projectRoot = _projectRoot;
    session.modelId = _selectedModel!.id;
    session.modelName = _selectedModel!.name;
    session.transcript.add(UserTranscriptEntry(trimmed));
    notifyListeners();
    _store.save(_sessions);

    final rootListing = await _describeProjectRoot();
    if (generation != _runGeneration) return; // stop() fired while listing the root
    final agent = _buildAgent(generation, session, rootListing);
    try {
      await agent.run([UserMessage.text(trimmed)], useStream: false);
    } on AgentException catch (e) {
      if (generation == _runGeneration) session.error = e.message;
    } catch (e) {
      if (generation == _runGeneration) session.error = e.toString();
    } finally {
      if (generation == _runGeneration) {
        _running = false;
        notifyListeners();
      }
      _store.save(_sessions);
    }
  }

  /// Ends the run and discards whatever it was doing. Mirrors
  /// `OrchestrationController.stop()`: bump the generation guard so a result
  /// that lands afterward is ignored, then abort whatever's actually in
  /// flight — a model generation via [ModelPool.cancel], or a stuck approval
  /// wait via denying it outright.
  void stop() {
    if (!_running) return;
    _runGeneration++;
    pool.cancel();
    _pendingApproval?.complete(ToolApprovalDecision.deny);
    _pendingApproval = null;
    _running = false;
    notifyListeners();
    _store.save(_sessions);
  }

  // ------------------------------------------------------------- hook events

  void _onModelResponse(int generation, CodeSession session, ModelMessage response) {
    if (generation != _runGeneration) return;
    final text = response.textOutput;
    if (text != null && text.trim().isNotEmpty) {
      session.transcript.add(AssistantTextTranscriptEntry(text.trim()));
      notifyListeners();
    }
  }

  Future<ToolCallHookResult> _onBeforeToolCall(
      int generation, CodeSession session, FunctionCall call) async {
    if (generation != _runGeneration) {
      // This run was already stopped — refuse rather than actually running a
      // write/command for a turn nobody is watching anymore.
      return ToolCallHookResult.deny(content: [TextPart('Run stopped.')]);
    }

    final entry = ToolCallTranscriptEntry(
      id: call.id,
      name: call.name,
      argumentsJson: call.arguments,
    );
    session.transcript.add(entry);

    final needsApproval =
        gatedToolNames.contains(call.name) && !_sessionAllowed.contains(call.name);
    if (!needsApproval) {
      notifyListeners();
      return ToolCallHookResult.proceed(call);
    }

    entry.status = ToolCallStatus.awaitingApproval;
    notifyListeners();

    final completer = Completer<ToolApprovalDecision>();
    _pendingApproval = completer;
    _approvals.add(ToolApprovalRequest(
      toolName: call.name,
      argsSummary: _summarizeArgs(call),
      completer: completer,
    ));
    final decision = await completer.future;
    _pendingApproval = null;

    if (generation != _runGeneration) {
      // stop() fired while this call was awaiting approval — the decision
      // (whatever it was) no longer matters; don't mutate the discarded
      // transcript or let the tool run for real.
      return ToolCallHookResult.deny(content: [TextPart('Run stopped.')]);
    }

    if (decision == ToolApprovalDecision.deny) {
      entry.status = ToolCallStatus.denied;
      notifyListeners();
      return ToolCallHookResult.deny(content: [TextPart('Denied by the user.')]);
    }
    if (decision == ToolApprovalDecision.allowForSession) {
      _sessionAllowed.add(call.name);
    }
    entry.status = ToolCallStatus.running;
    notifyListeners();
    return ToolCallHookResult.proceed(call);
  }

  void _onAfterToolCall(
      int generation, CodeSession session, FunctionExecutionResult result) {
    if (generation != _runGeneration) return;
    final entry = session.transcript
        .whereType<ToolCallTranscriptEntry>()
        .where((e) => e.id == result.id)
        .lastOrNull;
    if (entry == null) return;
    // dart_agent_core fires afterToolCall for every result, including the
    // synthetic one for a call [_onBeforeToolCall] already denied (which
    // defaults to isError: true) — that status was the point of denying it,
    // so it must win over the generic done/error mapping below rather than
    // being immediately overwritten by it.
    if (entry.status == ToolCallStatus.denied) return;
    entry
      ..status = result.isError ? ToolCallStatus.error : ToolCallStatus.done
      ..resultText = result.content.whereType<TextPart>().map((p) => p.text).join('\n');
    notifyListeners();
  }

  String _summarizeArgs(FunctionCall call) {
    try {
      final decoded = jsonDecode(call.arguments);
      if (decoded is Map<String, dynamic>) {
        switch (call.name) {
          case 'write_file':
          case 'edit_file':
            return decoded['path']?.toString() ?? call.arguments;
          case 'run_command':
            final command = decoded['command']?.toString() ?? '';
            final args = (decoded['args'] as List?)?.join(' ') ?? '';
            return args.isEmpty ? command : '$command $args';
        }
      }
    } on FormatException {
      // Fall through to the raw JSON below.
    }
    return call.arguments;
  }

  @override
  void dispose() {
    pool.removeListener(_onPoolChanged);
    _approvals.close();
    super.dispose();
  }
}

/// Routes dart_agent_core's hook callbacks back to the controller, tagged
/// with the [_generation] of the [send] call and the [_session] it belongs to
/// — see [CodeAgentController._buildAgent]. A separate class rather than the
/// controller implementing [AgentHook] itself: Dart has no multiple
/// inheritance, and `CodeAgentController` already extends `ChangeNotifier`.
class _CodeAgentHook extends AgentHook {
  _CodeAgentHook(this._controller, this._generation, this._session);

  final CodeAgentController _controller;
  final int _generation;
  final CodeSession _session;

  @override
  FutureOr<ModelResponseHookResult> afterModelCall(ModelResponseHookContext context) {
    _controller._onModelResponse(_generation, _session, context.response);
    return ModelResponseHookResult.proceed(context.response);
  }

  @override
  Future<ToolCallHookResult> beforeToolCall(ToolCallHookContext context) =>
      _controller._onBeforeToolCall(_generation, _session, context.call);

  @override
  FutureOr<ToolResultHookResult> afterToolCall(ToolResultHookContext context) {
    _controller._onAfterToolCall(_generation, _session, context.result);
    return ToolResultHookResult.proceed(result: context.result);
  }
}
