import 'package:flutter/material.dart';

import '../../theme.dart';
import 'tool_approval.dart';

/// Asks the user to approve a gated tool call before it runs. Chrome mirrors
/// `storage_settings_dialog.dart`/`thinking_settings_dialog.dart` (a
/// [Dialog] on [cardColor], 16px corner radius, a header row with a close
/// button) so it reads as this app's own dialog rather than a one-off.
class ToolApprovalDialog extends StatelessWidget {
  const ToolApprovalDialog({super.key, required this.request});

  final ToolApprovalRequest request;

  void _decide(BuildContext context, ToolApprovalDecision decision) {
    if (!request.completer.isCompleted) request.completer.complete(decision);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // A dialog dismissed by tapping outside/back must still resolve the
      // pending tool call — otherwise the agent loop hangs waiting for a
      // decision that will never come.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !request.completer.isCompleted) {
          request.completer.complete(ToolApprovalDecision.deny);
        }
      },
      child: Dialog(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, size: 18, color: Colors.amber),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Approve action',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'The Code assistant wants to run:',
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: mainColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(request.toolName,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.deepPurple.shade200)),
                      const SizedBox(height: 6),
                      SelectableText(request.argsSummary,
                          style: const TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              fontFamily: 'monospace',
                              color: Colors.white70)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: borderColor),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => _decide(context, ToolApprovalDecision.deny),
                        child: const Text('Deny', style: TextStyle(color: Colors.white54)),
                      ),
                    ),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            _decide(context, ToolApprovalDecision.allowOnce),
                        child: const Text('Allow once'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.deepPurple.shade400),
                        onPressed: () =>
                            _decide(context, ToolApprovalDecision.allowForSession),
                        child: const Text('Allow for session'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
