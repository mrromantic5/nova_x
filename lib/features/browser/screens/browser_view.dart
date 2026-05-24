import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/database/local_db.dart';
import 'package:nova_x/core/theme/app_theme.dart';

class BrowserView extends StatefulWidget {
  final String initialQuery;
  const BrowserView({super.key, required this.initialQuery});

  @override
  State<BrowserView> createState() => _BrowserViewState();
}

class _BrowserViewState extends State<BrowserView>
    with SingleTickerProviderStateMixin {
  InAppWebViewController? _wvc;
  final TextEditingController _urlCtrl = TextEditingController();
  bool _editing     = false;
  bool _canBack     = false;
  bool _canForward  = false;
  double _progress  = 0;
  String _currentUrl   = '';
  String _pageTitle    = 'Loading…';
  bool _isBookmarked   = false;
  bool _isSecure       = false;

  late AnimationController _progressAnimCtrl;

  // ── URL logic ────────────────────────────────────────────────────────────
  String _buildUrl(String query) {
    final q = query.trim();
    if (q.isEmpty) return 'https://www.google.com';
    if (q.startsWith('http://') || q.startsWith('https://')) return q;
    final domainRx = RegExp(
        r'^[a-zA-Z0-9][a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}(/.*)?$');
    if (domainRx.hasMatch(q) && !q.contains(' ')) return 'https://$q';
    return LocalDB.buildSearchUrl(q);
  }

  String _hostLabel(String url) => url
      .replaceFirst('https://', '')
      .replaceFirst('http://', '')
      .replaceFirst('www.', '')
      .split('/')[0];

  @override
  void initState() {
    super.initState();
    _progressAnimCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    final initial = _buildUrl(widget.initialQuery);
    _currentUrl    = initial;
    _urlCtrl.text  = _hostLabel(initial);
    _isSecure      = initial.startsWith('https://');
    _isBookmarked  = LocalDB.isBookmarked(initial);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _progressAnimCtrl.dispose();
    _wvc = null;
    super.dispose();
  }

  Future<void> _toggleBookmark() async {
    HapticFeedback.mediumImpact();
    if (_isBookmarked) {
      await LocalDB.removeBookmark(_currentUrl);
    } else {
      await LocalDB.addBookmark(_currentUrl, _pageTitle);
    }
    if (mounted) setState(() => _isBookmarked = !_isBookmarked);
    _showSnack(_isBookmarked ? '★ Bookmark added' : 'Bookmark removed');
  }

  void _navigateTo(String query) {
    final url = _buildUrl(query);
    _wvc?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    setState(() {
      _editing   = false;
      _currentUrl = url;
      _urlCtrl.text = _hostLabel(url);
      _isSecure  = url.startsWith('https://');
    });
    FocusScope.of(context).unfocus();
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
      backgroundColor: AppTheme.bgElevated,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _copyUrl() {
    Clipboard.setData(ClipboardData(text: _currentUrl));
    _showSnack('URL copied');
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _BrowserMenuSheet(
        url: _currentUrl,
        onCopy: _copyUrl,
        onRefresh: () { Navigator.pop(context); _wvc?.reload(); },
        onDesktop: () {
          Navigator.pop(context);
          _wvc?.loadUrl(urlRequest: URLRequest(
            url: WebUri(_currentUrl),
            headers: {'User-Agent':
              'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36'},
          ));
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Column(children: [
        _buildTopBar(),
        _buildProgressBar(),
        Expanded(child: _buildWebView()),
        _buildBottomBar(),
      ]),
    );
  }

  // ── Top URL bar ────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      color: AppTheme.bgDark,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 12,
        right: 12,
        bottom: 8,
      ),
      child: Row(children: [
        // Back
        _topBtn(Icons.arrow_back_ios_new_rounded,
            () async {
              if (await _wvc?.canGoBack() ?? false) {
                _wvc?.goBack();
              } else {
                Navigator.pop(context);
              }
            }),
        const SizedBox(width: 8),
        // URL bar
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _editing = true;
                _urlCtrl.text = _currentUrl;
                _urlCtrl.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: _urlCtrl.text.length);
              });
            },
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Row(children: [
                Icon(
                  _isSecure ? Icons.lock_rounded : Icons.lock_open_rounded,
                  color: _isSecure ? AppTheme.secure : AppTheme.textHint,
                  size: 14,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _editing
                      ? TextField(
                          controller: _urlCtrl,
                          autofocus: true,
                          style: GoogleFonts.inter(
                              color: Colors.white, fontSize: 13),
                          onSubmitted: (v) => _navigateTo(v),
                          textInputAction: TextInputAction.go,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        )
                      : Text(
                          _hostLabel(_currentUrl),
                          style: GoogleFonts.inter(
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Bookmark
        _topBtn(
          _isBookmarked
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded,
          _toggleBookmark,
          color: _isBookmarked ? AppTheme.warning : AppTheme.textHint,
        ),
        const SizedBox(width: 4),
        // More
        _topBtn(Icons.more_vert_rounded, _showMoreMenu),
      ]),
    );
  }

  Widget _topBtn(IconData icon, VoidCallback onTap,
      {Color color = AppTheme.textHint}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }

  // ── Progress bar ──────────────────────────────────────────────────────
  Widget _buildProgressBar() {
    if (_progress >= 1.0 || _progress == 0) return const SizedBox.shrink();
    return LinearProgressIndicator(
      value: _progress,
      color: AppTheme.accentCyan,
      backgroundColor: Colors.transparent,
      minHeight: 2,
    );
  }

  // ── WebView ─────────────────────────────────────────────────────────────
  Widget _buildWebView() {
    return InAppWebView(
      initialUrlRequest:
          URLRequest(url: WebUri(_currentUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled:            true,
        domStorageEnabled:            true,
        databaseEnabled:              true,
        useWideViewPort:              true,
        loadWithOverviewMode:         true,
        supportZoom:                  true,
        builtInZoomControls:          true,
        displayZoomControls:          false,
        allowsInlineMediaPlayback:    true,
        mediaPlaybackRequiresUserGesture: false,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        allowFileAccess:              true,
        allowContentAccess:           true,
      ),
      onWebViewCreated: (c) => _wvc = c,
      onTitleChanged: (_, title) {
        if (title != null && mounted) setState(() => _pageTitle = title);
      },
      onLoadStart: (_, url) {
        if (url == null || !mounted) return;
        final u = url.toString();
        setState(() {
          _currentUrl   = u;
          _isSecure     = u.startsWith('https://');
          _isBookmarked = LocalDB.isBookmarked(u);
          if (!_editing) _urlCtrl.text = _hostLabel(u);
        });
      },
      onLoadStop: (c, url) async {
        if (url == null || !mounted) return;
        final u = url.toString();
        setState(() {
          _canBack    = false; // updated below
          _canForward = false;
          _currentUrl = u;
        });
        _canBack    = await c.canGoBack();
        _canForward = await c.canGoForward();
        if (mounted) setState(() {});
        await LocalDB.saveHistoryItem(u, _pageTitle);
      },
      onProgressChanged: (_, p) {
        if (mounted) setState(() => _progress = p / 100);
      },
      onReceivedError: (_, req, __) {
        if (req.isForMainFrame == true && mounted) {
          setState(() => _pageTitle = 'Page unavailable');
        }
      },
    );
  }

  // ── Bottom navigation ─────────────────────────────────────────────────
  Widget _buildBottomBar() {
    return Container(
      color: AppTheme.bgDark,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 4,
        top: 4,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _bottomBtn(Icons.arrow_back_ios_new_rounded, 'Back', () async {
            if (await _wvc?.canGoBack() ?? false) _wvc?.goBack();
          }, enabled: _canBack),
          _bottomBtn(Icons.arrow_forward_ios_rounded, 'Fwd', () async {
            if (await _wvc?.canGoForward() ?? false) _wvc?.goForward();
          }, enabled: _canForward),
          _bottomBtn(Icons.home_rounded, 'Home',
              () => Navigator.pop(context)),
          _bottomBtn(Icons.refresh_rounded, 'Reload',
              () => _wvc?.reload()),
          _bottomBtn(
            _isBookmarked
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            'Save',
            _toggleBookmark,
            activeColor: _isBookmarked ? AppTheme.warning : null,
          ),
        ],
      ),
    );
  }

  Widget _bottomBtn(IconData icon, String label, VoidCallback onTap,
      {bool enabled = true, Color? activeColor}) {
    final color = !enabled
        ? AppTheme.divider
        : (activeColor ?? AppTheme.textSecondary);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.inter(color: color, fontSize: 9)),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Browser more-options sheet
// ══════════════════════════════════════════════════════════════════════════════
class _BrowserMenuSheet extends StatelessWidget {
  final String url;
  final VoidCallback onCopy;
  final VoidCallback onRefresh;
  final VoidCallback onDesktop;

  const _BrowserMenuSheet({
    required this.url,
    required this.onCopy,
    required this.onRefresh,
    required this.onDesktop,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      {'icon': Icons.copy_rounded,        'label': 'Copy URL',      'fn': onCopy},
      {'icon': Icons.refresh_rounded,     'label': 'Reload',        'fn': onRefresh},
      {'icon': Icons.desktop_windows_outlined, 'label': 'Desktop site', 'fn': onDesktop},
    ];
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40, height: 4,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: AppTheme.textHint,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Text(url,
            style: GoogleFonts.inter(
                color: AppTheme.textHint, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 20),
        ...items.map((item) => ListTile(
              leading: Icon(item['icon'] as IconData,
                  color: AppTheme.accentCyan, size: 20),
              title: Text(item['label'] as String,
                  style: GoogleFonts.inter(
                      color: AppTheme.textPrimary, fontSize: 14)),
              onTap: item['fn'] as VoidCallback,
              contentPadding: EdgeInsets.zero,
            )),
      ]),
    );
  }
}
