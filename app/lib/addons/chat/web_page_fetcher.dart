import 'package:http/http.dart' as http;

import 'web_search_client.dart' show webAccessUserAgent;

/// Fetches a page and reduces it to plain text worth putting in a prompt.
///
/// v1 does not check robots.txt before fetching — stated here as a known gap
/// rather than left silent, per this feature's own ethics/privacy plan. It's
/// mitigated in practice by how little this ever does: at most the top 2
/// search results, one request per distinct host, never in parallel — see
/// `web_grounding.dart`'s `gather`.
class WebPageFetcher {
  static const _maxBytes = 2 * 1024 * 1024; // 2MB
  static const _maxChars = 4000;

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
      final text = _extractText(response.body);
      if (text.isEmpty) return null;
      return text.length > _maxChars ? '${text.substring(0, _maxChars)}…' : text;
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
