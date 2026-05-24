import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import 'package:nova_x/core/database/local_db.dart';

class BrowserView extends StatefulWidget {
  final String initialQuery;
  const BrowserView({super.key, required this.initialQuery});

  @override
  State<BrowserView> createState() => _BrowserViewState();
}

class _BrowserViewState extends State<BrowserView> {
  InAppWebViewController? _webViewController;
  double _progress = 0;
  String _currentUrl = '';
  String _pageTitle  = 'Loading…';

  // ── URL builder ──────────────────────────────────────────────────────────
  // FIXED: the original code only checked for '.' which caused a double
  // https:// prefix crash when the query already started with "https://".
  // Now we properly detect full URLs, bare domains, and search queries.
  String _buildUrl(String query) {
    final q = query.trim();
    if (q.isEmpty) return 'https://www.google.com';

    // Already a full URL — return as-is
    if (q.startsWith('http://') || q.startsWith('https://')) return q;

    // Looks like a bare domain: has a dot, no spaces, no query symbols
    final domainPattern =
        RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}(/.*)?$');
    if (domainPattern.hasMatch(q) && !q.contains(' ')) {
      return 'https://$q';
    }

    // Default: Google search
    return 'https://www.google.com/search?q=${Uri.encodeComponent(q)}';
  }

  // Trim the displayed URL to fit the AppBar on small screens
  String _displayUrl(String url) {
    return url
        .replaceFirst('https://', '')
        .replaceFirst('http://', '')
        .replaceFirst('www.', '');
  }

  @override
  void initState() {
    super.initState();
    _currentUrl = _buildUrl(widget.initialQuery);
  }

  @override
  void dispose() {
    // Release the native webview controller reference
    _webViewController = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,

      // ── AppBar ──────────────────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: AppTheme.darkBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white70),
          onPressed: () async {
            if (await _webViewController?.canGoBack() ?? false) {
              _webViewController?.goBack();
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page title
            Text(
              _pageTitle,
              style: const TextStyle(
                fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,  // FIXED: was missing → overflow
              maxLines: 1,
            ),
            // Shortened URL beneath title
            Text(
              _displayUrl(_currentUrl),
              style: const TextStyle(fontSize: 11, color: AppTheme.accentCyan),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
        actions: [
          // Reload button
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white54, size: 20),
            onPressed: () => _webViewController?.reload(),
          ),
        ],
      ),

      // ── Body ────────────────────────────────────────────────────────────
      body: Column(
        children: [
          // Thin loading progress bar
          if (_progress < 1.0)
            LinearProgressIndicator(
              value: _progress,
              color: AppTheme.accentCyan,
              backgroundColor: Colors.transparent,
              minHeight: 2,
            ),

          // WebView — takes the remaining space
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_currentUrl)),

              // FIXED: added InAppWebViewSettings for proper browser behaviour
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled:           true,
                domStorageEnabled:           true,
                databaseEnabled:             true,
                useWideViewPort:             true,
                loadWithOverviewMode:        true,
                supportZoom:                 true,
                builtInZoomControls:         true,
                displayZoomControls:         false,
                allowsInlineMediaPlayback:   true,
                mediaPlaybackRequiresUserGesture: false,
                // Allow mixed HTTP/HTTPS content (browser requirement)
                mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                // Enable text selection, zoom, etc.
                allowFileAccess:   true,
                allowContentAccess: true,
              ),

              onWebViewCreated: (controller) =>
                  _webViewController = controller,

              onTitleChanged: (controller, title) {
                if (title != null && title.isNotEmpty && mounted) {
                  setState(() => _pageTitle = title);
                }
              },

              onLoadStop: (controller, url) async {
                if (url == null) return;
                if (mounted) {
                  setState(() => _currentUrl = url.toString());
                }
                // Persist browsing history
                await LocalDB.saveHistoryItem(
                  url.toString(),
                  _pageTitle,
                );
              },

              onProgressChanged: (controller, progress) {
                if (mounted) {
                  setState(() => _progress = progress / 100);
                }
              },

              onReceivedError: (controller, request, error) {
                // Only show error page for the main frame, not sub-resources
                if (request.isForMainFrame == true && mounted) {
                  setState(() => _pageTitle = 'Page load error');
                }
              },
            ),
          ),
        ],
      ),

      // ── Bottom navigation bar ────────────────────────────────────────────
      bottomNavigationBar: Container(
        color: AppTheme.darkBackground,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white54, size: 18),
              onPressed: () async {
                if (await _webViewController?.canGoBack() ?? false) {
                  _webViewController?.goBack();
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 18),
              onPressed: () async {
                if (await _webViewController?.canGoForward() ?? false) {
                  _webViewController?.goForward();
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.home_outlined, color: Colors.white54, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white54, size: 20),
              onPressed: () => _webViewController?.reload(),
            ),
          ],
        ),
      ),
    );
  }
}
