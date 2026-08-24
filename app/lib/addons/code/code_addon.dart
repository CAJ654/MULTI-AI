import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../model_pool.dart';
import '../../theme.dart';
import '../addon.dart';
import 'code_agent_controller.dart';
import 'code_agent_pane.dart';

/// A local agent loop over a real project folder: read/edit files, run
/// commands, ask before anything risky. See `code_agent_controller.dart` for
/// the loop itself and the README's "AI Coding Tool Portion" section for the
/// v1 scope this fulfils.
///
/// Desktop only (Windows/Linux) — see [_androidUnavailablePane]'s doc for why
/// Android gets a hard "not available" pane rather than a reduced mode.
class CodeAddOn extends AddOn {
  CodeAddOn();

  CodeAgentController? _controller;

  @override
  AddOnManifest get manifest => const AddOnManifest(
        id: 'code',
        title: 'Code',
        icon: Icons.code,
        order: 3,
        requires: [HostCapability.modelPool],
      );

  @override
  Future<void> onEnable(AddOnContext context) async {
    if (isAndroidPlatform) return;
    _controller = CodeAgentController(pool: context.modelPool)..start();
  }

  @override
  Future<void> onDisable() async {
    _controller?.dispose();
    _controller = null;
  }

  @override
  AddOnSurface registerUI(AddOnContext context) {
    final controller = _controller;
    if (controller == null) {
      return AddOnSurface(mainPane: (_) => _androidUnavailablePane());
    }
    return AddOnSurface(
      sidebarPanel: (_) => CodeSidebarPanel(controller: controller),
      mainPane: (_) => CodeAgentPane(controller: controller),
      topBarSlot: (_) => CodeStatus(controller: controller),
    );
  }

  /// Android is sandboxed: there is no arbitrary "project folder" to point a
  /// directory picker at (SAF hands back a content URI, not a path `dart:io`
  /// can open) and no shell to run `run_command` in from a release build.
  /// That isn't a smaller version of this feature, it's a different one — so
  /// rather than a reduced read-only mode, the tab is a hard off here, the
  /// same scoping shape the README already draws for Android's on-device-only
  /// chat path.
  Widget _androidUnavailablePane() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.code_off, size: 52, color: Colors.deepPurple.shade200),
              const SizedBox(height: 16),
              const Text('Code',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 10),
              const Text(
                "Not available on Android. The Code tab reads and edits files "
                'and runs commands in a real project folder — Android\'s app '
                "sandbox doesn't allow either, so there's no reduced version "
                'of this tab here.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.5, color: Colors.white38),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- sidebar

class CodeSidebarPanel extends StatelessWidget {
  const CodeSidebarPanel({super.key, required this.controller});

  final CodeAgentController controller;

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
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: _ProjectRootButton(controller: controller),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: cardColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: controller.running ? null : controller.newSession,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Conversation'),
              ),
            ),
            Expanded(child: CodeSessionList(controller: controller)),
            const Divider(height: 1, color: borderColor),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Text('Model',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white54)),
            ),
            if (models.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Download a model from the Models tab — a Qwen2.5-Coder '
                  'model is recommended for tool use.',
                  style: TextStyle(fontSize: 12, height: 1.4, color: Colors.white38),
                ),
              )
            else
              Expanded(
                flex: 2,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: models.length,
                  itemBuilder: (context, i) =>
                      _ModelTile(controller: controller, model: models[i]),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Past Code tab conversations, newest first. Mirrors `ChatSessionList` in
/// `chat_addon.dart`: a conversation only appears here once it has a message,
/// right-click (or long-press) opens Delete, and the selected one highlights.
class CodeSessionList extends StatelessWidget {
  const CodeSessionList({super.key, required this.controller});

  final CodeAgentController controller;

  Future<void> _showSessionMenu(
      BuildContext context, Offset position, int index) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      color: cardColor,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
              SizedBox(width: 10),
              Text('Delete', style: TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
      ],
    );
    if (action == 'delete') controller.deleteSession(index);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final sessions = controller.sessions;
        final visible = [
          for (var i = 0; i < sessions.length; i++)
            if (sessions[i].transcript.isNotEmpty) i,
        ];
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: visible.length,
          itemBuilder: (context, i) {
            final index = visible[i];
            final s = sessions[index];
            final selected = index == controller.activeSessionIndex;
            return GestureDetector(
              onSecondaryTapUp: (details) =>
                  _showSessionMenu(context, details.globalPosition, index),
              child: Material(
                color: selected ? cardColor : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: ListTile(
                  dense: true,
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  leading: const Icon(Icons.code, size: 16, color: Colors.white54),
                  title: Text(
                    s.title ?? 'New conversation',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13, color: selected ? Colors.white : Colors.white70),
                  ),
                  onTap: () => controller.selectSession(index),
                  onLongPress: () {
                    final box = context.findRenderObject() as RenderBox?;
                    final origin = box?.localToGlobal(Offset.zero) ?? Offset.zero;
                    _showSessionMenu(context, origin, index);
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ProjectRootButton extends StatelessWidget {
  const _ProjectRootButton({required this.controller});

  final CodeAgentController controller;

  @override
  Widget build(BuildContext context) {
    final root = controller.projectRoot;
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: cardColor,
        foregroundColor: Colors.white,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      onPressed: controller.running ? null : controller.pickProjectRoot,
      icon: const Icon(Icons.folder_open, size: 18),
      label: Text(
        root ?? 'Choose project folder',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({required this.controller, required this.model});

  final CodeAgentController controller;
  final ModelInfo model;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedModel?.id == model.id;
    return Material(
      color: selected ? cardColor : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: controller.running ? null : () => controller.selectModel(model.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 18,
                color: selected ? Colors.deepPurple.shade200 : Colors.white38,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(model.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13, color: selected ? Colors.white : Colors.white70)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- top bar

class CodeStatus extends StatelessWidget {
  const CodeStatus({super.key, required this.controller});

  final CodeAgentController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final root = controller.projectRoot;
        final model = controller.selectedModel;
        final text = root == null
            ? 'Code — choose a project folder in the sidebar'
            : model == null
                ? 'Code — choose a model in the sidebar'
                : '${root.split(RegExp(r'[\\/]')).last} · ${model.name}';
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
