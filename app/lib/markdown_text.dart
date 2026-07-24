import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

/// Renders model output as Markdown.
///
/// Every model in this app — server-backed (`transformers`) and on-device
/// (llama.cpp) alike — emits Markdown: headings, **bold**, `code`, fenced code
/// blocks, lists, tables, links. Rendered as a flat string those markers read
/// as literal noise (`**Paris**` instead of a bold word), so the assistant
/// bubble routes its text through here instead of a plain [SelectableText].
/// Because replies arrive complete rather than streaming into the bubble (see
/// `_send` in chat_screen.dart), there's no half-written-fence case to guard.
///
/// This is a deliberately small, dependency-free CommonMark subset rather than
/// a package: `flutter_markdown` is discontinued, and pulling a fork in would
/// churn the lockfile that the Windows release pipeline resolves for a feature
/// that only needs the handful of constructs LLMs actually emit. Anything it
/// doesn't recognize degrades to literal text — exactly the old behavior — so a
/// missed construct is never worse than before.
///
/// Selection works per block (each paragraph/code block is its own
/// [SelectableText]); a drag can't span two blocks, which matches how the
/// `flutter_markdown` package behaved too. A block that contains a link is the
/// exception — see [_richText].
class MarkdownText extends StatefulWidget {
  const MarkdownText(this.data, {super.key, required this.baseStyle, this.onTapLink});

  /// The raw Markdown to render (a model reply).
  final String data;

  /// Colour/height/size the text inherits; emphasis and headings derive from it.
  final TextStyle baseStyle;

  /// Invoked with a link's URL when it's tapped. Defaults to opening the URL in
  /// the platform's browser; injectable so a test can observe taps without the
  /// url_launcher platform channel.
  final void Function(String url)? onTapLink;

  @override
  State<MarkdownText> createState() => _MarkdownTextState();
}

class _MarkdownTextState extends State<MarkdownText> {
  // Tap recognizers are long-lived objects that must be disposed; they're built
  // while parsing and torn down here, rebuilt only when the source changes.
  final List<TapGestureRecognizer> _recognizers = [];
  late List<Widget> _blocks;

  @override
  void initState() {
    super.initState();
    _blocks = _render();
  }

  @override
  void didUpdateWidget(MarkdownText old) {
    super.didUpdateWidget(old);
    if (old.data != widget.data ||
        old.baseStyle != widget.baseStyle ||
        old.onTapLink != widget.onTapLink) {
      _blocks = _render();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  List<Widget> _render() {
    _disposeRecognizers();
    final ctx = _MdContext(widget.onTapLink ?? _openExternally, _recognizers);
    return _buildBlocks(widget.data, widget.baseStyle, ctx);
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  /// Opens a tapped link in the default browser. Silently ignores anything that
  /// isn't a launchable absolute URL — a malformed href in a model reply
  /// shouldn't throw into the chat.
  void _openExternally(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) return;
    launchUrl(uri, mode: LaunchMode.externalApplication)
        .then((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _blocks[i],
        ],
      ],
    );
  }
}

/// Carries the link-tap callback down through the parse and collects the
/// recognizers it mints so the widget can dispose them.
class _MdContext {
  _MdContext(this.onTapLink, this.recognizers);

  final void Function(String url) onTapLink;
  final List<TapGestureRecognizer> recognizers;

  TapGestureRecognizer recognizerFor(String url) {
    final r = TapGestureRecognizer()..onTap = () => onTapLink(url);
    recognizers.add(r);
    return r;
  }
}

// A monospaced stack that resolves on every target — 'monospace' alone renders
// as the proportional default on Windows desktop, so name real fonts first.
const _monoFallback = <String>[
  'Consolas',
  'SF Mono',
  'Menlo',
  'Roboto Mono',
  'Courier New',
  'monospace',
];

// ---------------------------------------------------------------- block parse

/// Splits [data] into block-level widgets. Line-oriented, single pass: each
/// branch either consumes a run of lines into one block or falls through to
/// gather a paragraph.
List<Widget> _buildBlocks(String data, TextStyle base, _MdContext ctx) {
  final lines = data.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final widgets = <Widget>[];
  var i = 0;

  while (i < lines.length) {
    final line = lines[i];
    final trimmed = line.trim();

    // Blank line — just a separator between blocks.
    if (trimmed.isEmpty) {
      i++;
      continue;
    }

    // Fenced code block (``` or ~~~). Content is verbatim: no inline parsing,
    // and the closing fence must match the opener's character.
    final fence = _fenceMarker(trimmed);
    if (fence != null) {
      final code = <String>[];
      i++;
      while (i < lines.length && lines[i].trim() != fence) {
        code.add(lines[i]);
        i++;
      }
      if (i < lines.length) i++; // consume the closing fence
      widgets.add(_codeBlock(code.join('\n'), base));
      continue;
    }

    // ATX heading (# .. ######).
    final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
    if (heading != null) {
      widgets.add(_heading(heading.group(2)!.trim(), heading.group(1)!.length, base, ctx));
      i++;
      continue;
    }

    // Horizontal rule: three or more -, *, or _ alone on a line.
    if (_hrPattern.hasMatch(line)) {
      widgets.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Divider(color: borderColor, height: 1),
      ));
      i++;
      continue;
    }

    // GFM table: a row with pipes followed by a |---|:--:| separator row.
    if (trimmed.contains('|') &&
        i + 1 < lines.length &&
        _isTableSeparator(lines[i + 1])) {
      final table = <String>[line, lines[i + 1]];
      i += 2;
      while (i < lines.length &&
          lines[i].contains('|') &&
          lines[i].trim().isNotEmpty) {
        table.add(lines[i]);
        i++;
      }
      widgets.add(_table(table, base, ctx));
      continue;
    }

    // Blockquote — consecutive `>` lines, the marker stripped.
    if (_quotePattern.hasMatch(line)) {
      final quote = <String>[];
      while (i < lines.length && _quotePattern.hasMatch(lines[i])) {
        quote.add(lines[i].replaceFirst(RegExp(r'^ {0,3}> ?'), ''));
        i++;
      }
      widgets.add(_blockquote(quote.join('\n'), base, ctx));
      continue;
    }

    // List — a run of bullet or ordered items.
    if (_listItem(line) != null) {
      final items = <_ListItem>[];
      while (i < lines.length) {
        final item = _listItem(lines[i]);
        if (item == null) break;
        items.add(item);
        i++;
      }
      widgets.add(_list(items, base, ctx));
      continue;
    }

    // Paragraph — gather lines until a blank line or the start of another block.
    final para = <String>[];
    while (i < lines.length) {
      final l = lines[i];
      if (l.trim().isEmpty ||
          _fenceMarker(l.trim()) != null ||
          RegExp(r'^(#{1,6})\s+').hasMatch(l) ||
          _hrPattern.hasMatch(l) ||
          _quotePattern.hasMatch(l) ||
          _listItem(l) != null) {
        break;
      }
      para.add(l);
      i++;
    }
    widgets.add(_paragraph(para.join('\n'), base, ctx));
  }

  return widgets;
}

final _hrPattern = RegExp(r'^ {0,3}([-*_])( *\1){2,} *$');
final _quotePattern = RegExp(r'^ {0,3}>');

/// The fence string (``` or ~~~, matched by run length) if [trimmed] opens a
/// fenced code block, else null. Any trailing language tag is ignored.
String? _fenceMarker(String trimmed) {
  final m = RegExp(r'^(`{3,}|~{3,})').firstMatch(trimmed);
  return m?.group(1);
}

// ------------------------------------------------------------- block builders

Widget _paragraph(String text, TextStyle base, _MdContext ctx) {
  final before = ctx.recognizers.length;
  final spans = _inlineSpans(text, base, ctx);
  return _richText(spans, base, ctx.recognizers.length > before);
}

Widget _heading(String text, int level, TextStyle base, _MdContext ctx) {
  // Scale the inherited size so a heading reads as one even without a distinct
  // font; h5/h6 lean on weight alone.
  const scales = [1.6, 1.42, 1.26, 1.14, 1.0, 0.95];
  final style = base.copyWith(
    fontWeight: FontWeight.bold,
    fontSize: (base.fontSize ?? 14) * scales[level - 1],
    height: 1.3,
  );
  final before = ctx.recognizers.length;
  final spans = _inlineSpans(text, style, ctx);
  return _richText(spans, style, ctx.recognizers.length > before);
}

Widget _codeBlock(String code, TextStyle base) {
  final style = base.copyWith(
    fontFamily: _monoFallback.first,
    fontFamilyFallback: _monoFallback,
    fontSize: (base.fontSize ?? 14) * 0.92,
    height: 1.45,
    color: const Color(0xFFE6E1F5),
  );
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFF15161C),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: borderColor),
    ),
    // Code lines don't wrap; they scroll, so a long line never squeezes the
    // rest of the reply.
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SelectableText(code, style: style),
    ),
  );
}

Widget _blockquote(String text, TextStyle base, _MdContext ctx) {
  final style = base.copyWith(color: Colors.white70, fontStyle: FontStyle.italic);
  final before = ctx.recognizers.length;
  final spans = _inlineSpans(text, style, ctx);
  return Container(
    padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
    decoration: const BoxDecoration(
      border: Border(left: BorderSide(color: Color(0xFF6D5BD0), width: 3)),
    ),
    child: _richText(spans, style, ctx.recognizers.length > before),
  );
}

Widget _list(List<_ListItem> items, TextStyle base, _MdContext ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final it in items)
          Padding(
            padding: EdgeInsets.only(left: 4 + it.indent * 18.0, top: 2, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: it.ordinal == null ? 18 : 26,
                  child: Text(
                    it.ordinal == null ? '•' : '${it.ordinal}.',
                    style: base.copyWith(
                      fontWeight:
                          it.ordinal == null ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                Expanded(child: _listItemBody(it.content, base, ctx)),
              ],
            ),
          ),
      ],
    );

Widget _listItemBody(String content, TextStyle base, _MdContext ctx) {
  final before = ctx.recognizers.length;
  final spans = _inlineSpans(content, base, ctx);
  return _richText(spans, base, ctx.recognizers.length > before);
}

Widget _table(List<String> lines, TextStyle base, _MdContext ctx) {
  final header = _splitRow(lines[0]);
  final cols = header.length;
  final rows = [for (var r = 2; r < lines.length; r++) _splitRow(lines[r])];
  final headerStyle = base.copyWith(fontWeight: FontWeight.bold);

  // Cells stay non-selectable Text.rich: an IntrinsicColumnWidth table sizes
  // each column by measuring its children, and SelectableText's editable
  // machinery doesn't report an intrinsic width, which throws under that. Text
  // .rich also delivers link taps directly, so links inside cells just work.
  Widget cell(String text, TextStyle style) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text.rich(TextSpan(style: style, children: _inlineSpans(text, style, ctx))),
      );

  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: const TableBorder.symmetric(inside: BorderSide(color: borderColor)),
        children: [
          TableRow(
            decoration: const BoxDecoration(color: cardColor),
            children: [
              for (var c = 0; c < cols; c++)
                cell(c < header.length ? header[c] : '', headerStyle),
            ],
          ),
          for (final row in rows)
            TableRow(
              children: [
                for (var c = 0; c < cols; c++)
                  cell(c < row.length ? row[c] : '', base),
              ],
            ),
        ],
      ),
    ),
  );
}

/// A rich-text block. A [TapGestureRecognizer] on a span inside a
/// [SelectableText] fights the selection gesture and often never fires, so a
/// block that carries a link ([hasLink]) is rendered non-selectable via
/// [Text.rich] to keep the tap reliable; link-free blocks stay selectable.
Widget _richText(List<InlineSpan> spans, TextStyle style, bool hasLink) {
  final span = TextSpan(style: style, children: spans);
  return hasLink ? Text.rich(span) : SelectableText.rich(span);
}

/// True if [line] is a table's `|---|:--:|` separator: every pipe-delimited
/// cell is dashes with optional alignment colons.
bool _isTableSeparator(String line) {
  final cells = _splitRow(line);
  if (cells.isEmpty) return false;
  return cells.every((c) => RegExp(r'^:?-+:?$').hasMatch(c.trim()));
}

/// Splits a table row on pipes, dropping the optional leading/trailing pipe and
/// trimming each cell.
List<String> _splitRow(String line) {
  var s = line.trim();
  if (s.startsWith('|')) s = s.substring(1);
  if (s.endsWith('|')) s = s.substring(0, s.length - 1);
  return [for (final c in s.split('|')) c.trim()];
}

class _ListItem {
  const _ListItem(this.indent, this.ordinal, this.content);

  /// Nesting depth, derived from leading indentation (2 spaces / level).
  final int indent;

  /// The number for an ordered item ("1"), or null for a bullet.
  final String? ordinal;

  final String content;
}

/// Parses [line] as a list item, or null if it isn't one.
_ListItem? _listItem(String line) {
  final m = RegExp(r'^(\s*)(?:([-*+])|(\d+)[.)])\s+(.*)$').firstMatch(line);
  if (m == null) return null;
  final indent = m.group(1)!.replaceAll('\t', '  ').length ~/ 2;
  return _ListItem(indent, m.group(3), m.group(4)!);
}

// ------------------------------------------------------------- inline parse

/// Turns one block of text into styled spans: inline code, links, and
/// emphasis. Recursive, so emphasis nests (bold inside a link, italic inside
/// bold). [recognizer], when set, is attached to every leaf span produced so a
/// whole link label — including any bold/italic inside it — is tappable.
/// Anything unrecognized is emitted verbatim.
List<InlineSpan> _inlineSpans(
  String text,
  TextStyle base,
  _MdContext ctx, {
  TapGestureRecognizer? recognizer,
}) {
  final spans = <InlineSpan>[];
  final buf = StringBuffer();
  void flush() {
    if (buf.isNotEmpty) {
      spans.add(TextSpan(text: buf.toString(), style: base, recognizer: recognizer));
      buf.clear();
    }
  }

  var i = 0;
  while (i < text.length) {
    // Inline code — highest precedence, its content is never re-parsed.
    if (text[i] == '`') {
      final close = text.indexOf('`', i + 1);
      if (close > i) {
        flush();
        spans.add(TextSpan(
          text: text.substring(i + 1, close),
          recognizer: recognizer,
          style: base.copyWith(
            fontFamily: _monoFallback.first,
            fontFamilyFallback: _monoFallback,
            backgroundColor: const Color(0x33000000),
            color: const Color(0xFFE6E1F5),
          ),
        ));
        i = close + 1;
        continue;
      }
    }

    // Math: \( \), \[ \], $$ $$, or $ … $. The app has no math typesetter, so
    // the LaTeX is converted to Unicode (10^{23} → 10²³, \times → ×) rather
    // than shown raw. Its content is never parsed as Markdown.
    final math = _mathAt(text, i);
    if (math != null) {
      flush();
      spans.add(TextSpan(text: math.rendered, style: base, recognizer: recognizer));
      i = math.end;
      continue;
    }

    // Link: [label](url). Its label is tappable, opening the URL; nested
    // emphasis in the label inherits the same recognizer.
    final link = _linkAt(text, i);
    if (link != null) {
      flush();
      final r = ctx.recognizerFor(link.url);
      spans.addAll(_inlineSpans(
        link.label,
        base.copyWith(
          color: const Color(0xFF8AB4F8),
          decoration: TextDecoration.underline,
          decorationColor: const Color(0xFF8AB4F8),
        ),
        ctx,
        recognizer: r,
      ));
      i = link.end;
      continue;
    }

    // Emphasis: ***/___, **/__, ~~, */_.
    final emph = _emphasisAt(text, i, base, ctx, recognizer);
    if (emph != null) {
      flush();
      spans.addAll(emph.spans);
      i = emph.end;
      continue;
    }

    buf.write(text[i]);
    i++;
  }

  flush();
  return spans;
}

class _Link {
  const _Link(this.label, this.url, this.end);
  final String label;
  final String url;
  final int end;
}

_Link? _linkAt(String text, int i) {
  if (text[i] != '[') return null;
  final close = text.indexOf(']', i + 1);
  if (close < 0 || close + 1 >= text.length || text[close + 1] != '(') return null;
  final paren = text.indexOf(')', close + 2);
  if (paren < 0) return null;
  return _Link(text.substring(i + 1, close), text.substring(close + 2, paren), paren + 1);
}

// ------------------------------------------------------------------- math

class _Math {
  const _Math(this.rendered, this.end);
  final String rendered;
  final int end;
}

/// A math span at [i] — delimited by `\( \)`, `\[ \]`, `$$ $$`, or `$ … $` —
/// converted from LaTeX to Unicode, or null if [i] doesn't open one. Bare `$`
/// is only treated as math when its content carries a LaTeX signal (`\`, `^`,
/// `_`), so prose like "it costs $5 and $10" is left alone.
_Math? _mathAt(String text, int i) {
  if (text[i] == r'\' && i + 1 < text.length) {
    final open = text[i + 1];
    if (open == '(' || open == '[') {
      final closer = open == '(' ? r'\)' : r'\]';
      final end = text.indexOf(closer, i + 2);
      if (end >= 0) return _Math(_latexToUnicode(text.substring(i + 2, end)), end + 2);
    }
    return null;
  }
  if (_startsWith(text, i, r'$$')) {
    final end = text.indexOf(r'$$', i + 2);
    if (end >= 0) return _Math(_latexToUnicode(text.substring(i + 2, end)), end + 2);
  }
  if (text[i] == r'$') {
    final end = text.indexOf(r'$', i + 1);
    if (end > i + 1) {
      final inner = text.substring(i + 1, end);
      if (inner.contains(r'\') || inner.contains('^') || inner.contains('_')) {
        return _Math(_latexToUnicode(inner), end + 1);
      }
    }
  }
  return null;
}

/// Best-effort LaTeX → Unicode for the inline math LLMs actually emit: symbols,
/// Greek, and super/subscripts. Anything unmapped degrades to plain text (a
/// bare `\times` becomes "times", an unmappable exponent keeps its caret) —
/// always better than the raw source, never a rendering crash.
String _latexToUnicode(String tex) {
  var s = tex;
  // \text{…}, \mathrm{…} etc. — keep the inner text, drop the wrapper.
  s = s.replaceAllMapped(
      RegExp(r'\\(?:text|mathrm|mathbf|mathit|mathsf|operatorname)\s*\{([^{}]*)\}'),
      (m) => m[1]!);
  // \frac{a}{b} → a/b; \sqrt{x} → √x.
  s = s.replaceAllMapped(
      RegExp(r'\\frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}'), (m) => '${m[1]}/${m[2]}');
  s = s.replaceAllMapped(RegExp(r'\\sqrt\s*\{([^{}]*)\}'), (m) => '√${m[1]}');
  // Spacing escapes (\, \; \: \! and backslash-space) → a single space.
  s = s.replaceAll(RegExp(r'\\[,;:! ]'), ' ');
  // Named commands: \times → ×, \alpha → α, \left → (removed), else the name.
  s = s.replaceAllMapped(
      RegExp(r'\\([a-zA-Z]+)'), (m) => _texCommands[m[1]!] ?? m[1]!);
  // Super/subscripts, then any grouping braces that are left over.
  s = _applyScript(s, '^', _superscripts);
  s = _applyScript(s, '_', _subscripts);
  s = s.replaceAll('{', '').replaceAll('}', '');
  return s.replaceAll(RegExp(r' {2,}'), ' ').trim();
}

/// Replaces `marker{group}` / `marker c` runs (e.g. `^{23}`, `_2`) with their
/// Unicode equivalents from [map]. A group only converts if every character
/// maps; otherwise the marker and text are kept literally so nothing is lost.
String _applyScript(String s, String marker, Map<String, String> map) {
  final out = StringBuffer();
  var i = 0;
  while (i < s.length) {
    if (s[i] == marker && i + 1 < s.length) {
      String group;
      int next;
      if (s[i + 1] == '{') {
        final close = s.indexOf('}', i + 2);
        if (close < 0) {
          out.write(s[i]);
          i++;
          continue;
        }
        group = s.substring(i + 2, close);
        next = close + 1;
      } else {
        group = s[i + 1];
        next = i + 2;
      }
      final converted = _mapAll(group, map);
      out.write(converted ?? '$marker$group');
      i = next;
    } else {
      out.write(s[i]);
      i++;
    }
  }
  return out.toString();
}

/// Maps every character of [group] through [map], or null if any is missing.
String? _mapAll(String group, Map<String, String> map) {
  final sb = StringBuffer();
  for (final ch in group.split('')) {
    final u = map[ch];
    if (u == null) return null;
    sb.write(u);
  }
  return sb.toString();
}

const _superscripts = <String, String>{
  '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
  '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
  '+': '⁺', '-': '⁻', '=': '⁼', '(': '⁽', ')': '⁾', 'n': 'ⁿ', 'i': 'ⁱ',
  'a': 'ᵃ', 'b': 'ᵇ', 'c': 'ᶜ', 'd': 'ᵈ', 'e': 'ᵉ', 'f': 'ᶠ', 'g': 'ᵍ',
  'h': 'ʰ', 'j': 'ʲ', 'k': 'ᵏ', 'l': 'ˡ', 'm': 'ᵐ', 'o': 'ᵒ', 'p': 'ᵖ',
  'r': 'ʳ', 's': 'ˢ', 't': 'ᵗ', 'u': 'ᵘ', 'v': 'ᵛ', 'w': 'ʷ', 'x': 'ˣ',
  'y': 'ʸ', 'z': 'ᶻ',
};

const _subscripts = <String, String>{
  '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄',
  '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
  '+': '₊', '-': '₋', '=': '₌', '(': '₍', ')': '₎',
  'a': 'ₐ', 'e': 'ₑ', 'h': 'ₕ', 'i': 'ᵢ', 'j': 'ⱼ', 'k': 'ₖ', 'l': 'ₗ',
  'm': 'ₘ', 'n': 'ₙ', 'o': 'ₒ', 'p': 'ₚ', 'r': 'ᵣ', 's': 'ₛ', 't': 'ₜ',
  'u': 'ᵤ', 'v': 'ᵥ', 'x': 'ₓ',
};

// LaTeX command name → Unicode. \left/\right map to '' so `\left(` becomes `(`;
// unmapped names fall through to their bare word in _latexToUnicode.
const _texCommands = <String, String>{
  'times': '×', 'div': '÷', 'cdot': '·', 'pm': '±', 'mp': '∓', 'ast': '∗',
  'star': '⋆', 'circ': '∘', 'bullet': '•', 'oplus': '⊕', 'otimes': '⊗',
  'leq': '≤', 'le': '≤', 'geq': '≥', 'ge': '≥', 'neq': '≠', 'ne': '≠',
  'approx': '≈', 'equiv': '≡', 'sim': '∼', 'simeq': '≃', 'cong': '≅',
  'propto': '∝', 'll': '≪', 'gg': '≫',
  'subset': '⊂', 'supset': '⊃', 'subseteq': '⊆', 'supseteq': '⊇',
  'in': '∈', 'notin': '∉', 'ni': '∋', 'cup': '∪', 'cap': '∩',
  'emptyset': '∅', 'varnothing': '∅', 'forall': '∀', 'exists': '∃',
  'neg': '¬', 'land': '∧', 'lor': '∨', 'wedge': '∧', 'vee': '∨',
  'rightarrow': '→', 'to': '→', 'longrightarrow': '⟶', 'leftarrow': '←',
  'gets': '←', 'leftrightarrow': '↔', 'Rightarrow': '⇒', 'implies': '⇒',
  'Leftarrow': '⇐', 'Leftrightarrow': '⇔', 'iff': '⇔', 'mapsto': '↦',
  'uparrow': '↑', 'downarrow': '↓',
  'infty': '∞', 'partial': '∂', 'nabla': '∇', 'sum': '∑', 'prod': '∏',
  'int': '∫', 'oint': '∮', 'sqrt': '√', 'angle': '∠', 'degree': '°',
  'perp': '⊥', 'parallel': '∥', 'therefore': '∴', 'because': '∵',
  'ldots': '…', 'dots': '…', 'cdots': '⋯', 'vdots': '⋮', 'ddots': '⋱',
  'prime': '′', 'hbar': 'ℏ', 'ell': 'ℓ', 'Re': 'ℜ', 'Im': 'ℑ', 'aleph': 'ℵ',
  'left': '', 'right': '', 'big': '', 'Big': '', 'bigg': '', 'Bigg': '',
  'quad': '  ', 'qquad': '    ', 'displaystyle': '', 'textstyle': '',
  // Greek — lowercase
  'alpha': 'α', 'beta': 'β', 'gamma': 'γ', 'delta': 'δ', 'epsilon': 'ε',
  'varepsilon': 'ε', 'zeta': 'ζ', 'eta': 'η', 'theta': 'θ', 'vartheta': 'ϑ',
  'iota': 'ι', 'kappa': 'κ', 'lambda': 'λ', 'mu': 'μ', 'nu': 'ν', 'xi': 'ξ',
  'pi': 'π', 'varpi': 'ϖ', 'rho': 'ρ', 'varrho': 'ϱ', 'sigma': 'σ',
  'varsigma': 'ς', 'tau': 'τ', 'upsilon': 'υ', 'phi': 'φ', 'varphi': 'φ',
  'chi': 'χ', 'psi': 'ψ', 'omega': 'ω',
  // Greek — uppercase
  'Gamma': 'Γ', 'Delta': 'Δ', 'Theta': 'Θ', 'Lambda': 'Λ', 'Xi': 'Ξ',
  'Pi': 'Π', 'Sigma': 'Σ', 'Upsilon': 'Υ', 'Phi': 'Φ', 'Psi': 'Ψ',
  'Omega': 'Ω',
};

class _Emph {
  const _Emph(this.spans, this.end);
  final List<InlineSpan> spans;
  final int end;
}

// marker, kind (1 bold, 2 italic, 3 bold+italic, 4 strike), and whether the
// marker needs word boundaries. Underscores are boundary-checked so a
// snake_case identifier or a file_name isn't sliced into emphasis; asterisks
// are intraword like CommonMark. Longest markers first so `***` wins over `**`.
const _emphSpecs = <List<Object>>[
  ['***', 3, false],
  ['___', 3, true],
  ['~~', 4, false],
  ['**', 1, false],
  ['__', 1, true],
  ['*', 2, false],
  ['_', 2, true],
];

_Emph? _emphasisAt(
  String text,
  int i,
  TextStyle base,
  _MdContext ctx,
  TapGestureRecognizer? recognizer,
) {
  for (final spec in _emphSpecs) {
    final marker = spec[0] as String;
    final kind = spec[1] as int;
    final boundary = spec[2] as bool;

    if (!_startsWith(text, i, marker)) continue;
    if (boundary && i > 0 && _isWord(text[i - 1])) continue;

    final afterOpen = i + marker.length;
    // Left-flanking: an opener touching whitespace (or nothing) isn't emphasis
    // — this is what keeps "a * b * c" from italicizing " b ".
    if (afterOpen >= text.length || _isSpace(text[afterOpen])) continue;

    var j = afterOpen;
    while (true) {
      final close = text.indexOf(marker, j);
      if (close < 0) break;
      // Right-flanking: a closer must not touch whitespace on its inner side.
      if (_isSpace(text[close - 1])) {
        j = close + 1;
        continue;
      }
      if (boundary &&
          close + marker.length < text.length &&
          _isWord(text[close + marker.length])) {
        j = close + 1;
        continue;
      }
      final inner = text.substring(afterOpen, close);
      return _Emph(
        _inlineSpans(inner, _applyEmphasis(base, kind), ctx, recognizer: recognizer),
        close + marker.length,
      );
    }
  }
  return null;
}

TextStyle _applyEmphasis(TextStyle base, int kind) => switch (kind) {
      1 => base.copyWith(fontWeight: FontWeight.bold),
      2 => base.copyWith(fontStyle: FontStyle.italic),
      3 => base.copyWith(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
      4 => base.copyWith(
          decoration: TextDecoration.lineThrough,
          decorationColor: base.color,
        ),
      _ => base,
    };

bool _startsWith(String s, int i, String m) {
  if (i + m.length > s.length) return false;
  for (var k = 0; k < m.length; k++) {
    if (s[i + k] != m[k]) return false;
  }
  return true;
}

bool _isSpace(String ch) => ch == ' ' || ch == '\t' || ch == '\n';

bool _isWord(String ch) {
  final c = ch.codeUnitAt(0);
  return (c >= 48 && c <= 57) || // 0-9
      (c >= 65 && c <= 90) || // A-Z
      (c >= 97 && c <= 122) || // a-z
      c == 95; // _
}
