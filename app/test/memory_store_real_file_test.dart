import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:multi_ai/addons/notebook/embedding_engine.dart';
import 'package:multi_ai/addons/notebook/memory_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart';

/// Fakes path_provider exactly like `chat_store_test.dart`'s
/// `_FakePathProviderPlatform` — real (temp) disk, no real platform behind
/// it.
class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.supportPath);
  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

class _FakeEmbeddingEngine extends EmbeddingEngine {
  @override
  Future<Float32List> embed(String text) async => Float32List.fromList([1.0, 0.0]);

  @override
  Future<void> dispose() async {}
}

/// Exercises `MemoryStore`'s real, file-backed `_openRealDatabase()` path —
/// the one every other `memory_store_test.dart` case bypasses via an
/// injected in-memory `Database`. This is the path `NotebookController`
/// actually takes in the shipped app (`MemoryStore()` with no injected db),
/// so a bug specific to opening/creating the on-disk sqlite3 file — rather
/// than the schema/CRUD logic itself — would only show up here.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('multi_ai_notebook_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('a real MemoryStore() opens a real sqlite3 file and a created notebook '
      'shows up in listNotebooks', () async {
    final store = MemoryStore(embeddingEngine: _FakeEmbeddingEngine());

    final notebook = await store.createNotebook('A');
    final notebooks = await store.listNotebooks();

    expect(notebooks.map((n) => n.id), contains(notebook.id));
    expect(notebooks.map((n) => n.title), contains('A'));

    // The file actually exists on disk, under the faked support directory —
    // not silently falling back to an in-memory/no-op store.
    final dbFile = File('${tempDir.path}${Platform.pathSeparator}notebook_memory.sqlite3');
    expect(await dbFile.exists(), isTrue);

    await store.dispose();
  });

  test('a second MemoryStore() against the same file sees the first one\'s notebook', () async {
    final first = MemoryStore(embeddingEngine: _FakeEmbeddingEngine());
    await first.createNotebook('Persisted');
    await first.dispose();

    final second = MemoryStore(embeddingEngine: _FakeEmbeddingEngine());
    final notebooks = await second.listNotebooks();
    expect(notebooks.map((n) => n.title), contains('Persisted'));
    await second.dispose();
  });

  test('an on-disk database from an older, incompatible schema is reset '
      'rather than crashing startup', () async {
    // Reproduces the real bug this test was added for: a user who ran an
    // older build has a real file on disk with the pre-`chats`-table shape
    // (`outputs.notebook_id` directly, no `chat_id`, no `user_version` ever
    // set — the exact state `CREATE TABLE IF NOT EXISTS` left behind, since
    // it never alters an existing table). Opening that file used to throw
    // `SqliteException: no such column: chat_id` out of the constructor's
    // unawaited `refreshNotebooks()`, which is why the notebook list never
    // populated — see memory_store.dart's `_schemaVersion` doc comment.
    final dbPath = '${tempDir.path}${Platform.pathSeparator}notebook_memory.sqlite3';
    final legacy = sqlite3.open(dbPath);
    legacy.execute('''
      CREATE TABLE notebooks (
        id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, created_at INTEGER NOT NULL
      );
    ''');
    legacy.execute('''
      CREATE TABLE outputs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        notebook_id INTEGER NOT NULL REFERENCES notebooks(id) ON DELETE CASCADE,
        author TEXT NOT NULL, text TEXT NOT NULL, created_at INTEGER NOT NULL
      );
    ''');
    legacy.execute(
      'INSERT INTO notebooks (title, created_at) VALUES (?, ?)',
      ['Old notebook', DateTime.now().millisecondsSinceEpoch],
    );
    legacy.dispose();

    final store = MemoryStore(embeddingEngine: _FakeEmbeddingEngine());
    // Must not throw — this is exactly what crashed refreshNotebooks() before
    // the fix.
    final notebooks = await store.listNotebooks();
    // The reset is a real reset: pre-existing data from the old schema does
    // not survive it (acceptable pre-release — see _schemaVersion's comment).
    expect(notebooks, isEmpty);

    // The store is fully usable afterward.
    await store.createNotebook('New notebook');
    expect((await store.listNotebooks()).map((n) => n.title), ['New notebook']);
    await store.dispose();
  });
}
