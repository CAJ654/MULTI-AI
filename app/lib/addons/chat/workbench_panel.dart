import 'package:flutter/material.dart';

import '../../copy_button.dart';
import 'artifacts.dart';
import 'html_preview.dart';
import 'html_sandbox.dart';

/// The workbench side panel: one code block from a reply. HTML and SVG open on a
/// rendered preview, and every block can be flipped to its source. Read-only:
/// editing is a separate step.
class WorkbenchPanel extends StatefulWidget {
  const WorkbenchPanel({super.key, required this.artifact, required this.onClose});

  final Artifact artifact;
  final VoidCallback onClose;

  @override
  State<WorkbenchPanel> createState() => _WorkbenchPanelState();
}

class _WorkbenchPanelState extends State<WorkbenchPanel> {
  late bool _showPreview;

  @override
  void initState() {
    super.initState();
    _showPreview = isPreviewable(widget.artifact);
  }

  @override
  void didUpdateWidget(WorkbenchPanel old) {
    super.didUpdateWidget(old);
    // A different block gets its own default view, not the previous one's.
    if (old.artifact != widget.artifact) {
      _showPreview = isPreviewable(widget.artifact);
    }
  }

  @override
  Widget build(BuildContext context) {
    final artifact = widget.artifact;
    return Material(
      color: const Color(0xFF16161D),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    artifact.label,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isPreviewable(artifact))
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: true, label: Text('Preview')),
                      ButtonSegment(value: false, label: Text('Code')),
                    ],
                    selected: {_showPreview},
                    onSelectionChanged: (s) => setState(() => _showPreview = s.first),
                  ),
                CopyButton(artifact.code),
                IconButton(
                  tooltip: 'Close workbench',
                  icon: const Icon(Icons.close, size: 18, color: Colors.white70),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: _showPreview && isPreviewable(artifact)
                ? HtmlPreview(html: sandboxedHtml(artifact))
                : _source(artifact),
          ),
        ],
      ),
    );
  }

  Widget _source(Artifact artifact) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SelectableText(
            artifact.code,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.45,
              color: Colors.white,
            ),
          ),
        ),
      );
}
