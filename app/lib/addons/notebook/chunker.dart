/// Splits [text] into overlapping chunks for embedding/retrieval.
///
/// Fixed-size character chunking with overlap, preferring to break on a
/// paragraph boundary near the end of each window rather than mid-sentence —
/// no sentence-boundary library, consistent with `web_page_fetcher.dart`'s
/// dependency-free approach to text processing. A pure function, no I/O, so
/// it's unit-testable with no setup.
///
/// Defaults (800 chars / 150 overlap) are a starting point, not tuned —
/// worth revisiting after real notebooks have gone through it.
List<String> chunkText(String text, {int size = 800, int overlap = 150}) {
  assert(size > 0);
  assert(overlap >= 0 && overlap < size);
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const [];
  if (trimmed.length <= size) return [trimmed];

  final chunks = <String>[];
  var start = 0;
  while (start < trimmed.length) {
    var end = start + size;
    if (end >= trimmed.length) {
      end = trimmed.length;
    } else {
      // Prefer a paragraph break within the last quarter of this window.
      final minBreak = start + size - (size ~/ 4);
      final breakAt = trimmed.lastIndexOf('\n\n', end);
      if (breakAt > minBreak) end = breakAt;
    }
    final chunk = trimmed.substring(start, end).trim();
    if (chunk.isNotEmpty) chunks.add(chunk);
    if (end >= trimmed.length) break;
    // Guarantee forward progress even if overlap would otherwise stall the
    // window at a short chunk (e.g. right after a very early paragraph break).
    final next = end - overlap;
    start = next > start ? next : end;
  }
  return chunks;
}
