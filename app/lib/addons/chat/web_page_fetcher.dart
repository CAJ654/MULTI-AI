import 'package:http/http.dart' as http;

import 'web_search_client.dart' show webAccessUserAgent;

/// The contents between the first `<article ...>` and its matching
/// `</article>`, or the whole page unchanged if it has none. A pure
/// string-in-string-out function (no network), so it's unit-testable
/// directly — see [WebPageFetcher.narrowToArticleTag]'s doc comment for why
/// this exists.
String articleTagSlice(String html) {
  final start = html.indexOf('<article');
  if (start == -1) return html;
  final end = html.indexOf('</article>', start);
  return end == -1 ? html.substring(start) : html.substring(start, end);
}

/// Fetches a page and reduces it to plain text worth putting in a prompt.
///
/// v1 does not check robots.txt before fetching — stated here as a known gap
/// rather than left silent, per this feature's own ethics/privacy plan. It's
/// mitigated in practice by how little this ever does: at most the top 2
/// search results, one request per distinct host, never in parallel — see
/// `web_grounding.dart`'s `gather`.
class WebPageFetcher {
  WebPageFetcher({this.maxChars = 4000, this.narrowToArticleTag = false});

  static const _maxBytes = 2 * 1024 * 1024; // 2MB

  /// Characters kept from the extracted text. Chat's default (4000) is sized
  /// to fit one grounding prompt; the notebook add-on's `SourceIngestion`
  /// passes a much higher cap, since a durable source is meant to be kept
  /// and searched, not just fit into a single prompt.
  final int maxChars;

  /// When true, restricts extraction to an `<article>` tag's contents if the
  /// page has one, before the usual tag-stripping — most semantic-HTML news
  /// and blog templates (WordPress, TownNews/BLOX, Substack, Medium, …) wrap
  /// the real body in one, and everything outside it (nav menus, share
  /// widgets, weather/footer boilerplate) is exactly the kind of noise that
  /// made a real notebook source mostly unusable: confirmed against a real
  /// page where it cut stored text from ~8500 chars (mostly site chrome, the
  /// article buried two-thirds in) to ~4800 (almost entirely the article).
  /// Chat's own grounding use (default `false`) skips this — a 2-result skim
  /// degrades gracefully either way, and this is extra work per fetch not
  /// worth paying there. `SourceIngestion` turns it on, since a notebook
  /// source is kept and searched repeatedly, so its noise compounds across
  /// every future question rather than being read once.
  final bool narrowToArticleTag;

  /// Fetches [url] and returns its extracted body text, or null if the
  /// request fails, times out, isn't HTML, or extracts to nothing — callers
  /// treat a null the same as "skip this one," not an error worth surfacing.
  Future<String?> fetchAndExtract(Uri url) async {
    try {
      final response = await http
          .get(url, headers: {'User-Agent': webAccessUserAgent})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      if (response.bodyBytes.length > _maxBytes) return null;
      final contentType = response.headers['content-type'] ?? '';
      if (contentType.isNotEmpty && !contentType.contains('html')) return null;
      final html = narrowToArticleTag ? articleTagSlice(response.body) : response.body;
      final text = _extractText(html);
      if (text.isEmpty) return null;
      return text.length > maxChars ? '${text.substring(0, maxChars)}…' : text;
    } catch (_) {
      return null;
    }
  }

  /// A small, dependency-free HTML→text reduction — strip script/style
  /// content, drop tags, unescape entities, collapse whitespace. Consistent
  /// with `markdown_text.dart`'s own choice not to pull in a parsing package
  /// for a narrow, LLM-facing text need (see that file's doc comment):
  /// anything this misses degrades to noisier text, never a crash.
  String _extractText(String html) {
    var s = html;
    s = s.replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ');
    s = s.replaceAll(RegExp(r'<(br|p|div|li|tr|h[1-6])[^>]*>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'<[^>]+>'), ' ');
    s = _unescapeEntities(s);
    s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
    s = s.replaceAll(RegExp(r'\n\s*\n+'), '\n\n');
    return s.trim();
  }

  String _unescapeEntities(String s) {
    const named = {
      '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'",
      '&apos;': "'", '&nbsp;': ' ', '&mdash;': '—', '&ndash;': '–',
      '&hellip;': '…', '&rsquo;': '’', '&lsquo;': '‘', '&rdquo;': '”', '&ldquo;': '“',
    };
    var out = s;
    for (final entry in named.entries) {
      out = out.replaceAll(entry.key, entry.value);
    }
    out = out.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (m) => String.fromCharCode(int.parse(m[1]!)),
    );
    out = out.replaceAllMapped(
      RegExp(r'&#[xX]([0-9a-fA-F]+);'),
      (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)),
    );
    return out;
  }
}
