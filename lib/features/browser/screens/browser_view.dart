// lib/features/browser/screens/browser_view.dart
//
// NOVA X Browser — full browser view
// New in this version:
//   • In-app Developer Tools (Elements / Console / Storage / Info)
//   • Incognito mode (no history, no cookies persisted, cleared on exit)
//   • Zoom controls (text zoom slider + reset)

import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nova_x/core/services/password_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/database/local_db.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import '../widgets/devtools_panel.dart';

class BrowserView extends StatefulWidget {
  final String initialQuery;
  /// Set to true to open in private/incognito mode
  final bool incognito;

  const BrowserView({
    super.key,
    required this.initialQuery,
    this.incognito = false,
  });

  @override
  State<BrowserView> createState() => _BrowserViewState();
}

class _BrowserViewState extends State<BrowserView>
    with SingleTickerProviderStateMixin {
  InAppWebViewController? _wvc;
  final TextEditingController _urlCtrl = TextEditingController();

  bool   _editing     = false;
  bool   _canBack     = false;
  bool   _canForward  = false;
  double _progress    = 0;
  String _currentUrl  = '';
  String _pageTitle   = 'Loading…';
  bool   _isBookmarked = false;
  bool   _isSecure    = false;
  bool   _desktopMode   = false;

  // ── Ad Blocker ──────────────────────────────────────────────────────────
  bool   _adBlockEnabled = false;

  // ── Password Manager ────────────────────────────────────────────────────
  bool   _savePasswords  = true;
  Map<String, String>? _pendingCredentials;  // waiting for user to confirm save
  Map<String, String>? _savedCreds;          // autofill candidate for current domain

  // ── DevTools ──────────────────────────────────────────────────────────────
  final List<Map<String, dynamic>> _consoleLogs = [];

  // ── Zoom ──────────────────────────────────────────────────────────────────
  double _textZoom    = 100; // 50 – 200
  bool   _showZoomBar = false;

  // ── UAs ───────────────────────────────────────────────────────────────────
  static const String _desktopUA =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  // JS that patches console.* to forward logs to Flutter
  static const String _consoleHook = r'''
(function() {
  if (window.__novax_patched) return;
  window.__novax_patched = true;
  ['log','warn','error','info','debug'].forEach(function(t) {
    var orig = console[t].bind(console);
    console[t] = function() {
      var msg = Array.prototype.slice.call(arguments).map(function(a) {
        try {
          return typeof a === 'object' ? JSON.stringify(a) : String(a);
        } catch(e) { return '[Object]'; }
      }).join(' ');
      try {
        window.flutter_inappwebview.callHandler(
          'novaxLog', { type: t, msg: msg, time: new Date().toLocaleTimeString() }
        );
      } catch(e) {}
      orig.apply(console, arguments);
    };
  });
})();
''';

  // ── URL helpers ────────────────────────────────────────────────────────────
  String _buildUrl(String query) {
    final q = query.trim();
    if (q.isEmpty) return 'https://www.google.com';
    if (q.startsWith('http://') || q.startsWith('https://')) return q;
    final domainRx =
        RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}(/.*)?$');
    if (domainRx.hasMatch(q) && !q.contains(' ')) return 'https://$q';
    return LocalDB.buildSearchUrl(q);
  }

  String _hostLabel(String url) => url
      .replaceFirst('https://', '')
      .replaceFirst('http://', '')
      .replaceFirst('www.', '')
      .split('/')[0];

  // ── Init / dispose ─────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    final initial = _buildUrl(widget.initialQuery);
    _currentUrl   = initial;
    _urlCtrl.text = _hostLabel(initial);
    _isSecure     = initial.startsWith('https://');
    _isBookmarked    = widget.incognito ? false : LocalDB.isBookmarked(initial);
    _adBlockEnabled  = LocalDB.getAdBlockEnabled();
    _savePasswords   = LocalDB.getSavePasswordsEnabled();
  }

  @override
  void dispose() {
    // Incognito: clear cookies + cache on exit
    if (widget.incognito && _wvc != null) {
      _wvc!.clearCache();
      CookieManager.instance().deleteAllCookies();
    }
    _urlCtrl.dispose();
    _wvc = null;
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────────────────────
  Future<void> _toggleBookmark() async {
    if (widget.incognito) { _snack('Bookmarks are disabled in incognito mode'); return; }
    HapticFeedback.mediumImpact();
    if (_isBookmarked) {
      await LocalDB.removeBookmark(_currentUrl);
    } else {
      await LocalDB.addBookmark(_currentUrl, _pageTitle);
    }
    if (mounted) setState(() => _isBookmarked = !_isBookmarked);
    _snack(_isBookmarked ? '★ Bookmark added' : 'Bookmark removed');
  }

  Future<void> _toggleDesktopMode() async {
    setState(() => _desktopMode = !_desktopMode);
    await _wvc?.setSettings(
      settings: InAppWebViewSettings(
        userAgent: _desktopMode ? _desktopUA : null,
      ),
    );
    await _wvc?.reload();
    _snack(_desktopMode ? '🖥️ Desktop site' : '📱 Mobile site');
  }

  Future<void> _applyTextZoom(double zoom) async {
    setState(() => _textZoom = zoom);
    await _wvc?.setSettings(
      settings: InAppWebViewSettings(textZoom: zoom.toInt()),
    );
  }

  void _navigateTo(String query) {
    final url = _buildUrl(query);
    _wvc?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    setState(() {
      _editing    = false;
      _currentUrl = url;
      _urlCtrl.text = _hostLabel(url);
      _isSecure   = url.startsWith('https://');
    });
    FocusScope.of(context).unfocus();
  }

  void _copyUrl() {
    Clipboard.setData(ClipboardData(text: _currentUrl));
    _snack('URL copied');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
      backgroundColor: AppTheme.bgElevated,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.incognito
          ? const Color(0xFF0D0C1A)   // darker purple tint for incognito
          : AppTheme.bgDark,
      resizeToAvoidBottomInset: true,
      body: Stack(children: [
        Column(children: [
          _buildTopBar(),
          _buildProgressBar(),
          Expanded(child: _buildWebView()),
          // Zoom bar (shown above bottom bar when active)
          if (_showZoomBar) _buildZoomBar(),
          _buildBottomBar(),
        ]),
      ]),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      color: widget.incognito ? const Color(0xFF120F2A) : AppTheme.bgDark,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 10, right: 10, bottom: 8,
      ),
      child: Row(children: [
        _topBtn(Icons.arrow_back_ios_new_rounded, () async {
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
                    baseOffset: 0, extentOffset: _urlCtrl.text.length);
              });
            },
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: widget.incognito
                    ? const Color(0xFF1C1535)
                    : AppTheme.bgCard,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: widget.incognito
                      ? AppTheme.accentPurple.withOpacity(0.3)
                      : AppTheme.divider,
                ),
              ),
              child: Row(children: [
                // Incognito spy icon OR lock icon
                Icon(
                  widget.incognito
                      ? Icons.privacy_tip_outlined
                      : (_isSecure ? Icons.lock_rounded : Icons.lock_open_rounded),
                  color: widget.incognito
                      ? AppTheme.accentPurple
                      : (_isSecure ? AppTheme.secure : AppTheme.textHint),
                  size: 13,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _editing
                      ? TextField(
                          controller: _urlCtrl,
                          autofocus: true,
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                          onSubmitted: _navigateTo,
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
                              color: widget.incognito
                                  ? const Color(0xFFBBABDD)
                                  : AppTheme.textSecondary,
                              fontSize: 13, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis, maxLines: 1,
                        ),
                ),
                // Indicators
                if (_desktopMode)
                  const Icon(Icons.desktop_windows_outlined,
                      color: AppTheme.accentCyan, size: 13),
                if (_textZoom != 100) ...[
                  const SizedBox(width: 4),
                  Text('${_textZoom.toInt()}%',
                      style: GoogleFonts.inter(
                          color: AppTheme.warning, fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ],
              ]),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Incognito badge (instead of bookmark in incognito)
        if (widget.incognito)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.accentPurple.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.accentPurple.withOpacity(0.4)),
            ),
            child: const Icon(Icons.person_off_outlined,
                color: AppTheme.accentPurple, size: 15),
          )
        else
          _topBtn(
            _isBookmarked
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            _toggleBookmark,
            color: _isBookmarked ? AppTheme.warning : AppTheme.textHint,
          ),

        const SizedBox(width: 4),
        _topBtn(Icons.more_vert_rounded, _showMoreMenu),
      ]),
    );
  }

  Widget _topBtn(IconData icon, VoidCallback onTap,
      {Color color = AppTheme.textHint}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: widget.incognito
              ? const Color(0xFF1C1535)
              : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 17),
      ),
    );
  }

  // ── Progress bar ──────────────────────────────────────────────────────────
  Widget _buildProgressBar() {
    if (_progress >= 1.0 || _progress == 0) return const SizedBox.shrink();
    return LinearProgressIndicator(
      value: _progress,
      color: widget.incognito ? AppTheme.accentPurple : AppTheme.accentCyan,
      backgroundColor: Colors.transparent,
      minHeight: 2,
    );
  }

  // ── WebView ────────────────────────────────────────────────────────────────
  Widget _buildWebView() {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(_currentUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled:            true,
        domStorageEnabled:            !widget.incognito,
        databaseEnabled:              !widget.incognito,
        cacheEnabled:                 !widget.incognito,
        clearCache:                   widget.incognito,
        useWideViewPort:              true,
        loadWithOverviewMode:         true,
        supportZoom:                  true,
        builtInZoomControls:          true,
        displayZoomControls:          false,
        allowsInlineMediaPlayback:    true,
        mediaPlaybackRequiresUserGesture: false,
        mixedContentMode:             MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        allowFileAccess:              true,
        allowContentAccess:           true,
        textZoom:                     _textZoom.toInt(),
        userAgent:                    _desktopMode ? _desktopUA : null,
        contentBlockers:              _adBlockEnabled ? PasswordService.buildAdBlockers() : [],
      ),

      onWebViewCreated: (c) {
        _wvc = c;
        // Console log handler
        c.addJavaScriptHandler(
          handlerName: 'novaxLog',
          callback: (args) {
            if (args.isNotEmpty && mounted) {
              try {
                final data = args[0] is Map
                    ? args[0] as Map<String, dynamic>
                    : jsonDecode(args[0].toString()) as Map<String, dynamic>;
                setState(() => _consoleLogs.add({
                  'type': data['type']?.toString() ?? 'log',
                  'msg':  data['msg']?.toString()  ?? '',
                  'time': data['time']?.toString()  ?? '',
                }));
              } catch (_) {}
            }
            return null;
          },
        );

        // Password detection handler
        if (!widget.incognito && _savePasswords) {
          c.addJavaScriptHandler(
            handlerName: 'novaxPwDetect',
            callback: (args) async {
              if (args.isEmpty || !mounted) return null;
              try {
                final data = args[0] is Map
                    ? Map<String, dynamic>.from(args[0] as Map)
                    : jsonDecode(args[0].toString()) as Map<String, dynamic>;
                final domain = data['domain']?.toString() ?? '';
                final user   = data['username']?.toString() ?? '';
                final pass   = data['password']?.toString() ?? '';
                if (domain.isNotEmpty && pass.isNotEmpty) {
                  _pendingCredentials = {'domain': domain, 'username': user, 'password': pass};
                  if (mounted) _showSavePasswordPrompt(domain, user, pass);
                }
              } catch (_) {}
              return null;
            },
          );
        }
      },

      onLoadStart: (c, url) async {
        if (url == null || !mounted) return;
        final u = url.toString();
        setState(() {
          _currentUrl = u;
          _isSecure   = u.startsWith('https://');
          _isBookmarked = widget.incognito ? false : LocalDB.isBookmarked(u);
          if (!_editing) _urlCtrl.text = _hostLabel(u);
        });
        // Inject console patch as early as possible
        await c.evaluateJavascript(source: _consoleHook);
        // Password detection hook
        if (!widget.incognito && _savePasswords) {
          await c.evaluateJavascript(source: PasswordService.pwDetectJS);
        }
      },

      onTitleChanged: (_, title) {
        if (title != null && mounted) setState(() => _pageTitle = title);
      },

      onLoadStop: (c, url) async {
        if (url == null || !mounted) return;
        final u = url.toString();
        _canBack    = await c.canGoBack();
        _canForward = await c.canGoForward();
        if (mounted) setState(() => _currentUrl = u);
        // Re-inject console hook (catches any page that replaced window context)
        await c.evaluateJavascript(source: _consoleHook);
        // Don't save history in incognito
        if (!widget.incognito) await LocalDB.saveHistoryItem(u, _pageTitle);
        // Check for saved passwords for autofill
        if (!widget.incognito && _savePasswords) {
          final domain = LocalDB.extractDomain(u);
          final creds  = await PasswordService.getCredentials(domain);
          if (creds != null && mounted) {
            _savedCreds = creds;
            _showAutofillPrompt(domain);
          }
        }
      },

      onProgressChanged: (_, p) {
        if (mounted) setState(() => _progress = p / 100);
      },

      onDownloadStartRequest: (controller, request) async {
        if (widget.incognito) {
          _snack('Downloads are disabled in incognito mode');
          return;
        }
        final url  = request.url.toString();
        final name = url.split('/').last.split('?').first;
        await LocalDB.addDownload({
          'url':       url,
          'filename':  name.isNotEmpty ? name : 'download',
          'mime':      request.mimeType ?? 'unknown',
          'size':      request.contentLength ?? 0,
          'timestamp': DateTime.now().toIso8601String(),
          'status':    'intercepted',
        });
        _snack('Download captured: ${name.isNotEmpty ? name : 'file'}');
      },

      onReceivedError: (_, req, __) {
        if (req.isForMainFrame == true && mounted) {
          setState(() => _pageTitle = 'Page unavailable');
        }
      },
    );
  }

  // ── Zoom bar ───────────────────────────────────────────────────────────────
  Widget _buildZoomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgElevated,
        border: Border(
          top:    BorderSide(color: AppTheme.warning.withOpacity(0.3)),
          bottom: BorderSide(color: AppTheme.divider),
        ),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: () => _applyTextZoom((_textZoom - 10).clamp(50, 200)),
          child: Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.divider),
            ),
            child: const Icon(Icons.remove, color: AppTheme.textSecondary, size: 16),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(children: [
            Slider(
              value: _textZoom,
              min: 50, max: 200,
              divisions: 15,
              activeColor: AppTheme.warning,
              inactiveColor: AppTheme.divider,
              onChanged: _applyTextZoom,
            ),
          ]),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => _applyTextZoom((_textZoom + 10).clamp(50, 200)),
          child: Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.divider),
            ),
            child: const Icon(Icons.add, color: AppTheme.textSecondary, size: 16),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 42,
          child: Text('${_textZoom.toInt()}%',
              style: GoogleFonts.inter(
                  color: AppTheme.warning,
                  fontSize: 13, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () { _applyTextZoom(100); setState(() => _showZoomBar = false); },
          child: const Icon(Icons.close_rounded, color: AppTheme.textHint, size: 18),
        ),
      ]),
    );
  }

  // ── Bottom nav ─────────────────────────────────────────────────────────────
  Widget _buildBottomBar() {
    return Container(
      color: widget.incognito ? const Color(0xFF120F2A) : AppTheme.bgDark,
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 4, top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _bBtn(Icons.arrow_back_ios_new_rounded, 'Back', () async {
            if (await _wvc?.canGoBack() ?? false) _wvc?.goBack();
          }, enabled: _canBack),
          _bBtn(Icons.arrow_forward_ios_rounded, 'Fwd', () async {
            if (await _wvc?.canGoForward() ?? false) _wvc?.goForward();
          }, enabled: _canForward),
          _bBtn(Icons.home_rounded, 'Home', () => Navigator.pop(context)),
          _bBtn(Icons.refresh_rounded, 'Reload', () => _wvc?.reload()),
          _bBtn(
            _isBookmarked
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            'Save',
            _toggleBookmark,
            color: _isBookmarked ? AppTheme.warning : null,
          ),
        ],
      ),
    );
  }

  Widget _bBtn(IconData icon, String label, VoidCallback onTap,
      {bool enabled = true, Color? color}) {
    final c = !enabled
        ? AppTheme.divider
        : (color ??
            (widget.incognito ? const Color(0xFF9988CC) : AppTheme.textSecondary));
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: c, size: 20),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.inter(color: c, fontSize: 9)),
        ]),
      ),
    );
  }

  // ── Password Manager ────────────────────────────────────────────────────────
  void _showSavePasswordPrompt(String domain, String username, String password) {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppTheme.divider, borderRadius: BorderRadius.circular(2))),
          Row(children: [
            Container(width: 44, height: 44,
              decoration: BoxDecoration(gradient: AppTheme.primaryGradient, borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.key_rounded, color: Colors.white, size: 22)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Save password?', style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
              Text(domain, style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12)),
            ])),
          ]),
          if (username.isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: AppTheme.bgElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.divider)),
              child: Row(children: [
                const Icon(Icons.person_outline_rounded, color: AppTheme.textHint, size: 16),
                const SizedBox(width: 8),
                Text(username, style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13)),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(color: AppTheme.bgElevated,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.divider)),
                child: Center(child: Text('Not now', style: GoogleFonts.inter(
                    color: AppTheme.textHint, fontSize: 14, fontWeight: FontWeight.w600))),
              ),
            )),
            const SizedBox(width: 12),
            Expanded(child: GestureDetector(
              onTap: () async {
                await PasswordService.saveCredentials(domain, username, password);
                if (mounted) Navigator.pop(context);
                _snack('🔑 Password saved for $domain');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppTheme.glowShadow),
                child: Center(child: Text('Save', style: GoogleFonts.spaceGrotesk(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700))),
              ),
            )),
          ]),
        ]),
      ),
    );
  }

  void _showAutofillPrompt(String domain) {
    final creds = _savedCreds;
    if (creds == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.key_rounded, color: AppTheme.accentCyan, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text('Fill saved password for $domain?',
            style: GoogleFonts.inter(color: Colors.white, fontSize: 12))),
      ]),
      backgroundColor: AppTheme.bgElevated,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      action: SnackBarAction(
        label: 'Fill',
        textColor: AppTheme.accentCyan,
        onPressed: () async {
          final js = PasswordService.autofillJS(
              creds['username'] ?? '', creds['password'] ?? '');
          await _wvc?.evaluateJavascript(source: js);
          _snack('✅ Password filled');
        },
      ),
    ));
  }

  // ── More menu ──────────────────────────────────────────────────────────────
  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: widget.incognito ? const Color(0xFF130F24) : AppTheme.bgCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
                color: AppTheme.textHint,
                borderRadius: BorderRadius.circular(2)),
          ),

          // Incognito banner
          if (widget.incognito) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppTheme.accentPurple.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.accentPurple.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.privacy_tip_outlined,
                    color: AppTheme.accentPurple, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'You\'re browsing privately. History, cookies and cache will be cleared when you close this tab.',
                    style: GoogleFonts.inter(
                        color: AppTheme.accentPurple.withOpacity(0.85),
                        fontSize: 11, height: 1.4),
                  ),
                ),
              ]),
            ),
          ],

          // Site info
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_hostLabel(_currentUrl),
                style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),

          // Menu items
          _menuTile(Icons.copy_rounded, 'Copy URL', _copyUrl),

          _menuTile(Icons.refresh_rounded, 'Reload page', () {
            Navigator.pop(context); _wvc?.reload();
          }),

          _menuTile(
            _desktopMode
                ? Icons.phone_android_rounded
                : Icons.desktop_windows_outlined,
            _desktopMode ? 'Switch to mobile site' : 'Request desktop site',
            () { Navigator.pop(context); _toggleDesktopMode(); },
            color: _desktopMode ? AppTheme.accentCyan : AppTheme.textSecondary,
          ),

          if (!widget.incognito)
            _menuTile(
              _isBookmarked
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              _isBookmarked ? 'Remove bookmark' : 'Add bookmark',
              () { Navigator.pop(context); _toggleBookmark(); },
              color: _isBookmarked ? AppTheme.warning : AppTheme.textSecondary,
            ),

          // ── ZOOM ──────────────────────────────────────────────────────────
          _menuTile(
            Icons.zoom_in_rounded,
            _showZoomBar
                ? 'Hide zoom controls'
                : 'Zoom (${_textZoom.toInt()}%)',
            () {
              Navigator.pop(context);
              setState(() => _showZoomBar = !_showZoomBar);
            },
            color: _textZoom != 100 ? AppTheme.warning : AppTheme.textSecondary,
          ),

          // ── DEVELOPER TOOLS ───────────────────────────────────────────────
          _menuTile(
            Icons.developer_mode_rounded,
            'Developer tools',
            () {
              Navigator.pop(context);
              showDevTools(
                context,
                wvc:            _wvc,
                url:            _currentUrl,
                pageTitle:      _pageTitle,
                consoleLogs:    _consoleLogs,
                onClearConsole: () => setState(() => _consoleLogs.clear()),
              );
            },
            color: AppTheme.accentCyan,
          ),

          // ── NEW INCOGNITO TAB ─────────────────────────────────────────────
          _menuTile(
            Icons.person_off_outlined,
            'New incognito tab',
            () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BrowserView(
                    initialQuery: _currentUrl,
                    incognito: true,
                  ),
                ),
              );
            },
            color: AppTheme.accentPurple,
          ),

          // ── FIND IN PAGE ───────────────────────────────────────────────────
          _menuTile(
            Icons.search_rounded, 'Find in page',
            () { Navigator.pop(context); _showFindInPage(); },
          ),

          // ── AD BLOCKER ─────────────────────────────────────────────────────
          ListTile(
            leading: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: (_adBlockEnabled
                    ? AppTheme.success : AppTheme.textHint).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.shield_rounded,
                  color: _adBlockEnabled ? AppTheme.success : AppTheme.textHint,
                  size: 18)),
            title: Text('Ad Blocker', style: GoogleFonts.inter(
                color: AppTheme.textPrimary, fontSize: 14)),
            subtitle: Text(_adBlockEnabled ? 'ON — Ads blocked' : 'OFF',
                style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11)),
            trailing: Switch(
              value: _adBlockEnabled,
              onChanged: (v) async {
                await LocalDB.setAdBlockEnabled(v);
                setState(() => _adBlockEnabled = v);
                Navigator.pop(context);
                await _wvc?.reload();
                _snack(v ? '🛡️ Ad Blocker ON — reloading…' : 'Ad Blocker OFF');
              },
              activeColor: AppTheme.success,
              inactiveThumbColor: AppTheme.textHint,
            ),
            contentPadding: EdgeInsets.zero, dense: true,
          ),

          // ── CLEAR PAGE DATA ────────────────────────────────────────────────
          _menuTile(
            Icons.cleaning_services_rounded, 'Clear page data',
            () async {
              Navigator.pop(context);
              await CookieManager.instance().deleteAllCookies();
              await _wvc?.clearCache();
              await _wvc?.evaluateJavascript(
                  source: 'localStorage.clear(); sessionStorage.clear();');
              await _wvc?.reload();
              _snack('🧹 Cookies, cache & storage cleared');
            },
            color: AppTheme.danger,
          ),
        ]),
      ),
    );
  }

  Widget _menuTile(IconData icon, String label, VoidCallback onTap,
      {Color color = AppTheme.textSecondary}) {
    return ListTile(
      leading: Icon(icon, color: color, size: 20),
      title:   Text(label,
          style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14)),
      onTap:   onTap,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }

  // ── Find in page ───────────────────────────────────────────────────────────
  void _showFindInPage() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          decoration: const BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                autofocus: true,
                style: GoogleFonts.inter(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Find in page…',
                  hintStyle: GoogleFonts.inter(color: AppTheme.textHint),
                  filled: true, fillColor: AppTheme.bgElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                ),
                onChanged: (q) async {
                  if (q.isEmpty) {
                    await _wvc?.clearMatches();
                  } else {
                    await _wvc?.findAllAsync(find: q);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            _toolIconBtn(Icons.arrow_upward_rounded,   () => _wvc?.findNext(forward: false)),
            const SizedBox(width: 6),
            _toolIconBtn(Icons.arrow_downward_rounded, () => _wvc?.findNext(forward: true)),
            const SizedBox(width: 6),
            _toolIconBtn(Icons.close_rounded, () async {
              await _wvc?.clearMatches();
              Navigator.pop(context);
            }),
          ]),
        ),
      ),
    );
  }

  Widget _toolIconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: AppTheme.bgElevated,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppTheme.textSecondary, size: 18),
      ),
    );
  }
}
