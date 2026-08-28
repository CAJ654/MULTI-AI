import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A small "Copy" affordance for AI response text. Copies [text] to the
/// system clipboard and flips to a checkmark for a couple of seconds as
/// feedback, then reverts.
///
/// Self-contained (owns its own copied/not-copied state) so it can be dropped
/// under any AI response — a chat bubble, a council step card — without the
/// caller wiring up a SnackBar or other feedback channel.
class CopyButton extends StatefulWidget {
  const CopyButton(this.text, {super.key});

  /// The raw text to copy. The button renders disabled when this is empty.
  final String text;

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.text));
    _resetTimer?.cancel();
    setState(() => _copied = true);
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = _copied ? Colors.greenAccent : Colors.white54;
    return Tooltip(
      message: _copied ? 'Copied!' : 'Copy to clipboard',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: widget.text.isEmpty ? null : _copy,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_copied ? Icons.check : Icons.copy_outlined, size: 14, color: color),
              const SizedBox(width: 4),
              Text(_copied ? 'Copied' : 'Copy', style: TextStyle(fontSize: 12, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
