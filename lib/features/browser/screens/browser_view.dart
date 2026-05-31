// lib/features/browser/screens/browser_view.dart
//
// NOVA X Browser — full browser view
// New in this version:
//   • In-app Developer Tools (Elements / Console / Storage / Info)
//   • Incognito mode (no history, no cookies persisted, cleared on exit)
//   • Zoom controls (text zoom slider + reset)

import 'dart:convert';
import 'dart:collection';
import 'package:nova_x/core/services/biometric_service.dart';
import 'dart:io';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:nova_x/core/services/password_service.dart';
import 'package:nova_x/core/services/nova_shield_service.dart';
import 'package:nova_x/features/cookie/cookie_editor_screen.dart';
import 'package:nova_x/features/cyber/screens/cyber_screen.dart';
import 'package:nova_x/features/shield/screens/nova_shield_screen.dart';
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

  /// Optional HTML to load directly (e.g. visual search page).
  /// When set, loaded via loadData() with baseUrl=google.com
  final String? htmlContent;

  /// When true, the Developer Tools panel opens automatically after first load
  /// (used by the "Dev Tools" shortcut in the home more-menu).
  final bool autoOpenDevTools;

  const BrowserView({
    super.key,
    required this.initialQuery,
    this.incognito = false,
    this.htmlContent,
    this.autoOpenDevTools = false,
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
  bool   _desktopMode    = false;

  // ── Ad Blocker ──────────────────────────────────────────────────────────
  bool   _adBlockEnabled = false;

  // ── Password Manager ────────────────────────────────────────────────────
  bool   _savePasswords  = true;
  Map<String,String>? _savedCreds;

  // ── Reader Mode ──────────────────────────────────────────────────────────
  bool   _readerMode     = false;
  String _readerTheme    = 'dark';
  double _readerFontSize = 18.0;
  String? _readerOriginalUrl;

  // ── DevTools ──────────────────────────────────────────────────────────────
  final List<Map<String, dynamic>> _consoleLogs = [];
  final List<Map<String, dynamic>> _networkLogs = [];

  // In-page voice bridge (Web Speech API -> native speech_to_text)
  final SpeechToText _speech = SpeechToText();
  bool _speechAvail = false;
  bool _devToolsAutoOpened = false;

  // ── Zoom ──────────────────────────────────────────────────────────────────
  double _textZoom    = 100; // 50 – 200
  bool   _showZoomBar = false;

  // ── UAs ───────────────────────────────────────────────────────────────────
  static const String _desktopUA =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  // Forces a wide desktop layout that zooms out to fit the screen (Kiwi-style).
  // Without this, sites with `width=device-width` ignore the desktop UA and
  // never zoom out. We override the viewport to a fixed width and let
  // loadWithOverviewMode scale it down to the screen.
  static const String _desktopViewportJS = r'''
(function(){
  try{
    var W = 1024;
    var v = document.querySelector('meta[name="viewport"]');
    if(!v){ v = document.createElement('meta'); v.setAttribute('name','viewport');
            (document.head||document.documentElement).appendChild(v); }
    v.setAttribute('content','width='+W+', initial-scale='+(window.screen.width/W).toFixed(3)+', user-scalable=yes');
    document.documentElement.style.minWidth = W+'px';
  }catch(e){}
})();
''';

  // JS that patches console.*, window.onerror and unhandledrejection to
  // forward everything to Flutter (so the Console tab shows real errors).
  static const String _consoleHook = r'''
(function() {
  if (window.__novax_patched) return;
  window.__novax_patched = true;
  function send(type, msg){
    try {
      window.flutter_inappwebview.callHandler(
        'novaxLog', { type: type, msg: msg, time: new Date().toLocaleTimeString() }
      );
    } catch(e) {}
  }
  function fmt(a){
    try { return typeof a === 'object' ? JSON.stringify(a) : String(a); }
    catch(e){ return '[Object]'; }
  }
  ['log','warn','error','info','debug'].forEach(function(t) {
    var orig = console[t] ? console[t].bind(console) : function(){};
    console[t] = function() {
      send(t, Array.prototype.slice.call(arguments).map(fmt).join(' '));
      orig.apply(console, arguments);
    };
  });
  window.addEventListener('error', function(e){
    send('error', (e.message || 'Error') + (e.filename ? '  ('+e.filename+':'+e.lineno+')' : ''));
  });
  window.addEventListener('unhandledrejection', function(e){
    var r = e.reason; send('error', 'Uncaught (in promise) ' + (r && r.message ? r.message : fmt(r)));
  });
})();
''';

  // JS that records fetch() + XHR network calls and forwards them to Flutter.
  static const String _netHook = r'''
(function(){
  if (window.__novax_net) return;
  window.__novax_net = true;
  function send(o){
    try { window.flutter_inappwebview.callHandler('novaxNet', o); } catch(e){}
  }
  if (window.fetch){
    var of = window.fetch;
    window.fetch = function(){
      var args = arguments;
      var url = (args[0] && args[0].url) ? args[0].url : String(args[0]);
      var method = (args[1] && args[1].method) ? args[1].method : 'GET';
      var t0 = Date.now();
      return of.apply(this, args).then(function(res){
        send({url:url, method:method, status:res.status, ms:(Date.now()-t0), type:'fetch'});
        return res;
      }).catch(function(err){
        send({url:url, method:method, status:0, ms:(Date.now()-t0), type:'fetch', error:String(err)});
        throw err;
      });
    };
  }
  var OX = window.XMLHttpRequest;
  if (OX){
    var oo = OX.prototype.open, os = OX.prototype.send;
    OX.prototype.open = function(m,u){ this.__nx={m:m,u:u}; return oo.apply(this, arguments); };
    OX.prototype.send = function(){
      var self=this, t0=Date.now();
      this.addEventListener('loadend', function(){
        if(self.__nx) send({url:self.__nx.u, method:self.__nx.m, status:self.status, ms:(Date.now()-t0), type:'xhr'});
      });
      return os.apply(this, arguments);
    };
  }
})();
''';

  // Polyfills the Web Speech API (webkitSpeechRecognition / SpeechRecognition),
  // which Android System WebView does NOT implement. Calls bridge to the native
  // speech_to_text plugin. Injected at document START so sites that feature-check
  // on load see the API as available.
  static const String _speechShim = r'''
(function(){
  if (window.__nxSpeechPatched) return; window.__nxSpeechPatched = true;
  function R(){
    this.lang='en-US'; this.continuous=false; this.interimResults=false;
    this.maxAlternatives=1; this._active=false;
    this.onresult=null; this.onerror=null; this.onend=null; this.onstart=null;
    this.onspeechstart=null; this.onspeechend=null; this.onaudiostart=null;
    this.onaudioend=null; this.onnomatch=null; this.onsoundstart=null; this.onsoundend=null;
  }
  R.prototype.start=function(){
    if(this._active) return; this._active=true; window.__nxActiveRec=this;
    try{ this.onstart && this.onstart(new Event('start')); }catch(e){}
    try{ this.onaudiostart && this.onaudiostart(new Event('audiostart')); }catch(e){}
    try{ window.flutter_inappwebview.callHandler('nxSpeechStart', this.lang||'en-US'); }
    catch(e){ try{ this.onerror && this.onerror({error:'not-allowed'}); }catch(_){ } this._active=false; }
  };
  R.prototype.stop=function(){ this._active=false;
    try{ window.flutter_inappwebview.callHandler('nxSpeechStop',''); }catch(e){} };
  R.prototype.abort=function(){ this.stop(); };
  R.prototype.addEventListener=function(t,cb){ this['on'+t]=cb; };
  R.prototype.removeEventListener=function(t){ this['on'+t]=null; };
  R.prototype.dispatchEvent=function(){ return true; };
  window.__nxSpeechResult=function(text, isFinal){
    var rec=window.__nxActiveRec; if(!rec) return;
    var alt={transcript:String(text||''), confidence:0.9};
    var res=[alt]; res[0]=alt; res.length=1; res.isFinal=!!isFinal;
    res.item=function(i){return res[i];};
    var list=[res]; list[0]=res; list.length=1; list.item=function(i){return list[i];};
    var ev; try{ ev=new Event('result'); }catch(e){ ev={type:'result'}; }
    ev.results=list; ev.resultIndex=0;
    try{ rec.onresult && rec.onresult(ev); }catch(e){}
    if(isFinal){ rec._active=false;
      try{ rec.onspeechend && rec.onspeechend(new Event('speechend')); }catch(e){}
      try{ rec.onend && rec.onend(new Event('end')); }catch(e){}
      window.__nxActiveRec=null; }
  };
  window.__nxSpeechError=function(err){
    var rec=window.__nxActiveRec; if(!rec) return; rec._active=false;
    try{ rec.onerror && rec.onerror({error:String(err||'no-speech')}); }catch(e){}
    try{ rec.onend && rec.onend(new Event('end')); }catch(e){}
    window.__nxActiveRec=null;
  };
  window.__nxSpeechEnd=function(){
    var rec=window.__nxActiveRec; if(!rec) return; rec._active=false;
    try{ rec.onend && rec.onend(new Event('end')); }catch(e){}
    window.__nxActiveRec=null;
  };
  window.SpeechRecognition = R;
  window.webkitSpeechRecognition = R;
})();
''';

  // ── Developer Tools ──────────────────────────────────────────────────────
  void _openDevTools() {
    showDevTools(
      context,
      wvc:            _wvc,
      url:            _currentUrl,
      pageTitle:      _pageTitle,
      consoleLogs:    _consoleLogs,
      onClearConsole: () => setState(() => _consoleLogs.clear()),
      networkLogs:    _networkLogs,
      onClearNetwork: () => setState(() => _networkLogs.clear()),
    );
  }

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
    try { _speech.stop(); } catch (_) {}
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
        userAgent: _desktopMode ? _desktopUA : '',  // '' resets to default mobile UA
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
          _buildReaderToolbar(),
          if (!_readerMode) _buildBottomBar(),
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
        userAgent:                    _desktopMode ? _desktopUA : '',
        contentBlockers:              _adBlockEnabled
            ? PasswordService.buildAdBlockers() : [],
      ),

      initialUserScripts: UnmodifiableListView([
        UserScript(source: _speechShim,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START),
      ]),

      // Grant in-page media permissions (microphone / camera) so getUserMedia
      // and voice features work inside the WebView.
      onPermissionRequest: (controller, request) async {
        return PermissionResponse(
          resources: request.resources,
          action: PermissionResponseAction.GRANT,
        );
      },

      onWebViewCreated: (c) {
        _wvc = c;
        // Register the console log handler BEFORE any page loads
        // Password detection handler
        if (!widget.incognito && _savePasswords) {
          c.addJavaScriptHandler(
            handlerName: 'novaxPwDetect',
            callback: (args) async {
              if (args.isEmpty || !mounted) return null;
              try {
                final d = args[0] is Map
                    ? Map<String,dynamic>.from(args[0] as Map)
                    : jsonDecode(args[0].toString()) as Map<String,dynamic>;
                final domain = d['domain']?.toString() ?? '';
                final user   = d['username']?.toString() ?? '';
                final pass   = d['password']?.toString() ?? '';
                if (domain.isNotEmpty && pass.isNotEmpty && mounted)
                  _showSavePasswordPrompt(domain, user, pass);
              } catch (_) {}
              return null;
            },
          );
        }

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

        c.addJavaScriptHandler(
          handlerName: 'novaxNet',
          callback: (args) {
            if (args.isNotEmpty && mounted) {
              try {
                final d = args[0] is Map
                    ? args[0] as Map<String, dynamic>
                    : jsonDecode(args[0].toString()) as Map<String, dynamic>;
                setState(() {
                  _networkLogs.add({
                    'url':    d['url']?.toString() ?? '',
                    'method': d['method']?.toString() ?? 'GET',
                    'status': d['status'] is num ? (d['status'] as num).toInt() : 0,
                    'ms':     d['ms'] is num ? (d['ms'] as num).toInt() : 0,
                    'type':   d['type']?.toString() ?? '',
                  });
                  if (_networkLogs.length > 300) _networkLogs.removeAt(0);
                });
              } catch (_) {}
            }
            return null;
          },
        );
        if (widget.htmlContent != null) {
          Future.delayed(const Duration(milliseconds: 80), () {
            c.loadData(
              data:     widget.htmlContent!,
              mimeType: 'text/html',
              encoding: 'utf-8',
              baseUrl:  WebUri('https://www.google.com'),
            );
          });
        }

        // ── Voice bridge: page calls webkitSpeechRecognition → native STT ──
        c.addJavaScriptHandler(
          handlerName: 'nxSpeechStart',
          callback: (args) async {
            final raw = args.isNotEmpty ? args[0].toString() : 'en-US';
            final locale = raw.replaceAll('-', '_');
            try {
              if (!_speechAvail) {
                _speechAvail = await _speech.initialize(
                  onError: (e) {
                    _wvc?.evaluateJavascript(
                        source: 'window.__nxSpeechError && window.__nxSpeechError(${jsonEncode(e.errorMsg)})');
                  },
                  onStatus: (s) {
                    if (s == 'done' || s == 'notListening') {
                      _wvc?.evaluateJavascript(
                          source: 'window.__nxSpeechEnd && window.__nxSpeechEnd()');
                    }
                  },
                );
              }
              if (!_speechAvail) {
                _wvc?.evaluateJavascript(
                    source: "window.__nxSpeechError && window.__nxSpeechError('not-allowed')");
                return null;
              }
              await _speech.listen(
                localeId: locale,
                partialResults: true,
                cancelOnError: true,
                onResult: (r) {
                  _wvc?.evaluateJavascript(
                      source: 'window.__nxSpeechResult && window.__nxSpeechResult('
                          '${jsonEncode(r.recognizedWords)}, ${r.finalResult})');
                },
              );
            } catch (_) {
              _wvc?.evaluateJavascript(
                  source: "window.__nxSpeechError && window.__nxSpeechError('audio-capture')");
            }
            return null;
          },
        );
        c.addJavaScriptHandler(
          handlerName: 'nxSpeechStop',
          callback: (args) async {
            try { await _speech.stop(); } catch (_) {}
            _wvc?.evaluateJavascript(source: 'window.__nxSpeechEnd && window.__nxSpeechEnd()');
            return null;
          },
        );
      },

      onLoadStart: (c, url) async {
        if (url != null && NovaShieldService.isEnabled) {
          final urlStr = url.toString();
          // Layer 3: HTTPS enforcement
          final httpsUrl = NovaShieldService.enforceHttps(urlStr);
          if (httpsUrl != null) {
            await NovaShieldService.recordHttpsUpgrade();
            await c.loadUrl(urlRequest: URLRequest(url: WebUri(httpsUrl)));
            return;
          }
          // Layer 1+2: Domain threat check via Cloudflare DoH
          if (!urlStr.startsWith('data:') && !urlStr.startsWith('about:') &&
              !urlStr.startsWith('blob:')) {
            final threat = await NovaShieldService.checkDomain(urlStr);
            if (threat.isThreat && mounted) {
              // Block the navigation and show warning
              await c.loadData(
                data: _buildBlockPage(threat.domain, threat.threatType),
                mimeType: 'text/html', encoding: 'utf-8');
              return;
            }
          }
        }
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
        await c.evaluateJavascript(source: _netHook);
        if (_desktopMode)
          await c.evaluateJavascript(source: _desktopViewportJS);
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
        await c.evaluateJavascript(source: _netHook);
        if (_desktopMode)
          await c.evaluateJavascript(source: _desktopViewportJS);
        // Ad blocker: cosmetic filtering — hide common ad containers so blocked
        // ads don't leave blank gaps. Pairs with the network-level ContentBlockers.
        if (_adBlockEnabled)
          await c.evaluateJavascript(source: PasswordService.adCosmeticJS);
        // Don't save history in incognito
        if (!widget.incognito) await LocalDB.saveHistoryItem(u, _pageTitle);
        // Inject password detection
        if (!widget.incognito && _savePasswords)
          await c.evaluateJavascript(source: PasswordService.pwDetectJS);
        // NOVA Shield: inject all protection layers
        if (NovaShieldService.isEnabled) {
          final js = NovaShieldService.buildProtectionBundle(
              incognito: widget.incognito);
          if (js.isNotEmpty)
            await c.evaluateJavascript(source: js);
        }
        // Check for saved credentials for this domain
        if (!widget.incognito && _savePasswords) {
          final creds = await PasswordService.getCredentials(LocalDB.extractDomain(u));
          if (creds != null && mounted) {
            _savedCreds = creds;
            _showAutofillSnack(LocalDB.extractDomain(u));
          }
        }
        // Auto-open Developer Tools when launched from the home shortcut
        if (widget.autoOpenDevTools && !_devToolsAutoOpened && mounted) {
          _devToolsAutoOpened = true;
          Future.delayed(const Duration(milliseconds: 250), () {
            if (mounted) _openDevTools();
          });
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

  // ── More menu ──────────────────────────────────────────────────────────────
  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.62,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: widget.incognito ? const Color(0xFF130F24) : AppTheme.bgCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          controller: scrollCtrl,
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
              _openDevTools();
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

          // ── NOVA SHIELD ────────────────────────────────────────────────
          ListTile(
            contentPadding: EdgeInsets.zero, dense: true,
            leading: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                gradient: NovaShieldService.isEnabled
                    ? AppTheme.primaryGradient : null,
                color: NovaShieldService.isEnabled ? null : AppTheme.bgElevated,
                borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.shield_rounded,
                  color: Colors.white, size: 17)),
            title: Text('NOVA Shield', style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary, fontSize: 14,
                fontWeight: FontWeight.w700)),
            subtitle: Text(
              NovaShieldService.isEnabled
                  ? '${NovaShieldService.protectionLevel} protection — ON'
                  : 'Protection disabled',
              style: GoogleFonts.inter(
                  color: NovaShieldService.isEnabled
                      ? AppTheme.success : AppTheme.textHint, fontSize: 11)),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.success.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.success.withOpacity(0.3))),
              child: Text('NEW', style: GoogleFonts.inter(
                  color: AppTheme.success, fontSize: 9,
                  fontWeight: FontWeight.w800))),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const NovaShieldScreen()));
            },
          ),

          // ── NOVA CYBER ─────────────────────────────────────────────────────
          ListTile(
            contentPadding: EdgeInsets.zero, dense: true,
            leading: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.security_rounded,
                  color: Colors.white, size: 17)),
            title: Text('NOVA Cyber', style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary, fontSize: 14,
                fontWeight: FontWeight.w700)),
            subtitle: Text('Website security scanner',
                style: GoogleFonts.inter(
                    color: AppTheme.textHint, fontSize: 11)),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.accentCyan.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: AppTheme.accentCyan.withOpacity(0.3))),
              child: Text('CYBER', style: GoogleFonts.inter(
                  color: AppTheme.accentCyan, fontSize: 9,
                  fontWeight: FontWeight.w800))),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(
                  builder: (_) => CyberScreen(initialUrl: _currentUrl)));
            },
          ),

          // ── FIND IN PAGE (bonus) ──────────────────────────────────────────
          // ── COOKIE EDITOR ──────────────────────────────────────────────────
          _menuTile(Icons.cookie_outlined, 'Cookie Editor',
            () { Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => CookieEditorScreen(url: _currentUrl))); },
            color: AppTheme.warning),

          // ── READER MODE ─────────────────────────────────────────────────────
          _menuTile(Icons.menu_book_rounded,
            _readerMode ? 'Exit Reader Mode' : 'Reader Mode',
            () { Navigator.pop(context); _toggleReaderMode(); },
            color: _readerMode ? AppTheme.warning : AppTheme.textSecondary),

          // ── AD BLOCKER ──────────────────────────────────────────────────────
          ListTile(
            contentPadding: EdgeInsets.zero, dense: true,
            leading: Container(width:34, height:34,
              decoration: BoxDecoration(
                color: (_adBlockEnabled ? AppTheme.success : AppTheme.textHint).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.shield_rounded,
                color: _adBlockEnabled ? AppTheme.success : AppTheme.textHint, size: 18)),
            title: Text('Ad Blocker', style: GoogleFonts.inter(
                color: AppTheme.textPrimary, fontSize:14)),
            subtitle: Text(_adBlockEnabled ? 'ON — ads blocked' : 'OFF',
                style: GoogleFonts.inter(color: AppTheme.textHint, fontSize:11)),
            trailing: Switch(
              value: _adBlockEnabled,
              onChanged: (v) async {
                await LocalDB.setAdBlockEnabled(v);
                setState(() => _adBlockEnabled = v);
                Navigator.pop(context);
                await _wvc?.reload();
                _snack(v ? '🛡️ Ad Blocker ON' : 'Ad Blocker OFF');
              },
              activeColor: AppTheme.success,
            ),
          ),

          // ── CLEAR PAGE DATA ─────────────────────────────────────────────────
          _menuTile(Icons.cleaning_services_rounded, 'Clear page data',
            () async { Navigator.pop(context);
              await CookieManager.instance().deleteAllCookies();
              await _wvc?.clearCache();
              await _wvc?.evaluateJavascript(
                  source: 'localStorage.clear();sessionStorage.clear();');
              await _wvc?.reload();
              _snack('🧹 Cookies, cache & storage cleared'); },
            color: AppTheme.danger),

          // ── FIND IN PAGE ────────────────────────────────────────────────────
          _menuTile(
            Icons.search_rounded,
            'Find in page',
            () {
              Navigator.pop(context);
              _showFindInPage();
            },
          ),
        ]),
        ),   // SingleChildScrollView
        ),   // Container (DraggableScrollable builder)
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

  // ── Password Manager ───────────────────────────────────────────────────────
  void _showSavePasswordPrompt(String domain, String username, String password) {
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(color: AppTheme.bgCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width:40, height:4, margin: const EdgeInsets.only(bottom:16),
              decoration: BoxDecoration(color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2))),
          Row(children: [
            Container(width:44, height:44,
              decoration: BoxDecoration(gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.key_rounded, color: Colors.white, size:22)),
            const SizedBox(width:14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Save password?', style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.textPrimary, fontSize:16, fontWeight: FontWeight.w700)),
              Text(domain, style: GoogleFonts.inter(color: AppTheme.textHint, fontSize:12)),
            ])),
          ]),
          const SizedBox(height:16),
          Row(children: [
            Expanded(child: GestureDetector(onTap: () => Navigator.pop(context),
              child: Container(padding: const EdgeInsets.symmetric(vertical:13),
                decoration: BoxDecoration(color: AppTheme.bgElevated,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.divider)),
                child: Center(child: Text('Not now', style: GoogleFonts.inter(
                    color: AppTheme.textHint, fontSize:14)))))),
            const SizedBox(width:12),
            Expanded(child: GestureDetector(
              onTap: () async {
                await PasswordService.saveCredentials(domain, username, password);
                if (mounted) Navigator.pop(context);
                _snack('🔑 Password saved for $domain');
              },
              child: Container(padding: const EdgeInsets.symmetric(vertical:13),
                decoration: BoxDecoration(gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppTheme.glowShadow),
                child: Center(child: Text('Save', style: GoogleFonts.spaceGrotesk(
                    color: Colors.white, fontSize:14, fontWeight: FontWeight.w700)))))),
          ]),
        ]),
      ));
  }

  void _showAutofillSnack(String domain) {
    final creds = _savedCreds; if (creds == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.key_rounded, color: AppTheme.accentCyan, size:16),
        const SizedBox(width:8),
        Expanded(child: Text('Fill saved password for $domain?',
            style: GoogleFonts.inter(color: Colors.white, fontSize:12))),
      ]),
      backgroundColor: AppTheme.bgElevated,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds:6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      action: SnackBarAction(label:'Fill', textColor: AppTheme.accentCyan,
        onPressed: () async {
          final ok = await BiometricService.verify('Verify it\'s you to fill your saved password');
          if (!ok) return;
          final js = PasswordService.autofillJS(
              creds['username'] ?? '', creds['password'] ?? '');
          await _wvc?.evaluateJavascript(source: js);
          _snack('✅ Password filled');
        }),
    ));
  }

  // ── Reader Mode ──────────────────────────────────────────────────────────────
  static const String _readerJs =
    '(function(){'
    'try{'
    'var sel=["article","[role=main]","main",".article-content",".post-content",'
    '".entry-content",".story-body",".article-body",".post-body"];'
    'var best=null,bestSc=0;'
    'for(var i=0;i<sel.length;i++){'
    'var el=document.querySelector(sel[i]);'
    'if(el){var sc=el.innerText.trim().length;if(sc>bestSc&&sc>300){bestSc=sc;best=el;}}}'
    'if(!best){var divs=document.querySelectorAll("div,section");'
    'for(var i=0;i<divs.length;i++){var el=divs[i],ps=el.querySelectorAll("p"),sc=0;'
    'for(var j=0;j<ps.length;j++)sc+=(ps[j].innerText||"").length;'
    'if(sc>bestSc&&sc<100000){bestSc=sc;best=el;}}}'
    'if(!best)return JSON.stringify({error:"No article found"});'
    'var title=(document.querySelector("h1")||{}).innerText||document.title||"Article";'
    'var clone=best.cloneNode(true);'
    'var rm=clone.querySelectorAll("script,style,iframe,noscript,.ad,.ads,nav,.sidebar");'
    'for(var i=0;i<rm.length;i++){if(rm[i].parentNode)rm[i].parentNode.removeChild(rm[i]);}'
    'var words=(best.innerText||"").trim().split(/\s+/).length;'
    'return JSON.stringify({title:title.trim(),html:clone.innerHTML,'
    'wordCount:words,readTime:Math.max(1,Math.ceil(words/200))});'
    '}catch(e){return JSON.stringify({error:e.message});}})()';

  Future<void> _toggleReaderMode() async {
    if (_readerMode) {
      setState(() => _readerMode = false);
      if (_readerOriginalUrl != null) {
        _wvc?.loadUrl(urlRequest: URLRequest(url: WebUri(_readerOriginalUrl!)));
        _readerOriginalUrl = null;
      }
      return;
    }
    _snack('⏳ Extracting article…');
    final result = await _wvc?.evaluateJavascript(source: _readerJs);
    if (result == null) { _snack('Could not extract article'); return; }
    try {
      final data = jsonDecode(result.toString()) as Map<String,dynamic>;
      if (data.containsKey('error')) { _snack('Reader Mode: ${data["error"]}'); return; }
      final title     = (data['title'] as String?) ?? _pageTitle;
      final html      = (data['html']  as String?) ?? '';
      final wordCount = (data['wordCount'] as int?) ?? 0;
      final readTime  = (data['readTime']  as int?) ?? 1;
      if (html.isEmpty) { _snack('No article content found'); return; }
      _readerOriginalUrl = _currentUrl;
      setState(() => _readerMode = true);
      final page = _buildReaderHtml(title, html, wordCount, readTime);
      await _wvc?.loadData(data: page, mimeType: 'text/html', encoding: 'utf-8');
    } catch (e) { _snack('Reader Mode error: $e'); }
  }

  String _buildReaderHtml(String title, String html, int words, int mins) {
    final themes = {
      'dark':  {'bg':'#07101E','text':'#F1F5F9','card':'#111827','muted':'#94A3B8','border':'#1E293B','link':'#00D4FF'},
      'light': {'bg':'#FAFAFA','text':'#1A1A2E','card':'#FFFFFF','muted':'#64748B','border':'#E2E8F0','link':'#0052CC'},
      'sepia': {'bg':'#F4ECD8','text':'#4A3728','card':'#EDE0C4','muted':'#7A5C44','border':'#D4B896','link':'#C0392B'},
    };
    final t = themes[_readerTheme] ?? themes['dark']!;
    final fs = _readerFontSize.toInt();
    final esc = title.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
    return '<!DOCTYPE html><html><head><meta charset="UTF-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=5">'
        '<style>*{box-sizing:border-box;margin:0;padding:0}'
        'body{background:${t['bg']};color:${t['text']};font-family:Georgia,serif;'
        'font-size:${fs}px;line-height:1.85;max-width:720px;margin:0 auto;padding:28px 20px 120px}'
        '.hdr{margin-bottom:28px;padding-bottom:20px;border-bottom:2px solid ${t['border']}}'
        '.ttl{font-size:1.75em;font-weight:700;line-height:1.3;margin-bottom:12px}'
        '.meta{font-size:13px;color:${t['muted']};font-family:sans-serif;display:flex;gap:12px;flex-wrap:wrap}'
        '.badge{background:rgba(0,212,255,.12);color:#00D4FF;padding:3px 12px;'
        'border-radius:20px;font-weight:700;border:1px solid rgba(0,212,255,.2);font-size:11px}'
        'h1,h2,h3{margin:1.5em 0 .5em;line-height:1.3}p{margin:1em 0}'
        'a{color:${t['link']}}img{max-width:100%;height:auto;border-radius:10px;margin:1em 0}'
        'blockquote{border-left:3px solid #00D4FF;padding:12px 20px;margin:1.5em 0;'
        'background:rgba(0,212,255,.05);border-radius:0 10px 10px 0;font-style:italic}'
        'pre{background:${t['card']};border:1px solid ${t['border']};border-radius:10px;'
        'padding:16px;overflow-x:auto}code{font-family:monospace;background:${t['card']};'
        'padding:2px 6px;border-radius:5px}ul,ol{padding-left:1.8em;margin:1em 0}'
        'hr{border:none;border-top:1px solid ${t['border']};margin:2em 0}</style>'
        '</head><body><div class="hdr"><div class="ttl">$esc</div>'
        '<div class="meta"><span class="badge">📖 $mins min read</span>'
        '<span>$words words</span></div></div>$html</body></html>';
  }

  Widget _buildReaderToolbar() {
    if (!_readerMode) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom+4,
          top:8, left:14, right:14),
      decoration: BoxDecoration(color: AppTheme.bgCard,
          border: Border(top: BorderSide(color: AppTheme.warning.withOpacity(0.5), width:1.5))),
      child: Row(children: [
        Container(padding: const EdgeInsets.symmetric(horizontal:8, vertical:4),
          decoration: BoxDecoration(color: AppTheme.warning.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.warning.withOpacity(0.4))),
          child: Text('READER', style: GoogleFonts.spaceGrotesk(
              color: AppTheme.warning, fontSize:9, fontWeight: FontWeight.w800))),
        const SizedBox(width:10),
        _rBtn(Icons.text_decrease_rounded, () async {
          if (_readerFontSize > 12) { _readerFontSize -= 2;
            await _wvc?.evaluateJavascript(
                source: "document.body.style.fontSize='${_readerFontSize.toInt()}px'");
            if (mounted) setState((){});
          }
        }),
        Padding(padding: const EdgeInsets.symmetric(horizontal:5),
          child: Text('${_readerFontSize.toInt()}px',
              style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize:10))),
        _rBtn(Icons.text_increase_rounded, () async {
          if (_readerFontSize < 28) { _readerFontSize += 2;
            await _wvc?.evaluateJavascript(
                source: "document.body.style.fontSize='${_readerFontSize.toInt()}px'");
            if (mounted) setState((){});
          }
        }),
        const Spacer(),
        for (final e in [['dark','🌙'],['light','☀️'],['sepia','📜']])
          GestureDetector(
            onTap: () { setState(() => _readerTheme = e[0]);
              final url = _readerOriginalUrl; _toggleReaderMode().then((_) {
                _readerOriginalUrl = url; _toggleReaderMode(); }); },
            child: Container(width:30, height:30,
              margin: const EdgeInsets.only(left:4),
              decoration: BoxDecoration(
                  color: _readerTheme == e[0]
                      ? AppTheme.warning.withOpacity(0.15) : AppTheme.bgElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _readerTheme == e[0]
                      ? AppTheme.warning : AppTheme.divider)),
              child: Center(child: Text(e[1], style: const TextStyle(fontSize:13))))),
        const SizedBox(width:8),
        GestureDetector(onTap: _toggleReaderMode,
          child: Container(width:30, height:30,
            decoration: BoxDecoration(color: AppTheme.danger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.danger.withOpacity(0.3))),
            child: const Icon(Icons.close_rounded, color: AppTheme.danger, size:15))),
      ]),
    );
  }

  Widget _rBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(width:28, height:28,
      decoration: BoxDecoration(color: AppTheme.bgElevated,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: AppTheme.divider)),
      child: Icon(icon, color: AppTheme.textSecondary, size:13)));

  // ── Find in page ───────────────────────────────────────────────────────────────
  // ── NOVA Shield malware block page ───────────────────────────────────────
  String _buildBlockPage(String domain, String type) {
    return '''<!DOCTYPE html><html><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:#07101E;color:#F1F5F9;font-family:-apple-system,sans-serif;
     display:flex;flex-direction:column;align-items:center;justify-content:center;
     min-height:100vh;padding:32px;text-align:center;gap:16px}
.icon{width:80px;height:80px;background:rgba(255,23,68,.15);border-radius:24px;
      display:flex;align-items:center;justify-content:center;font-size:40px;
      border:2px solid rgba(255,23,68,.4);box-shadow:0 0 40px rgba(255,23,68,.2)}
h1{font-size:22px;font-weight:800;color:#FF5252;letter-spacing:-.3px}
.sub{font-size:13px;color:#94A3B8;max-width:300px;line-height:1.65}
.domain{font-family:monospace;background:#111827;padding:10px 18px;
        border-radius:10px;color:#FF5252;font-size:12px;
        border:1px solid rgba(255,23,68,.2);word-break:break-all}
.back{color:#00D4FF;background:#1E293B;padding:14px 32px;border-radius:14px;
      border:1px solid rgba(0,212,255,.3);font-size:14px;font-weight:700;
      text-decoration:none;display:inline-block}
.badge{background:rgba(255,23,68,.1);border:1px solid rgba(255,23,68,.3);
       color:#FF5252;padding:5px 14px;border-radius:20px;font-size:10px;
       font-weight:800;letter-spacing:1px}
.cf{font-size:11px;color:#475569;margin-top:4px}
</style></head><body>
<div class="icon">🛑</div>
<span class="badge">NOVA SHIELD BLOCKED</span>
<h1>Dangerous Site Blocked</h1>
<div class="domain">''' + domain + r'''</div>
<p class="sub">NOVA Shield detected this site as <strong style="color:#FF5252">''' + type + r'''</strong>
using Cloudflare threat intelligence. Your connection is protected.</p>
<p class="cf">Powered by Cloudflare DNS-over-HTTPS · NOVA Shield v2.0</p>
<a class="back" href="javascript:history.back()">← Go Back to Safety</a>
</body></html>''';
  }

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
