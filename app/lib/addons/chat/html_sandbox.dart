import 'artifacts.dart';

/// Languages the workbench can render as a page. Anything else shows as source.
bool isPreviewable(Artifact artifact) {
  final lang = artifact.language.toLowerCase();
  return lang == 'html' || lang == 'htm' || lang == 'svg';
}

/// Turns an artifact into a self-contained page for the preview WebView.
///
/// Model output is untrusted, so the page is locked down before it loads:
///  * A Content-Security-Policy with `default-src 'none'` blocks every network
///    request (fetch, XHR, images, stylesheets, fonts from the web). Scripts and
///    styles are allowed inline only, so a page that is one self-contained file
///    still works.
///  * A `<base target="_blank">` sends link clicks to a new window, which the
///    WebView denies, so a click cannot replace the artifact with another page.
///
/// SVG is wrapped in a minimal HTML page so it gets the same policy.
String sandboxedHtml(Artifact artifact) {
  final source = artifact.code;
  final page = artifact.language.toLowerCase() == 'svg'
      ? '<!doctype html><html><head></head><body style="margin:0">$source</body></html>'
      : source;
  return _lockDown(page);
}

const _csp = "default-src 'none'; "
    "script-src 'unsafe-inline' 'unsafe-eval'; "
    "style-src 'unsafe-inline'; "
    "img-src data: blob:; "
    "font-src data:; "
    "media-src data: blob:; "
    "connect-src 'none'";

final _headOpen = RegExp(r'<head[^>]*>', caseSensitive: false);
final _doctype = RegExp(r'<!doctype[^>]*>', caseSensitive: false);

String _lockDown(String page) {
  final guard = '<meta http-equiv="Content-Security-Policy" content="$_csp">'
      '<base target="_blank">';
  // Insert after <head> when there is one, so the guard is in the head. Else
  // after the doctype, which keeps standards mode. Else at the very start.
  final head = _headOpen.firstMatch(page);
  if (head != null) {
    return page.replaceRange(head.end, head.end, guard);
  }
  final doctype = _doctype.firstMatch(page);
  if (doctype != null) {
    return page.replaceRange(doctype.end, doctype.end, guard);
  }
  return guard + page;
}
