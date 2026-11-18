// lib/features/devhub/devhub_screen.dart
//
// NOVA X Developer Hub (3.14.0) — the Android version of the Windows
// Developer Hub: same title, sections, icons, cards and colours.
//
//   Overview          inspect any site (NOVA DevTools, desktop view), open a
//                     LAN dev server, recent inspections, developer tools,
//                     toolbox, gestures, docs
//   Request timeline  real DNS / connect / TLS / first byte / download per
//                     redirect hop, certificate, HTTP/2, caching, security
//                     headers, CORS, cookies, body, cURL
//   DNS & domain      every record type from two resolvers, compared, plus
//                     RDAP registration (registrar, expiry, DNSSEC)
//   Toolbox           14 offline developer utilities
//   App Builder       Windows only (shows the Windows card)
//
// Phones: tab strip under the app bar. Tablets (> 840 dp): left menu, as on
// Windows. Requests go straight from the phone to the site, only when the
// user taps Run — no background work, no port scanning.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/widgets/windows_download_card.dart';
import '../browser/screens/browser_view.dart';
import '../cyber/screens/cyber_screen.dart';
import '../cyber/ui/cyber_palette.dart';
import '../cyber/ui/cyber_widgets.dart' show CodeBlock, Metric, Panel, kMono;
import '../devguide/developer_guide_screen.dart';
import '../devtools/screens/code_editor_screen.dart';
import '../network/screens/nova_network_screen.dart';
import '../pro/api_studio.dart';
import '../pro/rules_page.dart';
import 'devhub_net.dart';
import 'devhub_toolbox.dart';
import 'devhub_tools.dart';

enum DevHubView { overview, timeline, dns, toolbox, builder }

class DevHubScreen extends StatefulWidget {
  const DevHubScreen({super.key, this.initialView = DevHubView.overview, this.initialUrl = ''});
  final DevHubView initialView;

  /// Filled into the Inspect box (e.g. the page the user came from).
  final String initialUrl;

  @override
  State<DevHubScreen> createState() => _DevHubScreenState();

  /// Address parsing used by Inspect / timeline (for tests).
  @visibleForTesting
  static String? urlFromForTest(String input) => _DevHubScreenState.urlFrom(input);
}

class _DevHubScreenState extends State<DevHubScreen> {
  static const String _recentKey = 'nova_devhub_recent_v1';
  static const int _maxRecent = 20;

  late DevHubView _view = widget.initialView == DevHubView.builder ? DevHubView.overview : widget.initialView;
  String _toolboxStart = 'json';

  // Overview
  final TextEditingController _inspect = TextEditingController();
  final TextEditingController _lan = TextEditingController();
  List<String> _recent = [];

  // Timeline
  final TextEditingController _tlUrl = TextEditingController();
  String _tlMethod = 'GET';
  bool _tlFollow = true;
  bool _tlRunning = false;
  TimelineResult? _tl;
  String? _tlError;
  int _tlHop = 0;

  // DNS
  final TextEditingController _dnsName = TextEditingController();
  bool _dnsRunning = false;
  DnsAnswer? _ra, _rb;
  DomainInfo? _rdap;
  String? _rdapError;
  String? _dnsError;

  static const String _appBuilderReason = 'On Windows, App Builder turns a site you own into a signed Android app (.apk / .aab).';
  static const String _reconReason = 'On Windows, Recon Notebook keeps scope, passive recon and findings for your security reviews.';

  @override
  void initState() {
    super.initState();
    _inspect.text = widget.initialUrl;
    _loadRecent();
    if (widget.initialView == DevHubView.builder) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showBuilder());
    }
  }

  @override
  void dispose() {
    _inspect.dispose();
    _lan.dispose();
    _tlUrl.dispose();
    _dnsName.dispose();
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));

  void _showBuilder() => WindowsOnly.show(context, title: 'App Builder', reason: _appBuilderReason);

  void _select(DevHubView v) {
    if (v == DevHubView.builder) {
      _showBuilder();
      return;
    }
    setState(() => _view = v);
  }

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  // ── Recent ────────────────────────────────────────────────────────────────
  Future<void> _loadRecent() async {
    try {
      final p = await SharedPreferences.getInstance();
      final list = p.getStringList(_recentKey) ?? const [];
      if (mounted) setState(() => _recent = list);
    } catch (_) {}
  }

  Future<void> _remember(String url) async {
    _recent = [url, ..._recent.where((x) => x != url)].take(_maxRecent).toList();
    if (mounted) setState(() {});
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_recentKey, _recent);
    } catch (_) {}
  }

  Future<void> _forget(String url) async {
    setState(() => _recent = _recent.where((x) => x != url).toList());
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_recentKey, _recent);
    } catch (_) {}
  }

  // ── Opening sites ─────────────────────────────────────────────────────────
  static String? urlFrom(String input) {
    final t = input.trim();
    if (t.isEmpty) return null;
    if (t.startsWith('http://') || t.startsWith('https://')) return t;
    if (RegExp(r'^(localhost|127\.0\.0\.1)(:\d+)?(/.*)?$').hasMatch(t) || RegExp(r'^\d+\.\d+\.\d+\.\d+(:\d+)?(/.*)?$').hasMatch(t)) {
      return 'http://$t';
    }
    if (!t.contains(' ') && t.contains('.')) return 'https://$t';
    return null;
  }

  void _open(String url, {bool devtools = true, bool desktop = false}) {
    unawaited(_remember(url));
    _push(BrowserView(initialQuery: url, autoOpenDevTools: devtools, desktopSite: desktop));
  }

  void _inspectNow({bool desktop = false}) {
    final url = urlFrom(_inspect.text);
    if (url == null) {
      _snack('Enter a site, e.g. example.com or https://site.com/app.js');
      return;
    }
    _open(url, desktop: desktop);
  }

  void _openLan() {
    final t = _lan.text.trim().replaceFirst(RegExp(r'^https?://'), '');
    if (!RegExp(r'^\d{1,3}(\.\d{1,3}){3}(:\d{2,5})?(/.*)?$').hasMatch(t)) {
      _snack('Enter your computer\'s address and port, e.g. 192.168.1.20:5173');
      return;
    }
    _open('http://$t');
  }

  // ── Timeline ──────────────────────────────────────────────────────────────
  Future<void> _runTimeline([String? url]) async {
    if (url != null && url.trim().isNotEmpty) _tlUrl.text = url;
    final u = urlFrom(_tlUrl.text);
    final parsed = u == null ? null : Uri.tryParse(u);
    setState(() => _view = DevHubView.timeline);
    if (parsed == null || parsed.host.isEmpty) {
      if (url == null) setState(() => _tlError = 'Enter an address, e.g. example.com/api/health');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _tlRunning = true;
      _tlError = null;
      _tl = null;
      _tlHop = 0;
    });
    try {
      final r = await RequestTimeline.run(parsed, method: _tlMethod, follow: _tlFollow);
      if (!mounted) return;
      setState(() {
        _tl = r;
        _tlHop = r.hops.length - 1;
      });
    } catch (e) {
      if (mounted) setState(() => _tlError = '$e');
    } finally {
      if (mounted) setState(() => _tlRunning = false);
    }
  }

  // ── DNS ───────────────────────────────────────────────────────────────────
  Future<void> _runDns([String? name]) async {
    if (name != null && name.trim().isNotEmpty) _dnsName.text = name;
    var n = _dnsName.text.trim().toLowerCase();
    final asUrl = Uri.tryParse(n.contains('://') ? n : 'https://$n');
    if (asUrl != null && asUrl.host.isNotEmpty) n = asUrl.host;
    setState(() => _view = DevHubView.dns);
    if (n.isEmpty || !n.contains('.')) {
      if (name == null) setState(() => _dnsError = 'Enter a domain name, e.g. example.com');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _dnsRunning = true;
      _dnsError = null;
      _rdapError = null;
      _ra = _rb = null;
      _rdap = null;
    });
    final results = await Future.wait<Object?>([
      DevDns.lookup(n).then<Object?>((v) => v, onError: (Object e) => e),
      DevDns.lookup(n, google: true).then<Object?>((v) => v, onError: (Object e) => e),
      DevRdap.lookup(n).then<Object?>((v) => v, onError: (Object e) => e),
    ]);
    if (!mounted) return;
    setState(() {
      _dnsRunning = false;
      _ra = results[0] is DnsAnswer ? results[0] as DnsAnswer : null;
      _rb = results[1] is DnsAnswer ? results[1] as DnsAnswer : null;
      if (_ra == null && _rb == null) _dnsError = 'DNS lookups failed. Check your internet connection.';
      if (results[2] is DomainInfo) {
        _rdap = results[2] as DomainInfo;
      } else {
        _rdapError = results[2] == null ? 'No registration data published for this domain (RDAP).' : 'Registration lookup failed.';
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  static const _items = <(DevHubView, IconData, String)>[
    (DevHubView.overview, Icons.dashboard_outlined, 'Overview'),
    (DevHubView.timeline, Icons.waterfall_chart_rounded, 'Request timeline'),
    (DevHubView.dns, Icons.dns_outlined, 'DNS & domain'),
    (DevHubView.toolbox, Icons.handyman_outlined, 'Toolbox'),
    (DevHubView.builder, Icons.android_rounded, 'App Builder'),
  ];

  @override
  Widget build(BuildContext context) {
    return NovaThemed(
      child: Builder(builder: (context) {
        final p = NovaThemeScope.of(context);
        final wide = MediaQuery.of(context).size.width > 840;
        final body = switch (_view) {
          DevHubView.overview => _overview(p),
          DevHubView.timeline => _timelineView(p),
          DevHubView.dns => _dnsView(p),
          DevHubView.toolbox => wide ? DevToolbox(key: ValueKey('toolbox-$_toolboxStart'), initial: _toolboxStart) : const DevToolGrid(),
          DevHubView.builder => const SizedBox.shrink(),
        };
        return Scaffold(
          backgroundColor: p.bg,
          appBar: AppBar(
            backgroundColor: p.bg,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            titleSpacing: 0,
            iconTheme: IconThemeData(color: p.textMuted),
            title: Row(children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: const Color(0xFF22C55E).withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.developer_mode_rounded, size: 18, color: Color(0xFF22C55E)),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('Developer Hub', style: p.ui(size: 16, weight: FontWeight.w800)),
                Text('Build · inspect · debug', style: p.ui(size: 11, color: p.textFaint)),
              ]),
            ]),
            bottom: wide ? null : PreferredSize(preferredSize: const Size.fromHeight(48), child: _tabStrip(p)),
          ),
          body: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _rail(p),
                  VerticalDivider(width: 1, color: p.border),
                  Expanded(child: body),
                ])
              : body,
        );
      }),
    );
  }

  Widget _tabStrip(NovaPalette p) => SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          children: [
            for (final (v, icon, label) in _items)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  avatar: Icon(icon, size: 16, color: _view == v ? p.accent : p.textMuted),
                  label: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(label, style: p.ui(size: 12.5, weight: FontWeight.w600, color: _view == v ? p.text : p.textMuted)),
                    if (v == DevHubView.builder) ...[const SizedBox(width: 6), const WindowsBadge()],
                  ]),
                  selected: _view == v,
                  showCheckmark: false,
                  selectedColor: p.accentSoft,
                  backgroundColor: p.surface,
                  side: BorderSide(color: _view == v ? p.accent.withValues(alpha: 0.5) : p.border),
                  onSelected: (_) => _select(v),
                ),
              ),
          ],
        ),
      );

  Widget _rail(NovaPalette p) => Container(
        width: 220,
        color: p.surfaceAlt,
        child: ListView(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8), children: [
          for (final (v, icon, label) in _items)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _select(v),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  color: _view == v ? p.surface : null,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _view == v ? p.border : Colors.transparent),
                ),
                child: Row(children: [
                  Icon(icon, size: 18, color: _view == v ? p.accent : p.textMuted),
                  const SizedBox(width: 10),
                  Expanded(child: Text(label, style: p.ui(size: 13, weight: _view == v ? FontWeight.w700 : FontWeight.w500))),
                  if (v == DevHubView.builder) const WindowsBadge(),
                ]),
              ),
            ),
        ]),
      );

  Widget _pageHeader(NovaPalette p, String title, String subtitle) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: p.title(size: 20)),
          const SizedBox(height: 4),
          Text(subtitle, style: p.ui(size: 13, color: p.textMuted, height: 1.4)),
        ]),
      );

  Widget _scroll(Widget child) => SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), child: child);

  Widget _ghost(NovaPalette p, IconData icon, String label, VoidCallback onTap, {bool windows = false}) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), visualDensity: VisualDensity.compact),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label, style: p.ui(size: 12.5, weight: FontWeight.w600)),
          if (windows) ...[const SizedBox(width: 6), const WindowsBadge()],
        ]),
      );

  // ── Overview ──────────────────────────────────────────────────────────────
  Widget _overview(NovaPalette p) {
    return _scroll(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _pageHeader(p, 'Developer Hub', 'Inspect any site, measure requests, check DNS, and use everyday dev tools.'),
      _inspectPanel(p),
      const SizedBox(height: 16),
      _lanPanel(p),
      const SizedBox(height: 16),
      _toolsPanel(p),
      const SizedBox(height: 16),
      _toolboxStrip(p),
      const SizedBox(height: 16),
      _gesturesPanel(p),
      const SizedBox(height: 16),
      _docsPanel(p),
    ]));
  }

  Widget _inspectPanel(NovaPalette p) {
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _inspect,
          keyboardType: TextInputType.url,
          autocorrect: false,
          style: kMono.copyWith(fontSize: 14, color: p.text),
          onSubmitted: (_) => _inspectNow(),
          decoration: InputDecoration(
            hintText: 'example.com · https://site.com/app.js',
            hintStyle: kMono.copyWith(fontSize: 13.5, color: p.textFaint),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 14, right: 8),
              child: Text('>_', style: kMono.copyWith(fontSize: 15, color: p.accent, fontWeight: FontWeight.w800)),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () => _inspectNow(),
          icon: const Icon(Icons.developer_mode_rounded, size: 18),
          label: const Text('Inspect'),
        ),
        const SizedBox(height: 12),
        Text('QUICK ACTIONS', style: p.ui(size: 10.5, color: p.textFaint, weight: FontWeight.w700, letterSpacing: 0.8)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _ghost(p, Icons.desktop_windows_outlined, 'Desktop view + DevTools', () => _inspectNow(desktop: true)),
          _ghost(p, Icons.waterfall_chart_rounded, 'Request timeline', () => _runTimeline(_inspect.text)),
          _ghost(p, Icons.dns_outlined, 'DNS & domain', () => _runDns(_inspect.text)),
          _ghost(p, Icons.security_rounded, 'Security scan', () => _push(CyberScreen(initialUrl: urlFrom(_inspect.text) ?? ''))),
          _ghost(p, Icons.android_rounded, 'Build Android app', _showBuilder, windows: true),
        ]),
        if (_recent.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('RECENT INSPECTIONS', style: p.ui(size: 10.5, color: p.textFaint, weight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final r in _recent)
              InputChip(
                label: Text(r.replaceFirst(RegExp(r'^https?://'), ''),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: kMono.copyWith(fontSize: 12, color: p.text)),
                onPressed: () => _open(r),
                onDeleted: () => _forget(r),
                deleteIconColor: p.textFaint,
                backgroundColor: p.surfaceAlt,
                tooltip: 'Inspect $r',
                visualDensity: VisualDensity.compact,
              ),
          ]),
        ],
      ]),
    );
  }

  Widget _lanPanel(NovaPalette p) {
    return Panel(
      title: 'Open a LAN dev server',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Test the site you\'re building on your computer: run your dev server with --host, then enter the computer\'s address and port.',
            style: p.ui(size: 12.5, color: p.textMuted, height: 1.4)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _lan,
              keyboardType: TextInputType.url,
              autocorrect: false,
              style: kMono.copyWith(fontSize: 13.5, color: p.text),
              onSubmitted: (_) => _openLan(),
              decoration: InputDecoration(
                hintText: '192.168.1.20:5173',
                hintStyle: kMono.copyWith(fontSize: 13.5, color: p.textFaint),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _openLan, child: const Text('Open')),
        ]),
      ]),
    );
  }

  Widget _toolsPanel(NovaPalette p) {
    Widget tile(IconData icon, String title, String sub, VoidCallback onTap, {Color? tint, bool windows = false}) => InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: (tint ?? p.accent).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 18, color: tint ?? p.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: p.ui(size: 13, weight: FontWeight.w700))),
                    if (windows) ...[const SizedBox(width: 6), const WindowsBadge()],
                  ]),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: p.ui(size: 11.5, color: p.textFaint)),
                ]),
              ),
            ]),
          ),
        );
    final tiles = [
      tile(Icons.code_rounded, 'X Coder', 'Editor, terminal and preview', () => _push(const CodeEditorScreen(sharedWorkspace: true))),
      tile(Icons.api_rounded, 'API Studio', 'HTTP client, variables, cURL', () => _push(const ApiStudioScreen()), tint: const Color(0xFF8B5CF6)),
      tile(Icons.security_rounded, 'NOVA Cyber', 'Website & code security', () => _push(const CyberScreen()), tint: const Color(0xFF6366F1)),
      tile(Icons.tune_rounded, 'Rewrite Rules', 'Redirect, block, inject CSS/JS', () => _push(const RulesScreen()), tint: const Color(0xFFF59E0B)),
      tile(Icons.speed_rounded, 'NOVA Network', 'Speed, latency, jitter', () => _push(const NovaNetworkScreen()), tint: const Color(0xFF10B981)),
      tile(Icons.menu_book_rounded, 'Developer Guide', 'How NOVA X dev tools work', () => _push(const DeveloperGuideScreen()),
          tint: const Color(0xFF64748B)),
      tile(Icons.travel_explore_rounded, 'Recon Notebook', 'Scope, notes and findings',
          () => WindowsOnly.show(context, title: 'Recon Notebook', reason: _reconReason),
          tint: const Color(0xFF0EA5E9), windows: true),
    ];
    return Panel(
      title: 'Developer tools',
      child: LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth > 520 ? 2 : 1;
        final w = (box.maxWidth - (cols - 1) * 8) / cols;
        return Wrap(spacing: 8, runSpacing: 8, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
      }),
    );
  }

  Widget _toolboxStrip(NovaPalette p) {
    final wide = MediaQuery.of(context).size.width > 840;
    return Panel(
      title: 'Toolbox',
      trailing: TextButton(onPressed: () => setState(() => _view = DevHubView.toolbox), child: const Text('All tools')),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in DevToolbox.tools)
          ActionChip(
            avatar: Icon(t.icon, size: 16, color: p.accent),
            backgroundColor: p.surfaceAlt,
            label: Text(t.name, style: p.ui(size: 12.5, weight: FontWeight.w600)),
            onPressed: () {
              if (wide) {
                setState(() {
                  _toolboxStart = t.id;
                  _view = DevHubView.toolbox;
                });
              } else {
                _push(DevToolPage(id: t.id));
              }
            },
          ),
      ]),
    );
  }

  Widget _gesturesPanel(NovaPalette p) {
    const items = [
      ('⋮ › Developer tools', 'Open NOVA DevTools for the page in the browser'),
      ('Drag the top bar', 'Resize the DevTools panel; ⤢ for full height'),
      ('⌖ then tap', 'Pick an element on the page to inspect it'),
      ('↻ in DevTools', 'Reload and capture every request from the start'),
      ('Swipe ← in Storage', 'Delete a local / session storage item'),
      ('Long-press evidence', 'Copy a NOVA Cyber finding\'s evidence'),
      ('Swipe a tab', 'Close it in the tab switcher'),
      ('Ctrl+Enter (keyboard)', 'Run JavaScript in the Console'),
    ];
    return Panel(
      title: 'Gestures & shortcuts',
      child: Column(children: [
        for (final (k, d) in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 150),
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(5), border: Border.all(color: p.borderStrong)),
                child: Text(k, style: kMono.copyWith(fontSize: 11.5, color: p.text)),
              ),
              Expanded(child: Text(d, style: p.ui(size: 12.5, color: p.textMuted))),
            ]),
          ),
      ]),
    );
  }

  Widget _docsPanel(NovaPalette p) {
    const docs = [
      ('MDN Web Docs', 'developer.mozilla.org', 'https://developer.mozilla.org/'),
      ('web.dev', 'Performance & best practices', 'https://web.dev/'),
      ('Can I use', 'Browser support tables', 'https://caniuse.com/'),
      ('DevDocs', 'All API docs in one place', 'https://devdocs.io/'),
      ('Flutter docs', 'docs.flutter.dev', 'https://docs.flutter.dev/'),
      ('pub.dev', 'Dart & Flutter packages', 'https://pub.dev/'),
      ('npm', 'JavaScript packages', 'https://www.npmjs.com/'),
      ('HTTP status codes', 'MDN reference', 'https://developer.mozilla.org/docs/Web/HTTP/Status'),
    ];
    return Panel(
      title: 'Docs & references',
      child: Column(children: [
        for (final (t, s, u) in docs)
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _push(BrowserView(initialQuery: u)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
              child: Row(children: [
                Icon(Icons.north_east_rounded, size: 14, color: p.accent),
                const SizedBox(width: 10),
                Text(t, style: p.ui(size: 13, weight: FontWeight.w600)),
                const SizedBox(width: 8),
                Expanded(child: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: p.ui(size: 12, color: p.textFaint))),
              ]),
            ),
          ),
      ]),
    );
  }

  // ── Timeline view ─────────────────────────────────────────────────────────
  Widget _timelineView(NovaPalette p) {
    return _scroll(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _pageHeader(p, 'Request timeline', 'Every phase measured from this phone: DNS, connect, TLS, waiting for the server, download — for each redirect.'),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _tlUrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            style: kMono.copyWith(fontSize: 13.5, color: p.text),
            onSubmitted: (_) => _runTimeline(),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'https://example.com/api/health',
              hintStyle: kMono.copyWith(fontSize: 13.5, color: p.textFaint),
              contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _tlMethod,
                  dropdownColor: p.surface,
                  style: kMono.copyWith(fontSize: 13, color: p.text, fontWeight: FontWeight.w700),
                  items: const [
                    DropdownMenuItem(value: 'GET', child: Text('GET')),
                    DropdownMenuItem(value: 'HEAD', child: Text('HEAD')),
                    DropdownMenuItem(value: 'OPTIONS', child: Text('OPTIONS')),
                  ],
                  onChanged: (v) => setState(() => _tlMethod = v ?? 'GET'),
                ),
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _tlRunning ? null : () => _runTimeline(),
              icon: _tlRunning
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.onAccent))
                  : const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text(_tlRunning ? 'Measuring…' : 'Run'),
            ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Switch(value: _tlFollow, onChanged: (v) => setState(() => _tlFollow = v)),
            const SizedBox(width: 6),
            Expanded(child: Text('Follow redirects (up to ${RequestTimeline.maxHops})', style: p.ui(size: 12.5, color: p.textMuted))),
          ]),
          if (urlFrom(_tlUrl.text) != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final u = Uri.parse(urlFrom(_tlUrl.text)!);
                  await Clipboard.setData(ClipboardData(text: RequestTimeline.curl(u, method: _tlMethod)));
                  _snack('cURL command copied');
                },
                icon: const Icon(Icons.terminal_rounded, size: 16),
                label: const Text('Copy as cURL'),
              ),
            ),
        ]),
      ),
      if (_tlError != null) ...[const SizedBox(height: 12), _errorBox(p, _tlError!)],
      if (_tl != null) ...[const SizedBox(height: 16), ..._timelineResult(p, _tl!)],
      if (_tl == null && !_tlRunning && _tlError == null) ...[const SizedBox(height: 16), _timelineHelp(p)],
    ]));
  }

  Widget _timelineHelp(NovaPalette p) => Panel(
        title: 'What you get',
        child: Text(
          '• A waterfall of DNS lookup, TCP connect, TLS handshake, waiting (time to first byte) and download for every hop\n'
          '• Status, IP address and the full response headers of each hop\n'
          '• The TLS certificate: issuer, validity, days left, and whether the phone trusts it\n'
          '• Whether the server offers HTTP/2\n'
          '• Caching, CORS and security headers explained, cookies missing Secure / HttpOnly / SameSite\n'
          '• The response body (JSON pretty-printed), sizes on the wire and after decompression',
          style: p.ui(size: 13, color: p.textMuted, height: 1.6),
        ),
      );

  static const _segColors = [Color(0xFF14B8A6), Color(0xFFF59E0B), Color(0xFF8B5CF6), Color(0xFF22C55E), Color(0xFF3B82F6)];
  static const _segNames = ['DNS', 'Connect', 'TLS', 'Waiting (TTFB)', 'Download'];

  String _ms(Duration? d) => d == null ? '—' : '${(d.inMicroseconds / 1000).toStringAsFixed(d.inMilliseconds < 10 ? 1 : 0)} ms';

  String _size(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  Color _statusColor(NovaPalette p, int? s) {
    if (s == null) return p.danger;
    if (s < 300) return p.success;
    if (s < 400) return p.accent;
    if (s < 500) return p.warning;
    return p.danger;
  }

  List<Widget> _timelineResult(NovaPalette p, TimelineResult r) {
    final last = r.last!;
    final total = r.hops.fold<Duration>(Duration.zero, (a, h) => a + h.total);
    final cert = r.hops.map((h) => h.cert).whereType<CertInfo>().lastOrNull;
    final hop = r.hops[_tlHop.clamp(0, r.hops.length - 1)];
    return [
      Panel(
        child: Wrap(spacing: 24, runSpacing: 14, children: [
          Metric(value: last.status == null ? 'Error' : '${last.status}', label: last.reason.isEmpty ? 'Final status' : last.reason,
              color: _statusColor(p, last.status)),
          Metric(value: _ms(total), label: 'Total time'),
          Metric(value: '${r.hops.length}', label: r.hops.length == 1 ? 'Request' : 'Requests'),
          Metric(value: _size(last.transferred), label: 'Transferred'),
          Metric(value: _size(last.body.length), label: 'Body (decoded)'),
          if (r.http2 != null) Metric(value: r.http2! ? 'Yes' : 'No', label: 'HTTP/2 offered', color: r.http2! ? p.success : p.warning),
          if (cert != null)
            Metric(
                value: cert.trusted ? '${cert.daysLeft()} d' : 'Untrusted',
                label: 'Certificate left',
                color: !cert.trusted || cert.daysLeft() < 14 ? p.danger : (cert.daysLeft() < 30 ? p.warning : p.success)),
        ]),
      ),
      const SizedBox(height: 16),
      _waterfall(p, r),
      const SizedBox(height: 16),
      ..._hopDetails(p, hop),
    ];
  }

  Widget _waterfall(NovaPalette p, TimelineResult r) {
    final maxUs = r.hops.map((h) => h.total.inMicroseconds).fold<int>(1, (a, b) => b > a ? b : a);
    return Panel(
      title: 'Waterfall',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 12, runSpacing: 6, children: [
          for (var i = 0; i < 5; i++)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: _segColors[i], borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 5),
              Text(_segNames[i], style: p.ui(size: 11.5, color: p.textMuted)),
            ]),
        ]),
        const SizedBox(height: 10),
        for (var i = 0; i < r.hops.length; i++) _waterfallRow(p, r.hops[i], i, maxUs),
      ]),
    );
  }

  Widget _waterfallRow(NovaPalette p, Hop h, int i, int maxUs) {
    final sel = i == _tlHop;
    final segs = [h.dns, h.connect, h.tls, h.ttfb, h.download];
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _tlHop = i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: sel ? p.accentSoft.withValues(alpha: 0.6) : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: sel ? p.accent.withValues(alpha: 0.5) : Colors.transparent),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            SizedBox(
              width: 40,
              child: Text(h.status == null ? 'ERR' : '${h.status}',
                  style: kMono.copyWith(fontSize: 13, fontWeight: FontWeight.w800, color: _statusColor(p, h.status))),
            ),
            Expanded(child: Text('${h.method} ${h.url}', maxLines: 1, overflow: TextOverflow.ellipsis, style: kMono.copyWith(fontSize: 12, color: p.text))),
            const SizedBox(width: 8),
            Text(_ms(h.total), style: kMono.copyWith(fontSize: 12, color: p.textMuted)),
          ]),
          const SizedBox(height: 6),
          LayoutBuilder(builder: (context, box) {
            return Row(children: [
              for (var s = 0; s < segs.length; s++)
                if (segs[s] != null && segs[s]!.inMicroseconds > 0)
                  Tooltip(
                    message: '${_segNames[s]}: ${_ms(segs[s])}',
                    child: Container(
                      width: (box.maxWidth * segs[s]!.inMicroseconds / maxUs - 1).clamp(2.0, box.maxWidth),
                      height: 12,
                      margin: const EdgeInsets.only(right: 1),
                      decoration: BoxDecoration(color: _segColors[s], borderRadius: BorderRadius.circular(3)),
                    ),
                  ),
            ]);
          }),
        ]),
      ),
    );
  }

  List<Widget> _hopDetails(NovaPalette p, Hop h) {
    final widgets = <Widget>[];
    if (h.error != null) widgets.addAll([_errorBox(p, h.error!), const SizedBox(height: 16)]);

    widgets.add(Panel(
      title: 'Timing',
      child: Column(children: [
        for (var s = 0; s < 5; s++) _kv(p, _segNames[s], _ms([h.dns, h.connect, h.tls, h.ttfb, h.download][s]), dot: _segColors[s]),
        Divider(color: p.border, height: 18),
        _kv(p, 'Total', _ms(h.total), bold: true),
      ]),
    ));
    widgets.add(const SizedBox(height: 16));
    final c = h.cert;
    widgets.add(Panel(
      title: 'Connection',
      child: Column(children: [
        _kv(p, 'Address', h.ip ?? '—'),
        _kv(p, 'Protocol', h.httpVersion.isEmpty ? '—' : h.httpVersion),
        _kv(p, 'Server', h.header('server') ?? '—'),
        if (c != null) ...[
          Divider(color: p.border, height: 18),
          _kv(p, 'Certificate', c.trusted ? 'Trusted by this phone' : 'NOT trusted', color: c.trusted ? p.success : p.danger),
          _kv(p, 'Subject', c.subject),
          _kv(p, 'Issuer', c.issuer),
          _kv(p, 'Valid', '${c.validFrom.toUtc().toIso8601String().substring(0, 10)} → ${c.validTo.toUtc().toIso8601String().substring(0, 10)}'),
          _kv(p, 'Days left', '${c.daysLeft()}', color: c.daysLeft() < 14 ? p.danger : (c.daysLeft() < 30 ? p.warning : null)),
          _kv(p, 'SHA-1', c.sha1, mono: true),
        ],
      ]),
    ));
    widgets.add(const SizedBox(height: 16));

    if (h.status != null) {
      widgets.add(CodeBlock(
        [
          '${h.httpVersion} ${h.status} ${h.reason}',
          for (final (k, v) in h.headers) '$k: $v',
        ].join('\n'),
        label: 'RESPONSE HEADERS (${h.headers.length})',
        maxHeight: 320,
      ));
      widgets.add(const SizedBox(height: 16));

      widgets.add(Panel(
        title: 'Security headers',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final chk in HeaderAnalysis.security(h))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(chk.ok ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded, size: 17, color: chk.ok ? p.success : p.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(chk.name, style: p.ui(size: 12.5, weight: FontWeight.w600)),
                    SelectableText(chk.detail, style: p.ui(size: 12, color: p.textMuted)),
                  ]),
                ),
              ]),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _push(CyberScreen(initialUrl: h.url.toString())),
              icon: const Icon(Icons.security_rounded, size: 16),
              label: const Text('Full scan in NOVA Cyber'),
            ),
          ),
        ]),
      ));
      widgets.add(const SizedBox(height: 16));

      final caching = HeaderAnalysis.caching(h);
      final cors = HeaderAnalysis.cors(h);
      final cookies = HeaderAnalysis.cookies(h);
      widgets.add(Panel(
        title: 'Caching',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final line in caching)
            Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('• $line', style: p.ui(size: 12.5, color: p.textMuted, height: 1.4))),
        ]),
      ));
      widgets.add(const SizedBox(height: 16));
      widgets.add(Panel(
        title: 'CORS & cookies',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (cors.isEmpty)
            Text('No CORS headers: other sites\' scripts can\'t read this response.', style: p.ui(size: 12.5, color: p.textMuted))
          else
            for (final l in cors) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: SelectableText(l, style: kMono.copyWith(fontSize: 12, color: p.text))),
          const SizedBox(height: 10),
          if (cookies.isEmpty)
            Text('No cookies set.', style: p.ui(size: 12.5, color: p.textMuted))
          else
            for (final (name, miss) in cookies)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(miss.isEmpty ? Icons.cookie_outlined : Icons.warning_amber_rounded, size: 15, color: miss.isEmpty ? p.success : p.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '$name  ', style: kMono.copyWith(fontSize: 12, color: p.text)),
                      TextSpan(
                          text: miss.isEmpty ? 'Secure · HttpOnly · SameSite' : 'missing ${miss.join(', ')}',
                          style: p.ui(size: 12, color: miss.isEmpty ? p.textFaint : p.warning)),
                    ])),
                  ),
                ]),
              ),
        ]),
      ));
      widgets.add(const SizedBox(height: 16));
      widgets.add(_bodyBlock(p, h));
      widgets.add(const SizedBox(height: 12));
      widgets.add(Wrap(spacing: 8, runSpacing: 8, children: [
        _ghost(p, Icons.developer_mode_rounded, 'Inspect in NOVA DevTools', () => _open(h.url.toString())),
        _ghost(p, Icons.open_in_new_rounded, 'Open in a tab', () => _open(h.url.toString(), devtools: false)),
      ]));
    }
    return widgets;
  }

  Widget _bodyBlock(NovaPalette p, Hop h) {
    final type = (h.header('content-type') ?? '').toLowerCase();
    final sizes = '${_size(h.bodyWire)} on the wire → ${_size(h.body.length)} decoded'
        '${h.header('content-encoding') != null ? ' (${h.header('content-encoding')})' : ''}'
        '${h.truncated ? ' · first ${_size(RequestTimeline.maxBody)} only' : ''}';
    if (h.body.isEmpty) {
      return Panel(title: 'Body', child: Text('No body. $sizes', style: p.ui(size: 12.5, color: p.textMuted)));
    }
    String text;
    var label = 'BODY · ${type.isEmpty ? 'unknown type' : type.split(';').first} · $sizes';
    final isText = type.isEmpty || type.contains('json') || type.contains('text') || type.contains('xml') || type.contains('javascript') ||
        type.contains('html') || type.contains('css') || type.contains('svg');
    if (isText) {
      text = utf8.decode(h.body.length > 400000 ? h.body.sublist(0, 400000) : h.body, allowMalformed: true);
      if (type.contains('json')) {
        final f = DevTools.jsonFormat(text);
        if (f.ok) {
          text = f.text;
          label = '$label · pretty-printed';
        }
      }
      if (text.length > 60000) text = '${text.substring(0, 60000)}\n… (${_size(h.body.length)} total — shortened for display)';
    } else {
      text = DevTools.hexDump(h.body, max: 2048);
      label = '$label · binary (hex)';
    }
    return CodeBlock(text, label: label, maxHeight: 420);
  }

  Widget _kv(NovaPalette p, String k, String v, {Color? color, bool bold = false, bool mono = false, Color? dot}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (dot != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(width: 8),
          ],
          SizedBox(width: dot != null ? 104 : 96, child: Text(k, style: p.ui(size: 12.5, color: p.textFaint))),
          Expanded(
            child: SelectableText(v,
                style: mono || k == 'Address'
                    ? kMono.copyWith(fontSize: 12, color: color ?? p.text)
                    : p.ui(size: 12.5, color: color ?? p.text, weight: bold ? FontWeight.w700 : FontWeight.w500)),
          ),
        ]),
      );

  Widget _errorBox(NovaPalette p, String msg) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.danger.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          Icon(Icons.error_outline_rounded, color: p.danger, size: 18),
          const SizedBox(width: 10),
          Expanded(child: SelectableText(msg, style: p.ui(size: 13, color: p.text))),
        ]),
      );

  // ── DNS view ──────────────────────────────────────────────────────────────
  Widget _dnsView(NovaPalette p) {
    return _scroll(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _pageHeader(p, 'DNS & domain', 'Every record type from two public resolvers (DNS over HTTPS), compared, plus who the domain is registered with.'),
      Panel(
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _dnsName,
              keyboardType: TextInputType.url,
              autocorrect: false,
              style: kMono.copyWith(fontSize: 13.5, color: p.text),
              onSubmitted: (_) => _runDns(),
              decoration: InputDecoration(
                hintText: 'example.com',
                hintStyle: kMono.copyWith(fontSize: 13.5, color: p.textFaint),
                prefixIcon: Icon(Icons.dns_outlined, size: 18, color: p.textFaint),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _dnsRunning ? null : () => _runDns(),
            child: _dnsRunning
                ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.onAccent))
                : const Text('Look up'),
          ),
        ]),
      ),
      if (_dnsError != null) ...[const SizedBox(height: 12), _errorBox(p, _dnsError!)],
      if (_ra != null || _rb != null) ...[const SizedBox(height: 16), ..._dnsResults(p)],
    ]));
  }

  List<Widget> _dnsResults(NovaPalette p) {
    final a = _ra ?? _rb!;
    final diff = (_ra != null && _rb != null) ? DevDns.differences(_ra!, _rb!) : const <String>[];
    final out = <Widget>[];
    if (a.nxdomain) out.addAll([_errorBox(p, 'This name doesn\'t exist in DNS (NXDOMAIN).'), const SizedBox(height: 16)]);
    out.add(Panel(
      child: Row(children: [
        Icon(diff.isEmpty ? Icons.verified_rounded : Icons.compare_arrows_rounded, color: diff.isEmpty ? p.success : p.warning),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _ra == null || _rb == null
                ? 'Answer from one resolver only (the other didn\'t answer).'
                : diff.isEmpty
                    ? 'Both resolvers return the same records.'
                    : 'Resolvers disagree on ${diff.join(', ')} — usually a recent change still spreading (TTL) or geo DNS.',
            style: p.ui(size: 13, weight: FontWeight.w600),
          ),
        ),
      ]),
    ));
    out.add(const SizedBox(height: 16));
    out.add(_rdapPanel(p));
    out.add(const SizedBox(height: 16));
    for (final t in DevDns.types) {
      final recs = a.byType[t] ?? const <DnsRecord>[];
      final other = _ra != null && _rb != null && diff.contains(t) ? _rb!.byType[t] ?? const <DnsRecord>[] : null;
      out.add(Panel(
        title: '$t  ·  ${recs.where((r) => r.type == t).length}',
        trailing: a.errors[t] != null ? Text(a.errors[t]!, style: p.ui(size: 12, color: p.danger)) : null,
        child: recs.isEmpty
            ? Text('No $t records.', style: p.ui(size: 12.5, color: p.textFaint))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final r in recs) _dnsRow(p, r),
                if (other != null) ...[
                  Divider(color: p.border, height: 18),
                  Text('Second resolver answers', style: p.ui(size: 11.5, color: p.warning, weight: FontWeight.w700)),
                  for (final r in other) _dnsRow(p, r),
                ],
              ]),
      ));
      out.add(const SizedBox(height: 10));
    }
    return out;
  }

  Widget _dnsRow(NovaPalette p, DnsRecord r) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(r.type, style: kMono.copyWith(fontSize: 12, color: p.accent, fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
            Text('TTL ${r.ttl}', style: kMono.copyWith(fontSize: 12, color: p.textFaint)),
          ]),
          SelectableText(r.data, style: kMono.copyWith(fontSize: 12.5, color: p.text)),
        ]),
      );

  Widget _rdapPanel(NovaPalette p) {
    final d = _rdap;
    if (d == null) {
      return Panel(title: 'Registration', child: Text(_rdapError ?? '—', style: p.ui(size: 12.5, color: p.textMuted)));
    }
    final left = d.daysLeft();
    String date(DateTime? x) => x == null ? '—' : '${x.toUtc().toIso8601String().substring(0, 10)} (${DevTools.relative(x, DateTime.now())})';
    return Panel(
      title: 'Registration · ${d.domain}',
      child: Column(children: [
        _kv(p, 'Registrar', d.registrar ?? '—'),
        _kv(p, 'Registered', date(d.created)),
        _kv(p, 'Expires', date(d.expires), color: left == null ? null : (left < 30 ? p.danger : (left < 90 ? p.warning : p.success))),
        _kv(p, 'Updated', date(d.updated)),
        _kv(p, 'DNSSEC', d.dnssec == null ? '—' : (d.dnssec! ? 'Signed' : 'Not signed'), color: d.dnssec == true ? p.success : null),
        _kv(p, 'Nameservers', d.nameservers.isEmpty ? '—' : d.nameservers.join('\n'), mono: true),
        if (d.status.isNotEmpty) _kv(p, 'Status', d.status.join(', ')),
      ]),
    );
  }
}
