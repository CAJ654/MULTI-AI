import 'package:flutter_test/flutter_test.dart';
import 'package:multi_ai/addons/chat/artifacts.dart';

void main() {
  group('extractArtifacts', () {
    test('returns nothing for a reply with no code', () {
      expect(extractArtifacts('Just **prose**, no code.'), isEmpty);
    });

    test('pulls each fenced block with its language, in order', () {
      const reply = 'Here:\n```html\n<p>hi</p>\n```\nand\n```dart\nprint(1);\n```';
      final found = extractArtifacts(reply);
      expect(found.length, 2);
      expect(found[0].language, 'html');
      expect(found[0].code, '<p>hi</p>');
      expect(found[0].label, 'html 1');
      expect(found[1].language, 'dart');
      expect(found[1].index, 2);
    });

    test('keeps the block verbatim, with inner blank lines', () {
      const reply = '```\nline one\n\nline three\n```';
      final found = extractArtifacts(reply);
      expect(found.single.code, 'line one\n\nline three');
      expect(found.single.label, 'Code 1');
    });

    test('a closing fence must match the opener, so ~~~ does not end a ``` block', () {
      const reply = '```\na\n~~~\nb\n```';
      expect(extractArtifacts(reply).single.code, 'a\n~~~\nb');
    });

    test('an unclosed block runs to the end of the text', () {
      const reply = '```svg\n<svg/>';
      expect(extractArtifacts(reply).single.code, '<svg/>');
    });

    test('skips empty blocks', () {
      const reply = '```\n\n```\n```py\nx = 1\n```';
      final found = extractArtifacts(reply);
      expect(found.single.language, 'py');
      expect(found.single.index, 1);
    });
  });

  group('WorkbenchController', () {
    test('opens and closes, notifying listeners on each change', () {
      final workbench = WorkbenchController();
      var notified = 0;
      workbench.addListener(() => notified++);
      const a = Artifact(index: 1, language: 'html', code: '<p/>');

      workbench.open(a);
      expect(workbench.artifact, a);
      workbench.open(a); // same artifact: no second notification
      workbench.close();
      expect(workbench.artifact, isNull);
      workbench.close(); // already closed: no notification
      expect(notified, 2);
      workbench.dispose();
    });
  });
}
