/// One citation: a page or video a grounded reply drew on. Attached to a
/// [ChatMessage] (see `chat_store.dart`) so the transcript stays verifiable —
/// the user can see and open exactly what the model was given, not just trust
/// that it searched.
class WebSource {
  const WebSource({required this.title, required this.url, this.snippet});

  final String title;
  final String url;

  /// The search-result snippet, or null for a YouTube transcript source
  /// (which has no snippet — its full text is the context, not an excerpt).
  final String? snippet;

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        if (snippet != null) 'snippet': snippet,
      };

  factory WebSource.fromJson(Map<String, dynamic> json) => WebSource(
        title: json['title'] as String? ?? '',
        url: json['url'] as String? ?? '',
        snippet: json['snippet'] as String?,
      );
}
