import 'package:flutter/foundation.dart';

import '../../api_client.dart';
import '../../model_pool.dart';

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
}

/// Runs a "Model Council": several models answer a question, and a designated
/// lead synthesizes their answers into one.
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
  OrchestrationController({required this.pool});

  final ModelPool pool;

  final Set<String> _selectedIds = {};
  String? _leadId;
  DeliberationMode _mode = DeliberationMode.parallel;

  bool _running = false;
  int _runGeneration = 0;
  String? _question;
  List<CouncilStep> _memberSteps = const [];
  CouncilStep? _synthesisStep;
  String? _error;

  /// Models that can actually be convened — the downloaded ones, same gate the
  /// chat picker uses. Selecting an undownloaded model would kick off a
  /// multi-gigabyte download mid-run.
  List<ModelInfo> get availableModels => pool.downloaded;

  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  String? get leadId => _leadId;
  DeliberationMode get mode => _mode;

  bool get running => _running;

  /// Non-null once a run has started — the question that was asked.
  String? get question => _question;

  /// The members' answers, in council order. Empty before the first run.
  List<CouncilStep> get memberSteps => List.unmodifiable(_memberSteps);

  /// The lead's synthesis. Null before the first run.
  CouncilStep? get synthesisStep => _synthesisStep;

  /// A run-level failure (nobody answered), distinct from a single step's
  /// error. Null when the run is fine.
  String? get error => _error;

  bool get hasRun => _question != null;

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

    final generation = ++_runGeneration;
    _running = true;
    _error = null;
    _question = trimmed;
    _memberSteps = [for (final m in members) CouncilStep(m)];
    _synthesisStep = CouncilStep(lead);
    notifyListeners();

    try {
      for (var i = 0; i < _memberSteps.length; i++) {
        if (generation != _runGeneration) return;
        final prior = _mode == DeliberationMode.sequential
            ? _formatAnswers(_memberSteps.take(i))
            : null;
        await _runStep(
          generation,
          _memberSteps[i],
          prior == null || prior.isEmpty
              ? trimmed
              : _sequentialPrompt(trimmed, prior),
        );
      }
      if (generation != _runGeneration) return;

      if (!_memberSteps.any((s) => s.isDone)) {
        _error = 'Every council member failed to answer, so there was nothing '
            'to synthesize.';
        return;
      }
      await _runStep(
        generation,
        _synthesisStep!,
        _synthesisPrompt(trimmed, _memberSteps),
      );
    } finally {
      if (generation == _runGeneration) {
        _running = false;
        notifyListeners();
      }
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
