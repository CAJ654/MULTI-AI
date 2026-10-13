import 'package:flutter/material.dart';

import '../../theme.dart';
import 'memory_store.dart';
import 'notebook_addon.dart';

/// The notebook list — create, select, delete. Mirrors
/// `components/components_addon.dart`'s `ComponentRosterList`: one card per
/// row, `ListenableBuilder` over the shared controller.
class NotebookSidebarPanel extends StatelessWidget {
  const NotebookSidebarPanel({super.key, required this.controller});

  final NotebookController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _promptNewNotebook(context),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New notebook'),
              ),
            ),
          ),
          Expanded(
            child: controller.notebooks.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No notebooks yet', style: TextStyle(color: Colors.white54)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    itemCount: controller.notebooks.length,
                    itemBuilder: (context, i) {
                      final notebook = controller.notebooks[i];
                      final selected = notebook.id == controller.selectedNotebookId;
                      return _NotebookTile(
                        notebook: notebook,
                        selected: selected,
                        onTap: () => controller.selectNotebook(notebook.id),
                        onDelete: () => controller.deleteNotebook(notebook.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _promptNewNotebook(BuildContext context) async {
    final title = await _promptText(context, title: 'New notebook', label: 'Title');
    if (title != null && title.trim().isNotEmpty) {
      await controller.createNotebook(title.trim());
    }
  }
}

class _NotebookTile extends StatelessWidget {
  const _NotebookTile({
    required this.notebook,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final Notebook notebook;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selected ? cardColor : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? Colors.deepPurple.shade200 : borderColor),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.menu_book_outlined, size: 18, color: Colors.deepPurple.shade200),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    notebook.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.white38),
                  onPressed: onDelete,
                  tooltip: 'Delete notebook',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A single-field text prompt dialog — shared by the sidebar's "new
/// notebook" action and the main pane's "paste text" source action.
Future<String?> _promptText(BuildContext context, {required String title, required String label}) {
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
        TextButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
