import 'package:flutter_test/flutter_test.dart';
import 'package:multi_ai/addons/chat/artifacts.dart';
import 'package:multi_ai/addons/chat/html_sandbox.dart';

Artifact _block(String language, String code) =>
    Artifact(index: 1, language: language, code: code);

void main() {
  group('isPreviewable', () {
    test('html, htm, and svg render; other languages stay as source', () {
      expect(isPreviewable(_block('html', '')), isTrue);
      expect(isPreviewable(_block('HTM', '')), isTrue);
      expect(isPreviewable(_block('svg', '')), isTrue);
      expect(isPreviewable(_block('dart', '')), isFalse);
      expect(isPreviewable(_block('', '')), isFalse);
    });
  });

  group('sandboxedHtml', () {
    const csp = "Content-Security-Policy";

    test('a page with a head gets the guard inside the head', () {
      final out = sandboxedHtml(_block('html', '<html><head><title>x</title></head><body>hi</body></html>'));
      expect(out, contains(csp));
      expect(out.indexOf(csp), greaterThan(out.indexOf('<head>')));
      expect(out.indexOf(csp), lessThan(out.indexOf('<title>')));
    });

    test('the policy blocks the network by default', () {
      final out = sandboxedHtml(_block('html', '<p>hi</p>'));
      expect(out, contains("default-src 'none'"));
      expect(out, contains("connect-src 'none'"));
      // No remote origin is allowed anywhere in the policy.
      expect(out, isNot(contains('https://')));
      expect(out, isNot(contains('http://')));
    });

    test('a doctype keeps standards mode: the guard comes after it', () {
      final out = sandboxedHtml(_block('html', '<!DOCTYPE html>\n<p>hi</p>'));
      expect(out.indexOf('<!DOCTYPE html>'), 0);
      expect(out.indexOf(csp), greaterThan(0));
    });

    test('a bare fragment gets the guard at the very start', () {
      final out = sandboxedHtml(_block('html', '<p>hi</p>'));
      expect(out, startsWith('<meta http-equiv="$csp"'));
      expect(out, endsWith('<p>hi</p>'));
    });

    test('links open in a new window, which the preview denies', () {
      expect(sandboxedHtml(_block('html', '<p>x</p>')), contains('<base target="_blank">'));
    });

    test('SVG is wrapped in a page with the same guard', () {
      final out = sandboxedHtml(_block('svg', '<svg><circle r="5"/></svg>'));
      expect(out, contains(csp));
      expect(out, contains('<svg><circle r="5"/></svg>'));
      expect(out, contains('<body style="margin:0">'));
    });
  });
}
