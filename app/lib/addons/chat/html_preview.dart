import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart';

/// Renders a sandboxed HTML page in a WebView. The page is already locked down
/// by `html_sandbox.dart`; this widget only hosts it.
///
/// Windows uses WebView2 (`webview_windows`), since `webview_flutter` has no
/// Windows implementation. Android, iOS, and macOS use `webview_flutter`. The
/// web build and Linux have no WebView here, so they get a short note.
class HtmlPreview extends StatelessWidget {
  const HtmlPreview({super.key, required this.html});

  /// A complete page, already passed through `sandboxedHtml`.
  final String html;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return _unavailable('The preview needs the desktop or mobile app.');
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        return _WindowsPreview(html: html);
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return _MobilePreview(html: html);
      default:
        return _unavailable('The preview is not available on this platform.');
    }
  }

  static Widget _unavailable(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(message,
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
        ),
      );
}

/// A white backdrop: artifact pages are written for a light background, and
/// the app's dark theme would otherwise show their default text as invisible.
class _WindowsPreview extends StatefulWidget {
  const _WindowsPreview({required this.html});

  final String html;

  @override
  State<_WindowsPreview> createState() => _WindowsPreviewState();
}

class _WindowsPreviewState extends State<_WindowsPreview> {
  final _controller = WebviewController();
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _controller.initialize();
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await _controller.setBackgroundColor(Colors.white);
      await _controller.loadStringContent(widget.html);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      // Usually means the WebView2 runtime is missing.
      if (mounted) {
        setState(() => _error = 'The preview could not start. Is the WebView2 '
            'runtime installed? ($e)');
      }
    }
  }

  @override
  void didUpdateWidget(_WindowsPreview old) {
    super.didUpdateWidget(old);
    if (_ready && old.html != widget.html) {
      _controller.loadStringContent(widget.html);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return HtmlPreview._unavailable(_error!);
    }
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    return ColoredBox(
      color: Colors.white,
      child: Webview(_controller),
    );
  }
}

class _MobilePreview extends StatefulWidget {
  const _MobilePreview({required this.html});

  final String html;

  @override
  State<_MobilePreview> createState() => _MobilePreviewState();
}

class _MobilePreviewState extends State<_MobilePreview> {
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(Colors.white)
    ..setNavigationDelegate(NavigationDelegate(
      // The first load is an about:/data: URL. Anything after that is a click
      // inside the page, which would leave the artifact, so it is blocked.
      onNavigationRequest: (request) {
        final url = request.url;
        if (url.startsWith('about:') || url.startsWith('data:')) {
          return NavigationDecision.navigate;
        }
        return NavigationDecision.prevent;
      },
    ))
    ..loadHtmlString(widget.html);

  @override
  void didUpdateWidget(_MobilePreview old) {
    super.didUpdateWidget(old);
    if (old.html != widget.html) _controller.loadHtmlString(widget.html);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: WebViewWidget(controller: _controller),
    );
  }
}
