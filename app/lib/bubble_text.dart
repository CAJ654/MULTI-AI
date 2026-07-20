import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import 'theme.dart';

/// Chat-bubble body text, rendered as markdown or shown literally.
///
/// Models emit markdown by default — `**bold**`, `*` bullets, `#` headings,
/// fenced code — so an assistant reply shown through a plain `Text` displays
/// the syntax verbatim. This renders it instead.
///
/// [asMarkdown] is a switch rather than an assumption because the two sides of
/// a conversation want different answers: a model's reply should render, while
/// text the *user* typed should normally come back exactly as typed (see
/// `MarkdownSettings`).
///
/// Rendering deliberately stays tolerant of half-finished input: replies stream
/// in token by token, so mid-stream the text routinely holds an unclosed `**`
/// or an unterminated fence. `gpt_markdown` renders those as plain text rather
/// than throwing or swallowing the rest of the bubble, which is the property
/// that makes it usable on a live stream.
class BubbleText extends StatelessWidget {
  const BubbleText({
    super.key,
    required this.text,
    required this.style,
    required this.asMarkdown,
  });

  final String text;
  final TextStyle style;
  final bool asMarkdown;

  @override
  Widget build(BuildContext context) {
    // SelectableText, not Text: copying a reply out of the chat is a basic
    // affordance and predates this widget.
    if (!asMarkdown) return SelectableText(text, style: style);

    return SelectionArea(
      child: GptMarkdown(
        text,
        style: style,
        // Inline `code` and fenced blocks: tint the surface so they read as
        // code against the bubble rather than as slightly-off body text.
        highlightBuilder: (context, inlineCode, textStyle) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            inlineCode,
            style: textStyle.copyWith(fontFamily: 'monospace', fontSize: style.fontSize),
          ),
        ),
        codeBuilder: (context, name, code, closed) => Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: sidebarColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          // Long lines scroll rather than forcing the bubble wider or
          // overflowing it.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              code,
              style: style.copyWith(fontFamily: 'monospace', fontSize: 13, height: 1.4),
            ),
          ),
        ),
      ),
    );
  }
}
