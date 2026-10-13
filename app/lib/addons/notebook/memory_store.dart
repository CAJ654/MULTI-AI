import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart' show DefaultModelDownloadManager;
import 'package:path_provider/path_provider.dart' show getApplicationSupportDirectory;
import 'package:sqlite3/sqlite3.dart';

import '../../model_pool.dart' show androidModelCacheDirectory, isAndroidPlatform;
import 'chunker.dart';
import 'embedding_engine.dart';

/// Where a [RawItem] came from.
enum SourceKind {
  paste('paste'),
  url('url'),
  file('file');

  const SourceKind(this.wireName);
  final String wireName;

  static SourceKind fromWireName(String s) =>
      SourceKind.values.firstWhere((k) => k.wireName == s, orElse: () => SourceKind.paste);
}

class Notebook {
  const Notebook({required this.id, required this.title, required this.createdAt});

  final int id;
  final String title;
  final DateTime createdAt;
}

/// One conversation thread within a notebook — the `chats` table. A notebook
/// can hold several (e.g. "Summary", "Counterarguments"), each with its own
/// `outputs`, the same way the Chat tab's sidebar holds several
/// `ChatSession`s (`chat_addon.dart`'s `ChatSessionList`) rather than one
/// running transcript.
class Chat {
  const Chat({required this.id, required this.notebookId, required this.title, required this.createdAt});

  final int id;
  final int notebookId;
  final String title;
  final DateTime createdAt;
}

/// A source added to a notebook — the `raw_items` table. `fullText` is kept
/// in full (unlike `WebPageFetcher`'s chat-grounding truncation) since this
/// is meant to be kept and searched, not fit into one prompt.
class RawItem {
  const RawItem({
    required this.id,
    required this.notebookId,
    required this.kind,
    required this.title,
    required this.sourceUrl,
    required this.fullText,
    required this.addedAt,
    required this.embedStatus,
  });

  final int id;
  final int notebookId;
  final SourceKind kind;
  final String title;
  final String? sourceUrl;
  final String fullText;
  final DateTime addedAt;

  /// 'pending' | 'embedding' | 'done' | 'error'.
  final String embedStatus;
}

/// A note tied to a chat thread — the `outputs` table. `author` is `'user'`
/// or `'ai'`. `notebookId` is denormalized from `chatId`'s own notebook,
/// mirroring `memory_index`'s `notebook_id` column, for a per-notebook scan
/// without a join.
class Output {
  const Output({
    required this.id,
    required this.chatId,
    required this.notebookId,
    required this.author,
    required this.text,
    required this.createdAt,
  });

  final int id;
  final int chatId;
  final int notebookId;
  final String author;
  final String text;
  final DateTime createdAt;
}

/// One retrieved chunk, ranked by [score] (cosine similarity, higher is
/// closer).
class ScoredChunk {
  const ScoredChunk({
    required this.rawItemId,
    required this.sourceTitle,
    required this.text,
    required this.score,
  });

  final int rawItemId;
  final String sourceTitle;
  final String text;
  final double score;
}

/// The notebook/memory capability (`HostCapability.memory`): SQLite-backed
/// storage for notebooks, their sources (`raw_items`), chunked embeddings
/// (`memory_index`), chat threads (`chats`) and notes (`outputs`, one per
/// chat) — table names (other than `chats`, which the TODO's schema doesn't
/// name) match the TODO's planned memory-layer schema so a fuller Agentic OS
/// add-on can extend this later rather than migrating off a second,
/// incompatible one.
///
/// No server process and no vector-search extension: retrieval is
/// brute-force cosine similarity in Dart over `memory_index`, which is
/// plenty fast at the tens-to-low-hundreds-of-chunks scale one notebook
/// holds. Unlike `ComponentManager`/`ComponentRuntime` (Windows-bundled-
/// Python-only — see `components/component_runtime.dart`), this needs
/// nothing platform-specific: SQLite is a pure-Dart/FFI library and
/// embeddings run through `llamadart`'s in-process FFI engine, both equally
/// at home on Android — which is why `registry.dart` constructs this
/// unconditionally, with no availability gate.
class MemoryStore {
  MemoryStore({EmbeddingEngine? embeddingEngine, Database? database})
      : _embedding = embeddingEngine ?? EmbeddingEngine(),
        _injectedDb = database;

  final EmbeddingEngine _embedding;

  /// Set by tests to an in-memory database, bypassing [_openRealDatabase]
  /// entirely — see `memory_store_test.dart`.
  final Database? _injectedDb;

  Database? _db;

  Future<Database> _ensureOpen() async {
    final existing = _db;
    if (existing != null) return existing;
    final injected = _injectedDb;
    if (injected != null) {
      _createSchema(injected);
      return _db = injected;
    }
    return _db = await _openRealDatabase();
  }

  Future<Database> _openRealDatabase() async {
    if (isAndroidPlatform) {
      // Same durable app-support cache directory chat models already use on
      // Android (model_pool.dart) — one download location, not two.
      _embedding.downloadManager ??= DefaultModelDownloadManager.appPrivate(
        cacheDirectory: await androidModelCacheDirectory(),
      );
    }
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final db = sqlite3.open('${dir.path}${Platform.pathSeparator}notebook_memory.sqlite3');
    _createSchema(db);
    return db;
  }

  /// Bumped whenever a table's columns change shape (not just a new table).
  /// Pre-release: there is no shipped data to migrate yet, so a version
  /// mismatch means dropping and recreating rather than writing a one-off
  /// `ALTER TABLE` migration for a schema nobody outside development has
  /// seen — see [_createSchema]. Revisit once this ships.
  ///
  /// 1: `outputs` keyed by `notebook_id` directly. 2: `outputs` keyed by the
  /// new `chats` table's `chat_id` instead (`CREATE TABLE IF NOT EXISTS`
  /// left a `1`-shaped `outputs` table on disk untouched, so the `chat_id`
  /// index creation below failed outright against it — this pragma is what
  /// catches that case the next time the app starts).
  static const int _schemaVersion = 2;

  void _createSchema(Database db) {
    db.execute('PRAGMA foreign_keys = ON;');
    final onDiskVersion = db.select('PRAGMA user_version;').first['user_version'] as int;
    if (onDiskVersion != _schemaVersion) {
      // DROP TABLE IF EXISTS is a no-op on a brand-new database (nothing to
      // drop), so this runs unconditionally on any mismatch rather than
      // trying to distinguish "fresh" from "pre-versioning schema" — both
      // read as user_version 0, since _createSchema never set the pragma
      // before this check existed. See _schemaVersion's doc comment.
      for (final table in ['outputs', 'chats', 'memory_index', 'raw_items', 'notebooks']) {
        db.execute('DROP TABLE IF EXISTS $table;');
      }
    }
    db.execute('''
      CREATE TABLE IF NOT EXISTS notebooks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS raw_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        notebook_id INTEGER NOT NULL REFERENCES notebooks(id) ON DELETE CASCADE,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        source_url TEXT,
        full_text TEXT NOT NULL,
        added_at INTEGER NOT NULL,
        embed_status TEXT NOT NULL DEFAULT 'pending'
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS memory_index (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        raw_item_id INTEGER NOT NULL REFERENCES raw_items(id) ON DELETE CASCADE,
        notebook_id INTEGER NOT NULL,
        chunk_index INTEGER NOT NULL,
        text TEXT NOT NULL,
        embedding BLOB NOT NULL,
        embedding_dim INTEGER NOT NULL
      );
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_memory_index_notebook ON memory_index(notebook_id);');
    db.execute('''
      CREATE TABLE IF NOT EXISTS chats (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        notebook_id INTEGER NOT NULL REFERENCES notebooks(id) ON DELETE CASCADE,
        title TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS outputs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chat_id INTEGER NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
        notebook_id INTEGER NOT NULL,
        author TEXT NOT NULL,
        text TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_outputs_chat ON outputs(chat_id);');
    db.execute('PRAGMA user_version = $_schemaVersion;');
  }

  // --------------------------------------------------------------- notebooks

  Future<List<Notebook>> listNotebooks() async {
    final db = await _ensureOpen();
    final rows = db.select('SELECT id, title, created_at FROM notebooks ORDER BY created_at DESC');
    return [for (final r in rows) _notebookFromRow(r)];
  }

  Future<Notebook> createNotebook(String title) async {
    final db = await _ensureOpen();
    final now = DateTime.now();
    db.execute(
      'INSERT INTO notebooks (title, created_at) VALUES (?, ?)',
      [title, now.millisecondsSinceEpoch],
    );
    return Notebook(id: db.lastInsertRowId, title: title, createdAt: now);
  }

  /// Deletes [id] and (via `ON DELETE CASCADE`) every source, chunk, chat and
  /// note under it.
  Future<void> deleteNotebook(int id) async {
    final db = await _ensureOpen();
    db.execute('DELETE FROM notebooks WHERE id = ?', [id]);
  }

  // -------------------------------------------------------------------- chats

  Future<List<Chat>> listChats(int notebookId) async {
    final db = await _ensureOpen();
    final rows = db.select(
      'SELECT id, notebook_id, title, created_at FROM chats WHERE notebook_id = ? ORDER BY created_at ASC',
      [notebookId],
    );
    return [for (final r in rows) _chatFromRow(r)];
  }

  Future<Chat> createChat(int notebookId, String title) async {
    final db = await _ensureOpen();
    final now = DateTime.now();
    db.execute(
      'INSERT INTO chats (notebook_id, title, created_at) VALUES (?, ?, ?)',
      [notebookId, title, now.millisecondsSinceEpoch],
    );
    return Chat(id: db.lastInsertRowId, notebookId: notebookId, title: title, createdAt: now);
  }

  /// Deletes [id] and (via `ON DELETE CASCADE`) every note under it.
  Future<void> deleteChat(int id) async {
    final db = await _ensureOpen();
    db.execute('DELETE FROM chats WHERE id = ?', [id]);
  }

  // ----------------------------------------------------------------- sources

  Future<List<RawItem>> listSources(int notebookId) async {
    final db = await _ensureOpen();
    final rows = db.select(
      'SELECT * FROM raw_items WHERE notebook_id = ? ORDER BY added_at DESC',
      [notebookId],
    );
    return [for (final r in rows) _rawItemFromRow(r)];
  }

  Future<RawItem> ingestPastedText(int notebookId, {required String title, required String text}) =>
      _ingest(notebookId, kind: SourceKind.paste, title: title, text: text, sourceUrl: null);

  Future<RawItem> ingestUrl(
    int notebookId, {
    required Uri url,
    required String title,
    required String text,
  }) =>
      _ingest(notebookId, kind: SourceKind.url, title: title, text: text, sourceUrl: url.toString());

  Future<RawItem> ingestFile(int notebookId, {required String title, required String text}) =>
      _ingest(notebookId, kind: SourceKind.file, title: title, text: text, sourceUrl: null);

  Future<RawItem> _ingest(
    int notebookId, {
    required SourceKind kind,
    required String title,
    required String text,
    required String? sourceUrl,
  }) async {
    final db = await _ensureOpen();
    final now = DateTime.now();
    db.execute(
      'INSERT INTO raw_items (notebook_id, kind, title, source_url, full_text, added_at, embed_status) '
      "VALUES (?, ?, ?, ?, ?, ?, 'pending')",
      [notebookId, kind.wireName, title, sourceUrl, text, now.millisecondsSinceEpoch],
    );
    final item = RawItem(
      id: db.lastInsertRowId,
      notebookId: notebookId,
      kind: kind,
      title: title,
      sourceUrl: sourceUrl,
      fullText: text,
      addedAt: now,
      embedStatus: 'pending',
    );
    // Fire-and-forget: ingestion returns as soon as the source is saved, and
    // embedding (which can take a few seconds for a long source) proceeds in
    // the background. `embedStatus` is how a caller observes completion.
    unawaited(_embedItem(db, item));
    return item;
  }

  Future<void> _embedItem(Database db, RawItem item) async {
    try {
      db.execute("UPDATE raw_items SET embed_status = 'embedding' WHERE id = ?", [item.id]);
      final chunks = chunkText(item.fullText);
      for (var i = 0; i < chunks.length; i++) {
        final vector = await _embedding.embed(chunks[i]);
        db.execute(
          'INSERT INTO memory_index (raw_item_id, notebook_id, chunk_index, text, embedding, embedding_dim) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          [item.id, item.notebookId, i, chunks[i], vector.buffer.asUint8List(), vector.length],
        );
      }
      db.execute("UPDATE raw_items SET embed_status = 'done' WHERE id = ?", [item.id]);
    } catch (_) {
      // Surfaced to the UI via embedStatus, not rethrown — ingestion already
      // returned to its caller by the time this runs.
      db.execute("UPDATE raw_items SET embed_status = 'error' WHERE id = ?", [item.id]);
    }
  }

  // -------------------------------------------------------------- retrieval

  /// The [topK] chunks in [notebookId] most similar to [query], ranked
  /// highest-first. Rows left over from a since-swapped embedding model
  /// (different [RawItem]-independent `embedding_dim`) are skipped rather
  /// than compared against a mismatched query vector.
  Future<List<ScoredChunk>> search(int notebookId, String query, {int topK = 6}) async {
    final db = await _ensureOpen();
    final queryVector = await _embedding.embed(query);
    final rows = db.select(
      'SELECT m.text AS chunk_text, m.embedding AS embedding, m.embedding_dim AS embedding_dim, '
      'r.id AS raw_item_id, r.title AS source_title '
      'FROM memory_index m JOIN raw_items r ON r.id = m.raw_item_id '
      'WHERE m.notebook_id = ?',
      [notebookId],
    );
    final scored = <ScoredChunk>[];
    for (final row in rows) {
      final dim = row['embedding_dim'] as int;
      if (dim != queryVector.length) continue;
      final vector = _decodeVector(row['embedding'] as Uint8List, dim);
      scored.add(ScoredChunk(
        rawItemId: row['raw_item_id'] as int,
        sourceTitle: row['source_title'] as String,
        text: row['chunk_text'] as String,
        score: _cosine(queryVector, vector),
      ));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(topK).toList();
  }

  /// Decodes bytes stored by [ingestPastedText] et al. back into floats via
  /// [ByteData], rather than a typed-list view — a BLOB column's backing
  /// buffer offset isn't guaranteed 4-byte aligned, which a `Float32List`
  /// view would require and a view-based decode would otherwise throw on.
  Float32List _decodeVector(Uint8List bytes, int dim) {
    final byteData = ByteData.sublistView(bytes);
    final vector = Float32List(dim);
    for (var i = 0; i < dim; i++) {
      vector[i] = byteData.getFloat32(i * 4, Endian.host);
    }
    return vector;
  }

  double _cosine(Float32List a, Float32List b) {
    var dot = 0.0, normA = 0.0, normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0;
    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }

  // --------------------------------------------------------------- outputs

  Future<Output> addOutput(int chatId, {required String author, required String text}) async {
    final db = await _ensureOpen();
    final notebookId = _notebookIdForChat(db, chatId);
    final now = DateTime.now();
    db.execute(
      'INSERT INTO outputs (chat_id, notebook_id, author, text, created_at) VALUES (?, ?, ?, ?, ?)',
      [chatId, notebookId, author, text, now.millisecondsSinceEpoch],
    );
    return Output(
      id: db.lastInsertRowId,
      chatId: chatId,
      notebookId: notebookId,
      author: author,
      text: text,
      createdAt: now,
    );
  }

  /// Oldest first — a chat transcript reads top-to-bottom, unlike
  /// [listNotebooks]/[listSources]' most-recent-first ordering.
  Future<List<Output>> listOutputs(int chatId) async {
    final db = await _ensureOpen();
    final rows = db.select(
      'SELECT * FROM outputs WHERE chat_id = ? ORDER BY created_at ASC',
      [chatId],
    );
    return [for (final r in rows) _outputFromRow(r)];
  }

  int _notebookIdForChat(Database db, int chatId) {
    final rows = db.select('SELECT notebook_id FROM chats WHERE id = ?', [chatId]);
    if (rows.isEmpty) {
      throw ArgumentError.value(chatId, 'chatId', 'No chat with this id');
    }
    return rows.first['notebook_id'] as int;
  }

  // ----------------------------------------------------------------- rows

  Notebook _notebookFromRow(Row r) => Notebook(
        id: r['id'] as int,
        title: r['title'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
      );

  RawItem _rawItemFromRow(Row r) => RawItem(
        id: r['id'] as int,
        notebookId: r['notebook_id'] as int,
        kind: SourceKind.fromWireName(r['kind'] as String),
        title: r['title'] as String,
        sourceUrl: r['source_url'] as String?,
        fullText: r['full_text'] as String,
        addedAt: DateTime.fromMillisecondsSinceEpoch(r['added_at'] as int),
        embedStatus: r['embed_status'] as String,
      );

  Chat _chatFromRow(Row r) => Chat(
        id: r['id'] as int,
        notebookId: r['notebook_id'] as int,
        title: r['title'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
      );

  Output _outputFromRow(Row r) => Output(
        id: r['id'] as int,
        chatId: r['chat_id'] as int,
        notebookId: r['notebook_id'] as int,
        author: r['author'] as String,
        text: r['text'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
      );

  Future<void> dispose() async {
    await _embedding.dispose();
    _db?.dispose();
    _db = null;
  }
}
