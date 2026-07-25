import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../markdown_text.dart';
import '../../on_device_engine.dart';
import '../../theme.dart';
import '../addon.dart';
import 'orchestration_controller.dart';

/// The Model Council: pick several downloaded models, name one as lead, ask a
/// question, and the lead synthesizes the others' answers into one.
class OrchestrationAddOn extends AddOn {
  OrchestrationAddOn();

  OrchestrationController? _controller;

  @override
  AddOnManifest get manifest => const AddOnManifest(
        id: 'orchestration',
        title: 'Orchestration',
        icon: Icons.account_tree_outlined,
        order: 2,
        requires: [HostCapability.modelPool],
      );

  @override
  Future<void> onEnable(AddOnContext context) async {
    _controller = OrchestrationController(pool: context.modelPool)..start();
  }

  @override
  Future<void> onDisable() async {
    _controller?.dispose();
    _controller = null;
  }

  @override
  AddOnSurface registerUI(AddOnContext context) {
    final controller = _controller!;
    return AddOnSurface(
      sidebarPanel: (_) => OrchestrationPanel(controller: controller),
      mainPane: (_) => OrchestrationPane(controller: controller),
      topBarSlot: (_) => OrchestrationStatus(controller: controller),
    );
  }
}

/// True when the model runs in-app via llama.cpp rather than on the server —
/// only for the little "in-app / server" subtitle.
bool _runsInApp(ModelInfo m) => m.id == onDeviceModelId || m.gguf != null;

// ------------------------------------------------------------------- sidebar

/// Mode toggle plus the member/lead picker.
class OrchestrationPanel extends StatelessWidget {
  const OrchestrationPanel({super.key, required this.controller});

  final OrchestrationController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final models = controller.availableModels;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: _ModeToggle(controller: controller),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: Text('Council members',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white54)),
            ),
            if (models.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Download two or more models from the Models tab to '
                    'convene a council.',
                    style: TextStyle(fontSize: 12, height: 1.4, color: Colors.white38)),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: models.length,
                  itemBuilder: (context, i) =>
                      _MemberTile(controller: controller, model: models[i]),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.controller});

  final OrchestrationController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: mainColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          for (final mode in DeliberationMode.values)
            Expanded(
              child: _ModeButton(
                label: mode.label,
                selected: controller.mode == mode,
                // Locked mid-run: the mode decides how the current members were
                // prompted, so switching it partway would be incoherent.
                onTap: controller.running ? null : () => controller.setMode(mode),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? cardColor : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : Colors.white54)),
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.controller, required this.model});

  final OrchestrationController controller;
  final ModelInfo model;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedIds.contains(model.id);
    final isLead = controller.leadId == model.id;
    return Material(
      color: selected ? cardColor : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: controller.running ? null : () => controller.toggleSelected(model.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_box : Icons.check_box_outline_blank,
                size: 18,
                color: selected ? Colors.deepPurple.shade200 : Colors.white38,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(model.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            color: selected ? Colors.white : Colors.white70)),
                    Text(_runsInApp(model) ? 'In-app' : 'Server',
                        style: const TextStyle(fontSize: 10, color: Colors.white38)),
                  ],
                ),
              ),
              // The lead badge doubles as the control: tap it on another
              // selected model to move the crown. Only shown once selected.
              if (selected)
                Tooltip(
                  message: isLead ? 'Lead (synthesizes)' : 'Make lead',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: controller.running ? null : () => controller.setLead(model.id),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        isLead ? Icons.star : Icons.star_border,
                        size: 18,
                        color: isLead ? Colors.amber : Colors.white38,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- top bar

/// Compact one-liner on who's convened and how.
class OrchestrationStatus extends StatelessWidget {
  const OrchestrationStatus({super.key, required this.controller});

  final OrchestrationController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final lead = controller.leadModel;
        final members = controller.memberModels;
        final text = lead == null || members.isEmpty
            ? 'Model Council — select 2+ models in the sidebar'
            : '${controller.mode.label} · ${members.length} member'
                '${members.length == 1 ? '' : 's'} · lead ${lead.name}';
        return Align(
          alignment: Alignment.centerLeft,
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
        );
      },
    );
  }
}

// ------------------------------------------------------------------ main pane

class OrchestrationPane extends StatefulWidget {
  const OrchestrationPane({super.key, required this.controller});

  final OrchestrationController controller;

  @override
  State<OrchestrationPane> createState() => _OrchestrationPaneState();
}

class _OrchestrationPaneState extends State<OrchestrationPane> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  OrchestrationController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChanged);
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged() {
    // Follow the deliberation as it grows, but only while it's running — once
    // it's done, leave the user's scroll position where they put it.
    if (_c.running) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  void _submit() {
    final text = _input.text;
    if (!_c.canAsk || text.trim().isEmpty) return;
    _c.ask(text);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        return Column(
          children: [
            Expanded(child: _c.hasRun ? _buildTranscript() : _buildEmptyState()),
            _buildInput(),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_tree_outlined, size: 52, color: Colors.deepPurple.shade200),
              const SizedBox(height: 16),
              const Text('Model Council',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 10),
              const Text(
                'Pick two or more downloaded models in the sidebar and crown one '
                'as lead. The others answer your question; the lead reads every '
                'answer and gives one consolidated reply.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.5, color: Colors.white38),
              ),
              const SizedBox(height: 12),
              Text(
                _c.canAsk
                    ? 'Council ready — ask a question below.'
                    : 'Waiting for a lead and at least one other member.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    color: _c.canAsk ? Colors.deepPurple.shade200 : Colors.white30),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTranscript() {
    final lead = _c.synthesisStep;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            _QuestionBubble(text: _c.question ?? ''),
            const SizedBox(height: 12),
            for (final step in _c.memberSteps) _StepCard(step: step, isLead: false),
            if (lead != null) ...[
              const SizedBox(height: 4),
              _StepCard(step: lead, isLead: true),
            ],
            if (_c.error != null) ...[
              const SizedBox(height: 12),
              Text(_c.error!, style: TextStyle(color: Colors.red.shade300)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInput() {
    final running = _c.running;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Container(
            padding: const EdgeInsets.only(left: 20, right: 8),
            decoration: BoxDecoration(
              color: cardColor,
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: !running,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: _c.canAsk || running
                          ? 'Ask the council a question'
                          : 'Select a lead and members first',
                      hintStyle: const TextStyle(color: Colors.white38),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.deepPurple.shade400,
                      disabledBackgroundColor: Colors.white10,
                    ),
                    tooltip: running ? 'Stop' : 'Ask the council',
                    icon: Icon(running ? Icons.stop_rounded : Icons.arrow_upward,
                        size: 20, color: Colors.white),
                    onPressed: running
                        ? _c.stop
                        : (_c.canAsk ? _submit : null),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuestionBubble extends StatelessWidget {
  const _QuestionBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.deepPurple.shade400,
          borderRadius: BorderRadius.circular(18),
        ),
        child: SelectableText(text, style: const TextStyle(color: Colors.white, height: 1.4)),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.step, required this.isLead});

  final CouncilStep step;
  final bool isLead;

  @override
  Widget build(BuildContext context) {
    final accent = isLead ? Colors.amber : Colors.deepPurple.shade200;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLead ? Colors.amber.withValues(alpha: 0.5) : borderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isLead ? Icons.star : Icons.account_circle_outlined,
                  size: 16, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isLead ? 'Council synthesis · ${step.model.name}' : step.model.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: accent),
                ),
              ),
              _StatusChip(status: step.status),
            ],
          ),
          if (step.status == StepStatus.running) ...[
            const SizedBox(height: 10),
            const Row(
              children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('Thinking…', style: TextStyle(color: Colors.white54)),
              ],
            ),
          ] else if (step.text.isNotEmpty) ...[
            const SizedBox(height: 10),
            if (step.status == StepStatus.error)
              SelectableText(step.text,
                  style: TextStyle(height: 1.5, color: Colors.red.shade300))
            else
              MarkdownText(step.text,
                  baseStyle: const TextStyle(height: 1.5, color: Colors.white)),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final StepStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      StepStatus.pending => ('Waiting', Colors.white38),
      StepStatus.running => ('Answering', Colors.deepPurple.shade200),
      StepStatus.done => ('Answered', const Color(0xFF4ADE80)),
      StepStatus.error => ('Failed', const Color(0xFFF87171)),
    };
    return Text(label, style: TextStyle(fontSize: 11, color: color));
  }
}
