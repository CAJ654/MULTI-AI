import 'package:flutter_test/flutter_test.dart';
import 'package:multi_ai/addons/notebook/chunker.dart';

void main() {
  group('chunkText', () {
    test('empty or whitespace-only text produces no chunks', () {
      expect(chunkText(''), isEmpty);
      expect(chunkText('   \n  '), isEmpty);
    });

    test('text shorter than the window is returned as one chunk', () {
      expect(chunkText('short text', size: 800), ['short text']);
    });

    test('long text is split into more than one chunk', () {
      final text = List.generate(2000, (i) => 'word$i').join(' ');
      final chunks = chunkText(text, size: 800, overlap: 150);
      expect(chunks.length, greaterThan(1));
      // Every chunk fits the window — paragraph-break preference can only
      // shrink a chunk, never grow it past size.
      for (final chunk in chunks) {
        expect(chunk.length, lessThanOrEqualTo(800));
      }
    });

    test('adjacent chunks overlap in content', () {
      final text = List.generate(2000, (i) => 'word$i').join(' ');
      final chunks = chunkText(text, size: 800, overlap: 150);
      expect(chunks.length, greaterThan(1));
      // The end of chunk N and the start of chunk N+1 should share some
      // words, since the window steps back by `overlap` each time.
      final tailWords = chunks[0].split(' ').reversed.take(5).toSet();
      final headWords = chunks[1].split(' ').take(20).toSet();
      expect(tailWords.intersection(headWords), isNotEmpty);
    });

    test('prefers a paragraph break over a hard mid-word cut', () {
      final first = 'a' * 700;
      final second = 'b' * 700;
      final text = '$first\n\n$second';
      final chunks = chunkText(text, size: 800, overlap: 150);
      // The break should land on the paragraph boundary (end of `first`),
      // not 800 characters in (which would split `second` mid-run of b's).
      expect(chunks.first, first);
    });

    test('never loops forever on pathological input', () {
      final text = 'x' * 50000;
      expect(() => chunkText(text, size: 100, overlap: 90), returnsNormally);
    });
  });
}
