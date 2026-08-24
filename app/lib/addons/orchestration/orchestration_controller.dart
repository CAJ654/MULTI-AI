import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../api_client.dart';
import '../../model_pool.dart';
import 'orchestration_store.dart';

/// How the council members answer relative to one another.
enum DeliberationMode {
  /// Each member answers the raw question, seeing nobody else's answer. The
  /// lead then synthesizes them all.
  parallel('Parallel'),

  /// Each member answers in turn, seeing the answers already given, so later
  /// members can build on or push back. The lead still synthesizes at the end.
  sequential('Sequential');

  const DeliberationMode(this.label);
  final String label;
}

/// Where one step of a council run is in its lifecycle.
enum StepStatus { pending, running, done, error }

/// One model's contribution to a run — either a member's answer or the lead's
/// synthesis. Mutable: the same object goes pending → running → done as the
/// run progresses, so the UI watching it doesn't need a new list each step.
class CouncilStep {
  CouncilStep(this.model);

  final ModelInfo model;
  String text = '';
  StepStatus status = StepStatus.pending;

  bool get isDone => status == StepStatus.done;

  Map<String, dynamic> toJson() => {
        'modelId': model.id,
        'modelName': model.name,
        'text': text,
        'status': status.name,
      };

  /// A step loaded from disk whose status is still `pending`/`running` was
  /// interrupted mid-run (the app closed before it finished) and can never
  /// resume — surfaced as failed rather than a permanently "Thinking…" row.
  factory CouncilStep.fromJson(Map<String, dynamic> json) {
    final step = CouncilStep(ModelInfo(
      id: json['modelId'] as String? ?? '',
      name: json['modelName'] as String? ?? 'Unknown model',
    ))
      ..text = json['text'] as String? ?? '';
    final status = StepStatus.values
        .firstWhere((s) => s.name == json['status'], orElse: () => StepStatus.error);
    step.status =
        status == StepStatus.pending || status == StepStatus.running ? StepStatus.error : status;
    return step;
  }
}

/// One council run: the question asked, the mode it ran under, every
/// member's answer, and the lead's synthesis. Mirrors `ChatSession` in
/// `chat_store.dart` — a run only counts as history once it has a question.
class OrchestrationSession {
  OrchestrationSession();

  String? question;
  DeliberationMode mode = DeliberationMode.parallel;
  List<CouncilStep> memberSteps = [];
  CouncilStep? synthesisStep;
  String? error;

  bool get hasRun => question != null;

  Map<String, dynamic> toJson() => {
        if (question != null) 'question': question,
        'mode': mode.name,
        'memberSteps': memberSteps.map((s) => s.toJson()).toList(),
        if (synthesisStep != null) 'synthesis': synthesisStep!.toJson(),
        if (error != null) 'error': error,
      };

  factory OrchestrationSession.fromJson(Map<String, dynamic> json) {
    final synthesisJson = json['synthesis'] as Map<String, dynamic>?;
    return OrchestrationSession()
      ..question = json['question'] as String?
      ..mode = DeliberationMode.values
          .firstWhere((m) => m.name == json['mode'], orElse: () => DeliberationMode.parallel)
      ..memberSteps = [
        for (final s in (json['memberSteps'] as List<dynamic>? ?? []))
          CouncilStep.fromJson(s as Map<String, dynamic>),
      ]
      ..synthesisStep = synthesisJson == null ? null : CouncilStep.fromJson(synthesisJson)
      ..error = json['error'] as String?;
  }
}

/// Runs a "Model Council": several models answer a question, and a designated
/// lead synthesizes their answers into one. Keeps every past run so the
/// sidebar can show a history of them, the same way `ChatController` keeps
/// past conversations.
///
/// Built directly on [ModelPool.generate] rather than on an agent framework —
/// the council is fan-out plus a synthesis prompt, not tool use or planning,
/// and every framework would first need a custom adapter for this app's two
/// local run paths (llama.cpp in-process, and the Python backend) since neither
/// is an LLM provider any of them knows.
///
/// **Both modes execute members serially, not concurrently.** On a single-GPU
/// machine there is nothing to gain from wall-clock parallelism: the on-device
/// engine keeps one model resident and the Python backend evicts on model
/// switch, so two "simultaneous" generations would just thrash the same
/// hardware. "Parallel" here is the spec's *semantic* distinction — members
/// answer independently — not a threading one.
class OrchestrationController extends ChangeNotifier {
  OrchestrationController({required this.pool, OrchestrationStore? store})
      : _store = store ?? FileOrchestrationStore();

  final ModelPool pool;
  final OrchestrationStore _store;

  final Set<String> _selectedIds = {};
  String? _leadId;
  DeliberationMode _mode = DeliberationMode.parallel;

  bool _running = false;
  int _runGeneration = 0;

  final _sessions = <OrchestrationSession>[OrchestrationSession()];
  int _activeSession = 0;

  List<OrchestrationSession> get sessions => List.unmodifiable(_sessions);
  int get activeSessionIndex => _activeSession;
  OrchestrationSession get session => _sessions[_activeSession];

  /// Models that can actually be convened — the downloaded ones, same gate the
  /// chat picker uses. Selecting an undownloaded model would kick off a
  /// multi-gigabyte download mid-run.
  List<ModelInfo> get availableModels => pool.downloaded;

  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  String? get leadId => _leadId;
  DeliberationMode get mode => _mode;

  bool get running => _running;

  /// Non-null once the active session has been asked something.
  String? get question => session.question;

  /// The active session's member answers, in council order. Empty before its
  /// first run.
  List<CouncilStep> get memberSteps => List.unmodifiable(session.memberSteps);

  /// The active session's lead synthesis. Null before its first run.
  CouncilStep? get synthesisStep => session.synthesisStep;

  /// A run-level failure (nobody answered) for the active session, distinct
  /// from a single step's error. Null when the run is fine.
  String? get error => session.error;

  bool get hasRun => session.hasRun;

  ModelInfo? get leadModel => _leadId == null ? null : _modelById(_leadId!);

  /// The selected models that aren't the lead — the ones that actually answer.
  List<ModelInfo> get memberModels => [
        for (final id in _selectedIds)
          if (id != _leadId) ?_modelById(id),
      ];

  /// A council needs a lead plus at least one other member to answer, and
  /// nothing already in flight.
  bool get canAsk => !_running && leadModel != null && memberModels.isNotEmpty;

  ModelInfo? _modelById(String id) =>
      pool.models.where((m) => m.id == id).firstOrNull;

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

  /// Drops any selection that's no longer downloadable — a model deleted from
  /// the Models tab shouldn't stay in the council. Left alone mid-run so a
  /// delete can't yank a model out from under a generation.
  void _onPoolChanged() {
    if (!_running && pool.ready) {
      final ok = pool.downloadedIds;
      _selectedIds.removeWhere((id) => !ok.contains(id));
      if (_leadId != null && !_selectedIds.contains(_leadId)) {
        _leadId = _selectedIds.isEmpty ? null : _selectedIds.first;
      }
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- sessions

  void newSession() {
    // Reuse an existing empty session (they're hidden from the sidebar, so
    // stacking up duplicates would leak invisible entries).
    final existing = _sessions.indexWhere((s) => !s.hasRun);
    if (existing >= 0) {
      _activeSession = existing;
    } else {
      _sessions.insert(0, OrchestrationSession());
      _activeSession = 0;
    }
    notifyListeners();
  }

  void selectSession(int index) {
    _activeSession = index;
    notifyListeners();
  }

  void deleteSession(int index) {
    _sessions.removeAt(index);
    if (_sessions.isEmpty) _sessions.add(OrchestrationSession());
    if (_activeSession >= _sessions.length) {
      _activeSession = _sessions.length - 1;
    } else if (index < _activeSession) {
      _activeSession -= 1;
    }
    notifyListeners();
    _store.save(_sessions);
  }

  // ---------------------------------------------------------------- selection

  void toggleSelected(String id) {
    if (_running) return;
    if (_selectedIds.remove(id)) {
      // Removing the lead promotes whatever's left, so a valid council never
      // ends up lead-less while it still has members.
      if (_leadId == id) _leadId = _selectedIds.isEmpty ? null : _selectedIds.first;
    } else {
      _selectedIds.add(id);
      _leadId ??= id; // first pick leads by default
    }
    notifyListeners();
  }

  void setLead(String id) {
    if (_running || !_selectedIds.contains(id)) return;
    _leadId = id;
    notifyListeners();
  }

  void setMode(DeliberationMode mode) {
    if (_running) return;
    _mode = mode;
    notifyListeners();
  }

  // --------------------------------------------------------------------- run

  Future<void> ask(String question) async {
    final trimmed = question.trim();
    final lead = leadModel;
    final members = memberModels;
    if (_running || trimmed.isEmpty || lead == null || members.isEmpty) return;

    // A run always lands in a fresh session — the active one only if it
    // hasn't been asked anything yet (mirrors ChatController filling a
    // pre-existing empty session rather than appending to an answered one,
    // since a council run has no notion of a follow-up turn).
    var session = this.session;
    if (session.hasRun) {
      session = OrchestrationSession();
      _sessions.insert(0, session);
      _activeSession = 0;
    }

    final generation = ++_runGeneration;
    _running = true;
    session.question = trimmed;
    session.mode = _mode;
    session.memberSteps = [for (final m in members) CouncilStep(m)];
    session.synthesisStep = CouncilStep(lead);
    notifyListeners();
    _store.save(_sessions);

    try {
      for (var i = 0; i < session.memberSteps.length; i++) {
        if (generation != _runGeneration) return;
        final prior = _mode == DeliberationMode.sequential
            ? _formatAnswers(session.memberSteps.take(i))
            : null;
        await _runStep(
          generation,
          session.memberSteps[i],
          prior == null || prior.isEmpty
              ? trimmed
              : _sequentialPrompt(trimmed, prior),
        );
      }
      if (generation != _runGeneration) return;

      if (!session.memberSteps.any((s) => s.isDone)) {
        session.error = 'Every council member failed to answer, so there was nothing '
            'to synthesize.';
        return;
      }
      await _runStep(
        generation,
        session.synthesisStep!,
        _synthesisPrompt(trimmed, session.memberSteps),
      );
    } finally {
      if (generation == _runGeneration) {
        _running = false;
        notifyListeners();
      }
      _store.save(_sessions);
    }
  }

  Future<void> _runStep(int generation, CouncilStep step, String prompt) async {
    if (generation != _runGeneration) return;
    step.status = StepStatus.running;
    notifyListeners();
    try {
      final reply = await pool.generate(model: step.model, prompt: prompt);
      if (generation != _runGeneration) return;
      step
        ..text = reply
        ..status = StepStatus.done;
    } catch (e) {
      if (generation != _runGeneration) return;
      // A member failing is not a run failure — the council carries on with
      // whoever did answer. The message rides in the step so the card shows it.
      step
        ..text = e.toString()
        ..status = StepStatus.error;
    }
    notifyListeners();
  }

  /// Orphans the in-flight run so its late results are discarded, and aborts
  /// whatever generation is on the wire.
  void stop() {
    if (!_running) return;
    _runGeneration++;
    pool.cancel();
    _running = false;
    notifyListeners();
    _store.save(_sessions);
  }

  // ------------------------------------------------------------------ prompts

  String _formatAnswers(Iterable<CouncilStep> steps) => [
        for (final s in steps)
          if (s.isDone) '--- ${s.model.name} ---\n${s.text.trim()}',
      ].join('\n\n');

  String _sequentialPrompt(String question, String priorAnswers) =>
      'A user asked the following question:\n\n"$question"\n\n'
      'Other members of an AI council have already answered:\n\n$priorAnswers\n\n'
      'Give your own answer to the user\'s question. You may build on or '
      'disagree with the answers above, but answer the question directly.';

  String _synthesisPrompt(String question, List<CouncilStep> steps) =>
      'You are the lead of a council of AI models answering a user\'s question.\n\n'
      'The user asked:\n\n"$question"\n\n'
      'The council members answered:\n\n${_formatAnswers(steps)}\n\n'
      'Write one consolidated answer to the user\'s question. Note where the '
      'members agree, call out any contradictions or gaps, and give your best '
      'final answer. Answer the user directly — do not narrate that you are '
      'synthesizing or refer to "members" unless it genuinely helps.';

  @override
  void dispose() {
    pool.removeListener(_onPoolChanged);
    super.dispose();
  }
}
