import 'package:flutter/material.dart';

import '../../theme.dart';
import 'memory_store.dart';
import 'notebook_addon.dart';

/// The selected notebook's sources, add-source actions, and a notes/Q&A
/// view — the main pane while the Notebook tab is active. Mirrors
/// `components/components_addon.dart`'s `ComponentsPane` for the "nothing
/// selected yet" placeholder, but otherwise owns real content once a
/// notebook exists, unlike that pane (which only ever points at the
/// sidebar).
class NotebookMainPane extends StatefulWidget {
  const NotebookMainPane({super.key, required this.controller});

  final NotebookController controller;

  @override
  State<NotebookMainPane> createState() => _NotebookMainPaneState();
}

class _NotebookMainPaneState extends State<NotebookMainPane> {
  final _askController = TextEditingController();

  @override
  void dispose() {
    _askController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final selectedId = widget.controller.selectedNotebookId;
        if (selectedId == null) {
          return _placeholder();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.controller.error != null) _ErrorBanner(text: widget.controller.error!),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sourcesSection(context),
                      const SizedBox(height: 20),
                      _chatsRow(context),
                      const SizedBox(height: 8),
                      _outputsSection(),
                    ],
                  ),
                ),
              ),
            ),
            _askBar(),
          ],
        );
      },
    );
  }

  Widget _placeholder() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined, size: 52, color: Colors.deepPurple.shade200),
              const SizedBox(height: 16),
              const Text('Notebook',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 10),
              const Text(
                'Create a notebook, add some sources, then ask a question grounded '
                'in them.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.4, color: Colors.white38),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sourcesSection(BuildContext context) {
    final controller = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Sources',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
            const Spacer(),
            TextButton.icon(
              onPressed: controller.busy ? null : () => _promptPastedText(context),
              icon: const Icon(Icons.text_snippet_outlined, size: 16),
              label: const Text('Paste text'),
            ),
            TextButton.icon(
              onPressed: controller.busy ? null : () => _promptUrl(context),
              icon: const Icon(Icons.link, size: 16),
              label: const Text('Add URL'),
            ),
            TextButton.icon(
              onPressed: controller.busy ? null : () => controller.addTextFile(),
              icon: const Icon(Icons.upload_file_outlined, size: 16),
              label: const Text('Add file'),
            ),
          ],
        ),
        if (controller.sources.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No sources yet.', style: TextStyle(color: Colors.white38)),
          )
        else
          ...controller.sources.map((s) => _SourceTile(item: s)),
      ],
    );
  }

  /// The chat chips — one per thread in the selected notebook, plus a "New
  /// chat" chip. Mirrors `chat_addon.dart`'s `ChatSessionList` (tap to
  /// select, right-click/long-press for Delete), as a horizontal row rather
  /// than a sidebar list since the sidebar here is already the notebook
  /// list.
  Widget _chatsRow(BuildContext context) {
    final controller = widget.controller;
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final chat in controller.chats)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _ChatChip(
                chat: chat,
                selected: chat.id == controller.selectedChatId,
                onTap: () => controller.selectChat(chat.id),
                onDelete: () => controller.deleteChat(chat.id),
              ),
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 14, color: Colors.white70),
            label: const Text('New chat', style: TextStyle(fontSize: 12, color: Colors.white70)),
            backgroundColor: cardColor,
            onPressed: controller.busy ? null : () => controller.createChat(),
          ),
        ],
      ),
    );
  }

  Widget _outputsSection() {
    final outputs = widget.controller.outputs;
    if (outputs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('No messages in this chat yet.', style: TextStyle(color: Colors.white38)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      // listOutputs returns oldest-first — a chat transcript reads
      // top-to-bottom.
      children: [for (final o in outputs) _OutputTile(output: o)],
    );
  }

  Widget _askBar() {
    final controller = widget.controller;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: borderColor))),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _askController,
              enabled: !controller.busy,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Ask a question about this notebook…',
                hintStyle: TextStyle(color: Colors.white38),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submitAsk(),
            ),
          ),
          const SizedBox(width: 8),
          controller.busy
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(icon: const Icon(Icons.send), onPressed: _submitAsk),
        ],
      ),
    );
  }

  void _submitAsk() {
    final question = _askController.text.trim();
    if (question.isEmpty) return;
    _askController.clear();
    widget.controller.ask(question);
  }

  Future<void> _promptUrl(BuildContext context) async {
    final text = await _promptSingleField(context, title: 'Add a URL', label: 'https://…');
    if (text == null || text.trim().isEmpty) return;
    final uri = Uri.tryParse(text.trim());
    if (uri == null) return;
    await widget.controller.addUrl(uri);
  }

  Future<void> _promptPastedText(BuildContext context) async {
    final result = await showDialog<({String title, String text})>(
      context: context,
      builder: (context) => _PasteTextDialog(),
    );
    if (result != null) await widget.controller.addPastedText(result.title, result.text);
  }
}

Future<String?> _promptSingleField(BuildContext context, {required String title, required String label}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: cardColor,
      title: Text(title, style: const TextStyle(color: Colors.white)),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(labelText: label),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Add')),
      ],
    ),
  );
}

class _PasteTextDialog extends StatefulWidget {
  @override
  State<_PasteTextDialog> createState() => _PasteTextDialogState();
}

class _PasteTextDialogState extends State<_PasteTextDialog> {
  final _title = TextEditingController();
  final _text = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: cardColor,
      title: const Text('Paste text', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              maxLines: 8,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(labelText: 'Text', alignLabelWithHint: true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop((title: _title.text, text: _text.text)),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _ChatChip extends StatelessWidget {
  const _ChatChip({
    required this.chat,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final Chat chat;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  Future<void> _showMenu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      color: cardColor,
      position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
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
    if (action == 'delete') onDelete();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapUp: (details) => _showMenu(context, details.globalPosition),
      onLongPress: () {
        final box = context.findRenderObject() as RenderBox?;
        _showMenu(context, box?.localToGlobal(Offset.zero) ?? Offset.zero);
      },
      child: ChoiceChip(
        label: Text(chat.title, style: const TextStyle(fontSize: 12)),
        selected: selected,
        selectedColor: Colors.deepPurple.shade200.withValues(alpha: 0.3),
        backgroundColor: cardColor,
        labelStyle: TextStyle(color: selected ? Colors.white : Colors.white70),
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.item});

  final RawItem item;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (item.embedStatus) {
      'done' => Colors.greenAccent.shade200,
      'error' => Colors.redAccent.shade200,
      _ => Colors.white38,
    };
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(
            switch (item.kind) {
              SourceKind.url => Icons.link,
              SourceKind.file => Icons.description_outlined,
              SourceKind.paste => Icons.text_snippet_outlined,
            },
            size: 16,
            color: Colors.deepPurple.shade200,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(item.title,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
          Text(item.embedStatus, style: TextStyle(color: statusColor, fontSize: 11)),
        ],
      ),
    );
  }
}

class _OutputTile extends StatelessWidget {
  const _OutputTile({required this.output});

  final Output output;

  @override
  Widget build(BuildContext context) {
    final isUser = output.author == 'user';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isUser ? Colors.transparent : cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isUser ? 'You' : 'AI',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isUser ? Colors.white38 : Colors.deepPurple.shade200)),
          const SizedBox(height: 4),
          Text(output.text, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.red.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(text, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
    );
  }
}
