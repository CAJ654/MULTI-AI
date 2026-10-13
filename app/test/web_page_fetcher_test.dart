import 'package:flutter_test/flutter_test.dart';
import 'package:multi_ai/addons/chat/web_page_fetcher.dart';

void main() {
  group('articleTagSlice', () {
    test('returns the whole page when there is no <article> tag', () {
      const html = '<html><body><p>Hello</p></body></html>';
      expect(articleTagSlice(html), html);
    });

    test('isolates an <article> tag\'s contents from surrounding nav/chrome', () {
      const html = '<html><body>'
          '<nav>Home About Contact</nav>'
          '<article class="post"><h1>Title</h1><p>The real content.</p></article>'
          '<footer>Copyright</footer>'
          '</body></html>';
      final slice = articleTagSlice(html);
      expect(slice, contains('The real content.'));
      expect(slice, isNot(contains('Home About Contact')));
      expect(slice, isNot(contains('Copyright')));
    });

    test('handles an <article> tag with attributes', () {
      const html = '<div>nav</div><article id="main" data-x="1"><p>Body text</p></article>';
      final slice = articleTagSlice(html);
      expect(slice, contains('Body text'));
      expect(slice, isNot(contains('<div>nav</div>')));
    });

    test('falls back to everything from the tag onward if </article> is missing', () {
      const html = '<nav>menu</nav><article><p>Unclosed content</p>';
      final slice = articleTagSlice(html);
      expect(slice, contains('Unclosed content'));
      expect(slice, isNot(contains('menu')));
    });
  });
}
