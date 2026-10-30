// lib/features/xcoder/screens/xcoder_preview_screen.dart
//
// Live preview of a web project served from the phone (127.0.0.1). Shows the
// page's console, switches between phone / tablet / desktop widths, reloads
// automatically when files are saved, and can open the page in the NOVA X
// browser (with Dev Tools).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../browser/screens/browser_view.dart';
import '../widgets/xcoder_panels.dart';
import '../widgets/xcoder_ui.dart';

class XPreviewScreen extends StatefulWidget {
  const XPreviewScreen({super.key, required this.url, required this.title, required this.reloads, required this.onConsole});

  final String url;
  final String title;

  /// Fires when a project file is saved (auto-reload).
  final Stream<void> reloads;
  final void Function(String level, String text) onConsole;

  @override
  State<XPreviewScreen> createState() => _XPreviewScreenState();
}

enum _Device { phone, tablet, desktop }

class _XPreviewScreenState extends State<XPreviewScreen> {
  InAppWebViewController? _wvc;
  final List<OutputLine> _console = [];
  StreamSubscription<void>? _sub;
  bool _showConsole = false;
  bool _autoReload = true;
  _Device _device = _Device.phone;
  double _progress = 0;
  String _url = '';

  static const _desktopUA =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

  @override
  void initState() {
    super.initState();
    _url = widget.url;
    _sub = widget.reloads.listen((_) {
      if (_autoReload) _wvc?.reload();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  int get _errors => _console.where((l) => l.level == 'error').length;

  void _log(String level, String text) {
    setState(() {
      _console.add(OutputLine(level, text, DateTime.now()));
      if (_console.length > 500) _console.removeAt(0);
    });
    widget.onConsole(level, text);
  }

  Future<void> _setDevice(_Device d) async {
    setState(() => _device = d);
    await _wvc?.setSettings(
        settings: InAppWebViewSettings(
      userAgent: d == _Device.desktop ? _desktopUA : '',
      preferredContentMode: d == _Device.desktop ? UserPreferredContentMode.DESKTOP : UserPreferredContentMode.MOBILE,
      useWideViewPort: true,
      loadWithOverviewMode: d == _Device.desktop,
    ));
    await _wvc?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final frameWidth = switch (_device) {
      _Device.phone => w,
      _Device.tablet => w < 820 ? w : 820.0,
      _Device.desktop => w,
    };
    return Scaffold(
      backgroundColor: XC.bg,
      appBar: AppBar(
        backgroundColor: XC.bar,
        elevation: 0,
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title, style: XC.ui(15, weight: FontWeight.w700)),
          Text(_url.replaceFirst(RegExp(r'^http://127\.0\.0\.1:\d+'), 'localhost'),
              style: XC.mono(11, color: XC.faint), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
        actions: [
          XIconBtn(Icons.refresh_rounded, tooltip: 'Reload', onTap: () => _wvc?.reload()),
          XIconBtn(Icons.terminal_rounded,
              tooltip: 'Console', onTap: () => setState(() => _showConsole = !_showConsole), badge: _errors > 0 ? '$_errors' : null),
          PopupMenuButton<String>(
            color: XC.side,
            icon: const Icon(Icons.more_vert_rounded, color: XC.dim),
            onSelected: (v) async {
              switch (v) {
                case 'phone':
                  _setDevice(_Device.phone);
                case 'tablet':
                  _setDevice(_Device.tablet);
                case 'desktop':
                  _setDevice(_Device.desktop);
                case 'auto':
                  setState(() => _autoReload = !_autoReload);
                case 'browser':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => BrowserView(initialQuery: _url)));
                case 'hard':
                  await InAppWebViewController.clearAllCache();
                  await _wvc?.reload();
              }
            },
            itemBuilder: (_) => [
              _mi('phone', Icons.smartphone_rounded, 'Phone', _device == _Device.phone),
              _mi('tablet', Icons.tablet_android_rounded, 'Tablet width', _device == _Device.tablet),
              _mi('desktop', Icons.desktop_windows_outlined, 'Desktop site', _device == _Device.desktop),
              const PopupMenuDivider(),
              _mi('auto', Icons.autorenew_rounded, 'Reload when files are saved', _autoReload),
              _mi('hard', Icons.cleaning_services_outlined, 'Clear cache & reload', false),
              _mi('browser', Icons.open_in_browser_rounded, 'Open in NOVA X browser (Dev Tools)', false),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _progress < 1
              ? LinearProgressIndicator(value: _progress, minHeight: 2, color: XC.accent, backgroundColor: Colors.transparent)
              : const SizedBox(height: 2),
        ),
      ),
      body: Column(children: [
        Expanded(
          child: Center(
            child: SizedBox(
              width: frameWidth,
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  cacheEnabled: false,
                  allowFileAccess: false,
                  allowContentAccess: false,
                  mediaPlaybackRequiresUserGesture: false,
                  supportZoom: true,
                  builtInZoomControls: true,
                  displayZoomControls: false,
                  useWideViewPort: true,
                  useShouldOverrideUrlLoading: true,
                ),
                onWebViewCreated: (c) {
                  _wvc = c;
                  c.addJavaScriptHandler(
                    handlerName: 'xcPreview',
                    callback: (a) {
                      if (a.isNotEmpty && a.first is Map) {
                        final m = a.first as Map;
                        _log(m['level']?.toString() ?? 'log', m['text']?.toString() ?? '');
                      }
                      return null;
                    },
                  );
                },
                onProgressChanged: (_, p) => setState(() => _progress = p / 100),
                onLoadStart: (_, u) => setState(() => _url = u?.toString() ?? _url),
                onReceivedError: (_, req, err) {
                  if (req.isForMainFrame == true) _log('error', 'Failed to load ${req.url}: ${err.description}');
                },
                onReceivedHttpError: (_, req, res) {
                  _log('warn', '${res.statusCode} ${req.url.toString().replaceFirst(RegExp(r'^http://127\.0\.0\.1:\d+/'), '')}');
                },
                // Links to the internet open in the NOVA X browser, not inside the preview.
                shouldOverrideUrlLoading: (c, a) async {
                  final u = a.request.url?.toString() ?? '';
                  if (u.startsWith('http://127.0.0.1:') || u.startsWith('about:') || u.startsWith('data:') || u.startsWith('blob:')) {
                    return NavigationActionPolicy.ALLOW;
                  }
                  if (mounted && (u.startsWith('http://') || u.startsWith('https://'))) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => BrowserView(initialQuery: u)));
                  }
                  return NavigationActionPolicy.CANCEL;
                },
              ),
            ),
          ),
        ),
        if (_showConsole)
          Container(
            height: 220,
            decoration: const BoxDecoration(color: XC.side, border: Border(top: BorderSide(color: XC.border))),
            child: OutputView(lines: _console, onClear: () => setState(_console.clear)),
          ),
      ]),
    );
  }

  PopupMenuItem<String> _mi(String v, IconData i, String label, bool checked) => PopupMenuItem(
        value: v,
        child: Row(children: [
          Icon(i, size: 18, color: checked ? XC.accent : XC.dim),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: XC.ui(13.5, color: checked ? XC.accent : XC.text))),
          if (checked) const Icon(Icons.check_rounded, size: 16, color: XC.accent),
        ]),
      );
}
