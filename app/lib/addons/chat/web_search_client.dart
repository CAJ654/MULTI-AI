import 'dart:convert';

import 'package:http/http.dart' as http;

import '../components/component_manager.dart';
import 'web_source.dart';

/// A descriptive User-Agent, never a spoofed browser string — every request
/// this feature makes (this file and `web_page_fetcher.dart`) identifies
/// itself honestly, on the theory that a site should be able to tell this
/// app apart from a real visitor if it wants to.
const webAccessUserAgent = 'Multi-AI/1.0 (local SearXNG search; +https://github.com/)';

/// Queries the bundled local SearXNG instance's JSON API. See
/// `addons/components/searxng_supervisor.dart` for the process this talks to
/// and `assets/components/searxng_settings.yml.tmpl` for why its JSON format
/// is enabled at all (off by default on public instances, fine for one only
/// this app can reach).
class SearxngSearchClient {
  SearxngSearchClient(this._components);

  final ComponentManager _components;

  static const _port = 8891; // must match componentCatalog's searxng entry

  /// Runs [query] against SearXNG and returns up to [limit] results. Starts
  /// the SearXNG process first if it isn't already running — see
  /// `ComponentManager.ensureRunning`'s doc comment on why that happens here,
  /// lazily, rather than when the component is installed or the app starts.
  ///
  /// Throws on any failure (SearXNG not installed, failed to start, request
  /// error) — callers (see `web_grounding.dart`) are expected to catch this
  /// and fall back to answering without search results, not to propagate it
  /// as a failed chat turn.
  Future<List<WebSource>> search(String query, {int limit = 5}) async {
    await _components.ensureRunning('searxng');
    final uri = Uri.parse('http://127.0.0.1:$_port/search').replace(queryParameters: {
      'q': query,
      'format': 'json',
    });
    final response = await http
        .get(uri, headers: {'User-Agent': webAccessUserAgent})
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Search failed (HTTP ${response.statusCode}).');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = (data['results'] as List<dynamic>? ?? []);
    return [
      for (final r in results.take(limit))
        WebSource(
          title: (r as Map<String, dynamic>)['title'] as String? ?? '(untitled)',
          url: r['url'] as String? ?? '',
          snippet: r['content'] as String?,
        ),
    ].where((s) => s.url.isNotEmpty).toList();
  }
}
