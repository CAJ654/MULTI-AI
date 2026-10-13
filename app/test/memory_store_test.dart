import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:multi_ai/addons/notebook/embedding_engine.dart';
import 'package:multi_ai/addons/notebook/memory_store.dart';
import 'package:sqlite3/sqlite3.dart';

/// A fake embedder so these tests never touch the real GGUF/llama.cpp —
/// mirrors how `ModelPool` tests inject a fake engine/API client. Any text
/// containing "cat" lands near `[1, 0]`; anything else near `[0, 1]` — two
/// well-separated "topics", just enough for ranking assertions to mean
/// something without a real model.
class _FakeEmbeddingEngine extends EmbeddingEngine {
  @override
  Future<Float32List> embed(String text) async {
    final catty = text.toLowerCase().contains('cat');
    return Float32List.fromList(catty ? [1.0, 0.01] : [0.01, 1.0]);
  }

  @override
  Future<void> dispose() async {}
}

MemoryStore _newStore() => MemoryStore(
      embeddingEngine: _FakeEmbeddingEngine(),
      database: sqlite3.openInMemory(),
    );

/// Lets the fire-and-forget embed kicked off by an ingest call finish before
/// the test reads the row back — see `MemoryStore._ingest`'s doc comment.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('notebooks', () {
    test('create, list, delete', () async {
      final store = _newStore();
      final a = await store.createNotebook('A');
      final b = await store.createNotebook('B');
      expect((await store.listNotebooks()).map((n) => n.title), containsAll(['A', 'B']));

      await store.deleteNotebook(a.id);
      final remaining = await store.listNotebooks();
      expect(remaining.map((n) => n.id), [b.id]);
    });

    test('deleting a notebook cascades to its sources, chats and outputs', () async {
      final store = _newStore();
      final notebook = await store.createNotebook('Cascade');
      await store.ingestPastedText(notebook.id, title: 'note', text: 'a cat sat on a mat');
      final chat = await store.createChat(notebook.id, 'Chat 1');
      await store.addOutput(chat.id, author: 'user', text: 'hi');
      await _settle();

      await store.deleteNotebook(notebook.id);
      expect(await store.listSources(notebook.id), isEmpty);
      expect(await store.listChats(notebook.id), isEmpty);
      expect(await store.listOutputs(chat.id), isEmpty);
    });
  });

  group('chats', () {
    test('create, list, delete', () async {
      final store = _newStore();
      final notebook = await store.createNotebook('N');
      final a = await store.createChat(notebook.id, 'A');
      final b = await store.createChat(notebook.id, 'B');
      expect((await store.listChats(notebook.id)).map((c) => c.title), ['A', 'B']);

      await store.deleteChat(a.id);
      final remaining = await store.listChats(notebook.id);
      expect(remaining.map((c) => c.id), [b.id]);
    });

    test('a notebook can hold several chats, each with its own outputs', () async {
      final store = _newStore();
      final notebook = await store.createNotebook('N');
      final a = await store.createChat(notebook.id, 'A');
      final b = await store.createChat(notebook.id, 'B');
      await store.addOutput(a.id, author: 'user', text: 'in A');
      await store.addOutput(b.id, author: 'user', text: 'in B');

      expect((await store.listOutputs(a.id)).map((o) => o.text), ['in A']);
      expect((await store.listOutputs(b.id)).map((o) => o.text), ['in B']);
    });

    test('deleting a chat cascades to its outputs but leaves the notebook alone', () async {
      final store = _newStore();
      final notebook = await store.createNotebook('N');
      final chat = await store.createChat(notebook.id, 'A');
      await store.addOutput(chat.id, author: 'user', text: 'hi');

      await store.deleteChat(chat.id);
      expect(await store.listOutputs(chat.id), isEmpty);
      expect(await store.listNotebooks(), isNotEmpty);
    });
  });

  group('ingestion', () {
    test('ingesting a source chunks it, embeds it, and marks it done', () async {
      final store = _newStore();
      final notebook = await store.createNotebook('N');
      final item = await store.ingestPastedText(notebook.id, title: 'cats', text: 'a cat sat on a mat');
      await _settle();

      final sources = await store.listSources(notebook.id);
      expect(sources.single.id, item.id);
      expect(sources.single.embedStatus, 'done');
    });
  });

  group('search', () {
    test('ranks the more similar source first', () async {
      final store = _newStore();
      final notebook = await store.createNotebook('N');
      await store.ingestPastedText(notebook.id, title: 'cats', text: 'a cat sat on a mat');
      await store.ingestPastedText(notebook.id, title: 'dogs', text: 'a dog ran in the park');
      await _settle();

      final results = await store.search(notebook.id, 'tell me about my cat');
      expect(results, isNotEmpty);
      expect(results.first.sourceTitle, 'cats');
    });

    test('is scoped to one notebook', () async {
      final store = _newStore();
      final a = await store.createNotebook('A');
      final b = await store.createNotebook('B');
      await store.ingestPastedText(a.id, title: 'a-cats', text: 'a cat sat on a mat');
      await store.ingestPastedText(b.id, title: 'b-cats', text: 'a cat sat on a mat');
      await _settle();

      final results = await store.search(a.id, 'cat');
      expect(results, isNotEmpty);
      expect(results.every((r) => r.sourceTitle == 'a-cats'), isTrue);
    });
  });

  group('outputs', () {
    test('addOutput then listOutputs round-trips, oldest first', () async {
      final store = _newStore();
      final notebook = await store.createNotebook('N');
      final chat = await store.createChat(notebook.id, 'Chat 1');
      await store.addOutput(chat.id, author: 'user', text: 'question');
      await store.addOutput(chat.id, author: 'ai', text: 'answer');

      final outputs = await store.listOutputs(chat.id);
      expect(outputs.map((o) => o.text), ['question', 'answer']);
    });
  });
}
