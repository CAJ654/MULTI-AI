import 'package:flutter/material.dart';

import 'markdown_settings.dart';
import 'theme.dart';
import 'thinking_settings.dart';
import 'thinking_words.dart';

/// The chat settings dialog, behind the gear icon in the top bar.
///
/// Two sections today: the "thinking" row (toggle whole phrase groups on/off,
/// or expand a group to pick individual phrases within it) and message
/// formatting. Each section's changes are pushed live via its own callback so
/// the caller can persist + apply them immediately (see `chat_screen.dart`).
///
/// The class name predates the second section — it is still the only dialog
/// the gear opens.
class ThinkingSettingsDialog extends StatefulWidget {
  const ThinkingSettingsDialog({
    super.key,
    required this.initial,
    required this.onChanged,
    required this.initialMarkdown,
    required this.onMarkdownChanged,
  });

  final ThinkingSettings initial;
  final ValueChanged<ThinkingSettings> onChanged;

  final MarkdownSettings initialMarkdown;
  final ValueChanged<MarkdownSettings> onMarkdownChanged;

  @override
  State<ThinkingSettingsDialog> createState() => _ThinkingSettingsDialogState();
}

class _ThinkingSettingsDialogState extends State<ThinkingSettingsDialog> {
  late final Set<String> _enabledGroups = {...widget.initial.enabledGroups};
  late final Map<String, Set<String>> _disabledWords = {
    for (final e in widget.initial.disabledWords.entries) e.key: {...e.value},
  };
  final Set<String> _expanded = {};

  void _push() {
    widget.onChanged(ThinkingSettings(enabledGroups: {..._enabledGroups}, disabledWords: {
      for (final e in _disabledWords.entries) e.key: {...e.value},
    }));
  }

  void _toggleGroup(String id, bool enabled) {
    setState(() => enabled ? _enabledGroups.add(id) : _enabledGroups.remove(id));
    _push();
  }

  void _toggleWord(String groupId, String word, bool enabled) {
    setState(() {
      final set = _disabledWords.putIfAbsent(groupId, () => {});
      enabled ? set.remove(word) : set.add(word);
    });
    _push();
  }

  late bool _renderUserMarkdown = widget.initialMarkdown.renderUserMessages;

  void _setRenderUserMarkdown(bool enabled) {
    setState(() => _renderUserMarkdown = enabled);
    widget.onMarkdownChanged(
      widget.initialMarkdown.copyWith(renderUserMessages: enabled),
    );
  }

  Widget _sectionHeader(String title, String blurb) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70)),
            const SizedBox(height: 4),
            Text(blurb, style: const TextStyle(fontSize: 12, color: Colors.white54)),
          ],
        ),
      );

  void _setAllWords(ThinkingWordGroup group, bool enabled) {
    setState(() {
      if (enabled) {
        _disabledWords[group.id]?.clear();
      } else {
        _disabledWords[group.id] = {...group.words};
      }
    });
    _push();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Chat settings',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: borderColor),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  _sectionHeader(
                    'Thinking indicator',
                    'What shows in the chat status row while a reply is generating. '
                        'Turn a whole group on or off, or expand it to pick individual phrases.',
                  ),
                  for (final group in thinkingWordGroups) _buildGroup(group),
                  const Divider(height: 24, color: borderColor),
                  _sectionHeader(
                    'Message formatting',
                    'Replies are always formatted — models write in markdown, so showing it '
                        'raw would leave asterisks and backticks on screen.',
                  ),
                  SwitchListTile(
                    value: _renderUserMarkdown,
                    onChanged: _setRenderUserMarkdown,
                    dense: true,
                    activeThumbColor: Colors.deepPurple.shade300,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    title: const Text('Format my messages too',
                        style: TextStyle(fontSize: 13, color: Colors.white)),
                    subtitle: const Text(
                      'Off by default, so what you type appears exactly as typed.',
                      style: TextStyle(fontSize: 11, color: Colors.white38),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroup(ThinkingWordGroup group) {
    final enabled = _enabledGroups.contains(group.id);
    final expanded = _expanded.contains(group.id);
    final disabled = _disabledWords[group.id] ?? const <String>{};
    final activeCount = group.words.length - disabled.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          value: enabled,
          onChanged: (v) => _toggleGroup(group.id, v ?? false),
          activeColor: Colors.deepPurple.shade300,
          checkColor: Colors.white,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(group.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          subtitle: Text(
            '${group.description}\n$activeCount / ${group.words.length} phrases selected',
            style: const TextStyle(fontSize: 11, color: Colors.white38),
          ),
          isThreeLine: true,
          secondary: IconButton(
            icon: Icon(expanded ? Icons.expand_less : Icons.expand_more, color: Colors.white54),
            onPressed: () => setState(() {
              expanded ? _expanded.remove(group.id) : _expanded.add(group.id);
            }),
          ),
        ),
        if (expanded) _buildWordPicker(group, disabled),
        const Divider(height: 1, color: borderColor),
      ],
    );
  }

  Widget _buildWordPicker(ThinkingWordGroup group, Set<String> disabled) {
    return Container(
      color: mainColor,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TextButton(onPressed: () => _setAllWords(group, true), child: const Text('Select all')),
              TextButton(onPressed: () => _setAllWords(group, false), child: const Text('Clear all')),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final word in group.words)
                FilterChip(
                  // Templates (Transparency Log) show a generic filled-in
                  // preview here; the real phrase uses live chat context
                  // instead (see ThinkingIndicator).
                  label: Text(fillThinkingTemplate(word), style: const TextStyle(fontSize: 12)),
                  selected: !disabled.contains(word),
                  onSelected: (v) => _toggleWord(group.id, word, v),
                  selectedColor: Colors.deepPurple.shade400,
                  checkmarkColor: Colors.white,
                  backgroundColor: cardColor,
                  labelStyle: TextStyle(color: disabled.contains(word) ? Colors.white38 : Colors.white),
                  side: BorderSide(color: borderColor),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
