import 'package:flutter/material.dart';

import 'backend_process.dart';
import 'theme.dart';

/// What happens to the downloaded AI runtime when Multi-AI is uninstalled.
///
/// This exists because the answer cannot be asked for at the time it matters.
/// The old Inno installer prompted during uninstall; Velopack, which replaced
/// it, runs uninstall hooks with no UI allowed and a 30-second budget, so the
/// choice has to be made ahead of time and simply read by the hook. See
/// [BackendRuntime.removeRuntimeOnUninstall].
///
/// Written straight through on toggle rather than via an onChanged callback —
/// unlike ThinkingSettingsDialog, nothing in the running app reacts to this
/// setting, so there is no live state for a caller to apply.
class StorageSettingsDialog extends StatefulWidget {
  const StorageSettingsDialog({super.key});

  @override
  State<StorageSettingsDialog> createState() => _StorageSettingsDialogState();
}

class _StorageSettingsDialogState extends State<StorageSettingsDialog> {
  late bool _keep = BackendRuntime.keepsRuntimeOnUninstall;

  void _setKeep(bool keep) {
    setState(() => _keep = keep);
    BackendRuntime.setKeepRuntimeOnUninstall(keep);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
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
                  const Expanded(
                    child: Text('Storage',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'The AI runtime — PyTorch and the libraries the server-backed '
                'models need — is about 2.5 GB and was downloaded on first '
                'launch. App updates never re-download it.',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ),
            const Divider(height: 1, color: borderColor),
            CheckboxListTile(
              value: _keep,
              onChanged: (v) => _setKeep(v ?? false),
              activeColor: Colors.deepPurple.shade300,
              checkColor: Colors.white,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Keep it if I uninstall Multi-AI',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
              subtitle: Text(
                _keep
                    ? 'Uninstalling leaves the 2.5 GB in place, so reinstalling '
                        'skips the first-run download.'
                    : 'Uninstalling also removes the 2.5 GB. Reinstalling will '
                        'download it again.',
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
              isThreeLine: true,
            ),
            const Divider(height: 1, color: borderColor),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: Text(
                'Downloaded model weights live in your Hugging Face cache and '
                'are never removed by uninstalling, either way.',
                style: TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
