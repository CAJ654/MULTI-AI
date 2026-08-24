import 'dart:async';

/// What the user chose for a pending [ToolApprovalRequest].
enum ToolApprovalDecision {
  /// Run this one call, then ask again next time this tool is used.
  allowOnce,

  /// Run this call and every future call to the same tool for the rest of
  /// this run — see `CodeAgentController._sessionAllowed`.
  allowForSession,

  /// Refuse this call. The agent loop gets a "denied by user" tool result
  /// and can try something else or explain why it stopped.
  deny,
}

/// One gated tool call (`write_file`/`edit_file`/`run_command`) waiting on a
/// user decision. `CodeAgentController` pushes these on
/// [CodeAgentController.approvalRequests]; the pane's [State] shows
/// [ToolApprovalDialog] and completes [completer] with the result.
class ToolApprovalRequest {
  ToolApprovalRequest({
    required this.toolName,
    required this.argsSummary,
    required this.completer,
  });

  final String toolName;

  /// A human-readable one-or-few-line rendering of what the call would do —
  /// e.g. the resolved path for `write_file`, or the full command line for
  /// `run_command`. Built by the controller, which knows the project root
  /// tools are scoped to; the dialog just displays it.
  final String argsSummary;

  final Completer<ToolApprovalDecision> completer;
}
