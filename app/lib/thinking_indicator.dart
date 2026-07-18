import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'thinking_words.dart';

/// The rotating status text in the chat "thinking" row. Cycles through
/// `words` on a timer with a fade transition; shows a plain static message
/// if the user has disabled every phrase group (see `thinking_settings.dart`).
///
/// Entries may be Transparency Log templates containing `{query}`/`{model}`
/// placeholders — `query` and `modelName` fill those in with the live chat
/// context so those phrases read as if they're narrating this actual request.
class ThinkingIndicator extends StatefulWidget {
  const ThinkingIndicator({super.key, required this.words, this.query, this.modelName});

  final List<String> words;
  final String? query;
  final String? modelName;

  @override
  State<ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<ThinkingIndicator> {
  static const _interval = Duration(milliseconds: 2200);
  final _random = Random();
  Timer? _timer;
  // Assigned in initState, not as a field initializer: a `late` field's
  // initializer expression runs lazily on first read, and if that read
  // happens from inside the initializer itself (as it would here, via
  // _pickNext's self-comparison), Dart re-enters the same lazy
  // initialization and never settles — it doesn't throw a clean error, it
  // corrupts the read into a degenerate value that blew up layout instead.
  late String _current;

  String _pickInitial() {
    if (widget.words.isEmpty) return 'Thinking…';
    return widget.words[_random.nextInt(widget.words.length)];
  }

  // Avoids repeating the same phrase twice in a row; only safe to call once
  // `_current` already holds a value.
  String _pickNext() {
    if (widget.words.isEmpty) return 'Thinking…';
    if (widget.words.length == 1) return widget.words.first;
    String next;
    do {
      next = widget.words[_random.nextInt(widget.words.length)];
    } while (next == _current);
    return next;
  }

  @override
  void initState() {
    super.initState();
    _current = _pickInitial();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.words.length <= 1) return;
    _timer = Timer.periodic(_interval, (_) {
      if (!mounted) return;
      setState(() => _current = _pickNext());
    });
  }

  @override
  void didUpdateWidget(covariant ThinkingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.words != widget.words) {
      _current = _pickNext();
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final display = fillThinkingTemplate(_current, query: widget.query, model: widget.modelName);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Text(
        display,
        key: ValueKey(_current),
        style: const TextStyle(fontSize: 13, color: Colors.white54),
      ),
    );
  }
}
