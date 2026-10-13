import 'dart:convert' show utf8;

import 'package:file_picker/file_picker.dart';

import '../chat/web_page_fetcher.dart';
import 'memory_store.dart';

/// Thin ingestion wrappers the notebook UI calls — each turns one piece of
/// user input into a [MemoryStore] source. Kept separate from the store
/// itself so [MemoryStore] stays storage/retrieval logic only, with no
/// `file_picker`/HTTP dependency of its own.
class SourceIngestion {
  SourceIngestion(this._memory);

  final MemoryStore _memory;

  Future<RawItem> addPastedText(int notebookId, {required String title, required String text}) =>
      _memory.ingestPastedText(notebookId, title: title, text: text);

  /// Fetches [url] and adds it as a durable source — a much higher
  /// character cap than `WebPageFetcher`'s chat-grounding default (4000),
  /// and scoped to an `<article>` tag when the page has one, since this is
  /// meant to be kept and searched repeatedly, not skimmed once: a model
  /// asked to answer "using only the sources below" can read as having no
  /// information at all when the real content is a fifth of a chunk buried
  /// in site-navigation noise (see `narrowToArticleTag`'s doc comment).
  /// Null if the fetch failed (see `WebPageFetcher.fetchAndExtract`).
  Future<RawItem?> addUrl(int notebookId, Uri url) async {
    final text =
        await WebPageFetcher(maxChars: 20000, narrowToArticleTag: true).fetchAndExtract(url);
    if (text == null) return null;
    return _memory.ingestUrl(notebookId, url: url, title: url.toString(), text: text);
  }

  /// Opens a picker for a `.txt`/`.md` file and adds it as a source. Null if
  /// the user cancelled.
  Future<RawItem?> addTextFile(int notebookId) async {
    // file_picker 12: a static call returning the chosen files directly
    // ([] on cancel), and bytes come from PlatformFile.readAsBytes() rather
    // than a withData: true constructor flag — see attachment_input.dart's
    // pickImages() for the same pattern.
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['txt', 'md']);
    if (files.isEmpty) return null;
    final file = files.first;
    final bytes = await file.readAsBytes();
    final text = utf8.decode(bytes, allowMalformed: true);
    return _memory.ingestFile(notebookId, title: file.name, text: text);
  }
}
