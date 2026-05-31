// lib/features/browser/widgets/devtools_panel.dart
//
// In-app Developer Tools panel for NOVA X browser.
// Tabs: Elements (HTML source) | Console (live JS logs) | Storage (cookies) | Info
//
// Usage:
//   showDevTools(context, wvc: _wvc, url: _currentUrl, title: _pageTitle,
//                consoleLogs: _consoleLogs, onClear: () => setState(() => _consoleLogs.clear()));

import 'package:flutter/material.dart';
import 'package:nova_x/core/services/rewards_entitlements.dart';
import 'package:nova_x/core/services/rewards_service.dart';
import 'package:nova_x/core/widgets/feature_lock.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────
void showDevTools(
  BuildContext context, {
  required InAppWebViewController? wvc,
  required String url,
  required String pageTitle,
  required List<Map<String, dynamic>> consoleLogs,
  required VoidCallback onClearConsole,
}) {
  if (!RewardsEntitlements.isUnlocked(RewardFeature.devtools)) {
    showFeatureUnlockSheet(context, RewardFeature.devtools);
    return;
  }
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      snap: true,
      snapSizes: const [0.3, 0.55, 0.95],
      builder: (ctx, scrollCtrl) => _DevToolsPanel(
        wvc:             wvc,
        url:             url,
        pageTitle:       pageTitle,
        consoleLogs:     consoleLogs,
        onClearConsole:  onClearConsole,
        scrollController: scrollCtrl,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Main panel widget
// ─────────────────────────────────────────────────────────────────────────────
class _DevToolsPanel extends StatefulWidget {
  final InAppWebViewController? wvc;
  final String url;
  final String pageTitle;
  final List<Map<String, dynamic>> consoleLogs;
  final VoidCallback onClearConsole;
  final ScrollController scrollController;

  const _DevToolsPanel({
    required this.wvc,
    required this.url,
    required this.pageTitle,
    required this.consoleLogs,
    required this.onClearConsole,
    required this.scrollController,
  });

  @override
  State<_DevToolsPanel> createState() => _DevToolsPanelState();
}

class _DevToolsPanelState extends State<_DevToolsPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  // Elements
  String _htmlSource = '';
  bool   _loadingHtml = false;

  // Storage
  List<Cookie> _cookies = [];
  bool _loadingCookies = false;

  // Search / filter
  final TextEditingController _filterCtrl = TextEditingController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _tabCtrl.addListener(_onTabSwitch);
    _loadHtml();  // pre-load on open
  }

  @override
  void dispose() {
    _tabCtrl.removeListener(_onTabSwitch);
    _tabCtrl.dispose();
    _filterCtrl.dispose();
    super.dispose();
  }

  void _onTabSwitch() {
    if (!_tabCtrl.indexIsChanging) return;
    switch (_tabCtrl.index) {
      case 0: _loadHtml();    break;
      case 2: _loadCookies(); break;
    }
    setState(() => _filter = '');
    _filterCtrl.clear();
  }

  // ── Data fetchers ──────────────────────────────────────────────────────────
  Future<void> _loadHtml() async {
    if (widget.wvc == null) return;
    setState(() => _loadingHtml = true);
    try {
      final html = await widget.wvc!.getHtml() ?? '<html>\n  <head></head>\n  <body></body>\n</html>';
      if (mounted) setState(() { _htmlSource = html; _loadingHtml = false; });
    } catch (_) {
      if (mounted) setState(() { _htmlSource = '// Could not load source'; _loadingHtml = false; });
    }
  }

  Future<void> _loadCookies() async {
    if (widget.url.isEmpty) return;
    setState(() => _loadingCookies = true);
    try {
      final cookies = await CookieManager.instance()
          .getCookies(url: WebUri(widget.url));
      if (mounted) setState(() { _cookies = cookies; _loadingCookies = false; });
    } catch (_) {
      if (mounted) setState(() { _loadingCookies = false; });
    }
  }

  Future<void> _clearCookies() async {
    await CookieManager.instance().deleteCookies(url: WebUri(widget.url));
    await _loadCookies();
    _snack('Cookies cleared for this site');
  }

  Future<void> _clearSiteStorage() async {
    if (widget.wvc == null) return;
    await widget.wvc!.clearCache();
    _snack('Cache and storage cleared');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(color: Colors.white, fontSize: 13)),
      backgroundColor: AppTheme.bgElevated,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0B1624),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        // Drag handle
        Center(
          child: Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            decoration: BoxDecoration(
              color: AppTheme.textHint, borderRadius: BorderRadius.circular(2)),
          ),
        ),

        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.accentCyan.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.code_rounded, color: AppTheme.accentCyan, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Developer Tools',
                    style: GoogleFonts.spaceGrotesk(
                        color: AppTheme.textPrimary,
                        fontSize: 13, fontWeight: FontWeight.w700)),
                Text(widget.url,
                    style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 10),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Icon(Icons.close_rounded, color: AppTheme.textHint, size: 20),
            ),
          ]),
        ),

        // Tab bar
        Container(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFF1A2E45), width: 1),
            ),
          ),
          child: TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: AppTheme.accentCyan,
            indicatorWeight: 2,
            labelColor: AppTheme.accentCyan,
            unselectedLabelColor: AppTheme.textHint,
            labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
            unselectedLabelStyle: GoogleFonts.inter(fontSize: 12),
            tabs: const [
              Tab(text: 'Elements'),
              Tab(text: 'Console'),
              Tab(text: 'Storage'),
              Tab(text: 'Info'),
            ],
          ),
        ),

        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildElementsTab(),
              _buildConsoleTab(),
              _buildStorageTab(),
              _buildInfoTab(),
            ],
          ),
        ),
      ]),
    );
  }

  // ── ELEMENTS TAB ──────────────────────────────────────────────────────────
  Widget _buildElementsTab() {
    return Column(children: [
      // Toolbar
      _tabToolbar(
        left: Row(children: [
          _toolBtn(Icons.refresh_rounded, 'Refresh source', _loadHtml),
          const SizedBox(width: 8),
          _toolBtn(Icons.copy_rounded, 'Copy HTML', () {
            Clipboard.setData(ClipboardData(text: _htmlSource));
            _snack('HTML copied to clipboard');
          }),
        ]),
        right: _filterField('Filter elements…'),
      ),

      // Content
      if (_loadingHtml)
        const Expanded(child: Center(child: CircularProgressIndicator(
            color: AppTheme.accentCyan, strokeWidth: 2)))
      else
        Expanded(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            scrollDirection: Axis.vertical,
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildHtmlSource(
                _filter.isEmpty
                    ? _htmlSource
                    : _htmlLines(_htmlSource)
                        .where((l) => l.toLowerCase().contains(_filter))
                        .join('\n'),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _buildHtmlSource(String html) {
    final lines = _htmlLines(html);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(lines.length, (i) {
        final line = lines[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Line number
              SizedBox(
                width: 34,
                child: Text('${i + 1}',
                    style: GoogleFonts.jetBrainsMono(
                        color: const Color(0xFF3A5070), fontSize: 11),
                    textAlign: TextAlign.right),
              ),
              const SizedBox(width: 12),
              // Syntax-coloured line
              _htmlSpan(line),
            ],
          ),
        );
      }),
    );
  }

  Widget _htmlSpan(String line) {
    final spans = <TextSpan>[];
    final trimmed = line.trimLeft();

    if (trimmed.startsWith('<!--')) {
      // Comment
      spans.add(TextSpan(text: line,
          style: const TextStyle(color: Color(0xFF5A7A5A))));
    } else {
      // Tokenise: split on < > " =
      final regex = RegExp(r'(</?[\w!][^>]*>|"[^"]*"|[^<>"]+)');
      for (final m in regex.allMatches(line)) {
        final t = m.group(0)!;
        if (t.startsWith('<') && t.endsWith('>')) {
          // Tag — break into parts
          final tagSpans = _colorTag(t);
          spans.addAll(tagSpans);
        } else if (t.startsWith('"')) {
          spans.add(TextSpan(text: t,
              style: const TextStyle(color: Color(0xFFCE9178))));
        } else {
          spans.add(TextSpan(text: t,
              style: const TextStyle(color: Color(0xFFD4D4D4))));
        }
      }
    }

    return RichText(
      text: TextSpan(
        style: GoogleFonts.jetBrainsMono(fontSize: 11, height: 1.5),
        children: spans,
      ),
    );
  }

  List<TextSpan> _colorTag(String tag) {
    final spans = <TextSpan>[];
    // < or </
    final open = tag.startsWith('</') ? '</' : '<';
    spans.add(TextSpan(text: open, style: const TextStyle(color: Color(0xFF808080))));

    // Tag name
    final rest = tag.substring(open.length, tag.endsWith('/>') ? tag.length - 2 : tag.length - 1);
    final spaceIdx = rest.indexOf(' ');
    final tagName  = spaceIdx < 0 ? rest : rest.substring(0, spaceIdx);
    spans.add(TextSpan(text: tagName, style: const TextStyle(color: Color(0xFF569CD6))));

    if (spaceIdx >= 0) {
      // Attributes
      final attrs = rest.substring(spaceIdx);
      // Use triple-quote raw string so single quotes inside don't end the literal
      final attrRx = RegExp(r"""(\s+[\w-:]+)(=)("[^"]*"|'[^']*')?""");
      int cursor = 0;
      for (final m in attrRx.allMatches(attrs)) {
        if (m.start > cursor) {
          spans.add(TextSpan(text: attrs.substring(cursor, m.start),
              style: const TextStyle(color: Color(0xFFD4D4D4))));
        }
        spans.add(TextSpan(text: m.group(1),
            style: const TextStyle(color: Color(0xFF9CDCFE))));
        if (m.group(2) != null) {
          spans.add(TextSpan(text: '=',
              style: const TextStyle(color: Color(0xFF808080))));
        }
        if (m.group(3) != null) {
          spans.add(TextSpan(text: m.group(3),
              style: const TextStyle(color: Color(0xFFCE9178))));
        }
        cursor = m.end;
      }
      if (cursor < attrs.length) {
        spans.add(TextSpan(text: attrs.substring(cursor),
            style: const TextStyle(color: Color(0xFFD4D4D4))));
      }
    }

    spans.add(TextSpan(
        text: tag.endsWith('/>') ? '/>' : '>',
        style: const TextStyle(color: Color(0xFF808080))));
    return spans;
  }

  List<String> _htmlLines(String html) =>
      html.replaceAll('\r\n', '\n').split('\n');

  // ── CONSOLE TAB ───────────────────────────────────────────────────────────
  Widget _buildConsoleTab() {
    final logs = _filter.isEmpty
        ? widget.consoleLogs
        : widget.consoleLogs
            .where((l) =>
                (l['msg'] as String).toLowerCase().contains(_filter) ||
                (l['type'] as String).toLowerCase().contains(_filter))
            .toList();

    return Column(children: [
      _tabToolbar(
        left: Row(children: [
          _toolBtn(Icons.delete_outline_rounded, 'Clear', widget.onClearConsole),
          const SizedBox(width: 12),
          // Type filters
          ...[('log', AppTheme.textSecondary), ('warn', AppTheme.warning),
              ('error', AppTheme.danger)].map((t) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => setState(() => _filter = _filter == t.$1 ? '' : t.$1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _filter == t.$1 ? t.$2.withOpacity(0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _filter == t.$1 ? t.$2 : AppTheme.divider),
                    ),
                    child: Text(t.$1,
                        style: GoogleFonts.inter(
                            color: t.$2, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                ),
              )),
        ]),
        right: _filterField('Filter logs…'),
      ),

      if (logs.isEmpty)
        Expanded(
          child: Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.terminal_rounded, color: AppTheme.textHint, size: 36),
              const SizedBox(height: 10),
              Text('No console output yet',
                  style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 13)),
              const SizedBox(height: 4),
              Text('JS console.log / warn / error will appear here',
                  style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11)),
            ],
          )),
        )
      else
        Expanded(
          child: ListView.builder(
            controller: widget.scrollController,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: logs.length,
            itemBuilder: (_, i) {
              final log  = logs[logs.length - 1 - i]; // newest first
              final type = log['type'] as String? ?? 'log';
              final msg  = log['msg']  as String? ?? '';
              final time = log['time'] as String? ?? '';
              return _consoleEntry(type, msg, time);
            },
          ),
        ),
    ]);
  }

  Widget _consoleEntry(String type, String msg, String time) {
    final (icon, color, bg) = switch (type) {
      'error' => (Icons.error_outline_rounded, AppTheme.danger,
          AppTheme.danger.withOpacity(0.06)),
      'warn' => (Icons.warning_amber_rounded, AppTheme.warning,
          AppTheme.warning.withOpacity(0.06)),
      'info' => (Icons.info_outline_rounded, AppTheme.accentCyan,
          AppTheme.accentCyan.withOpacity(0.04)),
      _ => (Icons.chevron_right_rounded, const Color(0xFF8A9BAD),
          Colors.transparent),
    };

    return Container(
      color: bg,
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(msg,
              style: GoogleFonts.jetBrainsMono(
                  color: color, fontSize: 11.5, height: 1.5)),
        ),
        if (time.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(time, style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 9.5)),
        ],
      ]),
    );
  }

  // ── STORAGE TAB ───────────────────────────────────────────────────────────
  Widget _buildStorageTab() {
    final filtered = _filter.isEmpty
        ? _cookies
        : _cookies.where((c) =>
            c.name.toLowerCase().contains(_filter) ||
            (c.value?.toString().toLowerCase().contains(_filter) ?? false)).toList();

    return Column(children: [
      _tabToolbar(
        left: Row(children: [
          _toolBtn(Icons.refresh_rounded, 'Reload', _loadCookies),
          const SizedBox(width: 8),
          _toolBtn(Icons.delete_sweep_outlined, 'Clear cookies', _clearCookies),
          const SizedBox(width: 8),
          _toolBtn(Icons.cleaning_services_outlined, 'Clear storage', _clearSiteStorage),
        ]),
        right: _filterField('Filter cookies…'),
      ),

      if (_loadingCookies)
        const Expanded(child: Center(child: CircularProgressIndicator(
            color: AppTheme.accentCyan, strokeWidth: 2)))
      else if (filtered.isEmpty)
        Expanded(
          child: Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cookie_outlined, color: AppTheme.textHint, size: 36),
              const SizedBox(height: 10),
              Text('No cookies found',
                  style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 13)),
            ],
          )),
        )
      else
        Expanded(
          child: ListView.separated(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(12),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const Divider(
                color: Color(0xFF152236), height: 1),
            itemBuilder: (_, i) => _cookieRow(filtered[i]),
          ),
        ),
    ]);
  }

  Widget _cookieRow(Cookie c) {
    final secure   = c.isSecure   ?? false;
    final httpOnly = c.isHttpOnly ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(c.name,
                style: GoogleFonts.jetBrainsMono(
                    color: const Color(0xFF9CDCFE),
                    fontSize: 11.5, fontWeight: FontWeight.w600)),
          ),
          if (secure)
            _badge('Secure', AppTheme.secure),
          if (httpOnly) ...[
            const SizedBox(width: 4),
            _badge('HttpOnly', AppTheme.warning),
          ],
        ]),
        const SizedBox(height: 3),
        GestureDetector(
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: c.value?.toString() ?? ''));
            _snack('Cookie value copied');
          },
          child: Text(c.value?.toString() ?? '(empty)',
              style: GoogleFonts.jetBrainsMono(
                  color: const Color(0xFFCE9178), fontSize: 11),
              maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        if (c.domain != null) ...[
          const SizedBox(height: 2),
          Text('Domain: ${c.domain}  Path: ${c.path ?? '/'}',
              style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 9.5)),
        ],
      ]),
    );
  }

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withOpacity(0.4)),
    ),
    child: Text(label, style: GoogleFonts.inter(color: color, fontSize: 9, fontWeight: FontWeight.w700)),
  );

  // ── INFO TAB ──────────────────────────────────────────────────────────────
  Widget _buildInfoTab() {
    final isSecure = widget.url.startsWith('https://');
    final host     = widget.url
        .replaceFirst('https://', '').replaceFirst('http://', '')
        .split('/')[0];

    final rows = <(String, String, Color?)>[
      ('Title',    widget.pageTitle, null),
      ('URL',      widget.url, null),
      ('Host',     host, null),
      ('Protocol', isSecure ? 'HTTPS (Secure)' : 'HTTP (Not Secure)',
          isSecure ? AppTheme.secure : AppTheme.danger),
      ('Cookies',  '${_cookies.length} cookie${_cookies.length == 1 ? '' : 's'}', null),
      ('Engine',   'Chromium / WebKit (flutter_inappwebview)', null),
    ];

    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Security card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: (isSecure ? AppTheme.secure : AppTheme.danger).withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (isSecure ? AppTheme.secure : AppTheme.danger).withOpacity(0.3)),
          ),
          child: Row(children: [
            Icon(
              isSecure ? Icons.lock_rounded : Icons.lock_open_rounded,
              color: isSecure ? AppTheme.secure : AppTheme.danger, size: 22),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(isSecure ? 'Connection is secure' : 'Connection is not secure',
                  style: GoogleFonts.inter(
                      color: isSecure ? AppTheme.secure : AppTheme.danger,
                      fontSize: 13, fontWeight: FontWeight.w600)),
              Text(isSecure
                  ? 'Information sent to this site is encrypted.'
                  : 'Your data could be seen by others on this network.',
                  style: GoogleFonts.inter(
                      color: AppTheme.textHint, fontSize: 11, height: 1.4)),
            ])),
          ]),
        ),
        const SizedBox(height: 16),

        // Info rows
        ...rows.map((r) => _infoRow(r.$1, r.$2, r.$3)),

        const SizedBox(height: 16),

        // Actions
        Text('Actions', style: GoogleFonts.inter(
            color: AppTheme.textHint, fontSize: 10,
            fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _actionBtn(
              Icons.copy_rounded, 'Copy URL', AppTheme.accentCyan,
              () { Clipboard.setData(ClipboardData(text: widget.url)); _snack('URL copied'); })),
          const SizedBox(width: 10),
          Expanded(child: _actionBtn(
              Icons.code_rounded, 'View Source', AppTheme.accentPurple,
              () { _tabCtrl.animateTo(0); })),
        ]),
      ]),
    );
  }

  Widget _infoRow(String label, String value, Color? valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.bgCard.withOpacity(0.5),
          border: Border(bottom: BorderSide(color: AppTheme.divider, width: 0.5)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: GoogleFonts.inter(
                    color: AppTheme.textHint,
                    fontSize: 11, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(value,
                style: GoogleFonts.inter(
                    color: valueColor ?? AppTheme.textPrimary,
                    fontSize: 11.5, height: 1.4)),
          ),
        ]),
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.inter(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ── Shared toolbar helpers ─────────────────────────────────────────────────
  Widget _tabToolbar({required Widget left, required Widget right}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: const BoxDecoration(
        color: Color(0xFF0A1525),
        border: Border(bottom: BorderSide(color: Color(0xFF1A2E45))),
      ),
      child: Row(children: [
        Flexible(child: left),
        const Spacer(),
        right,
      ]),
    );
  }

  Widget _toolBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppTheme.bgCard.withOpacity(0.5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, color: AppTheme.textSecondary, size: 15),
        ),
      ),
    );
  }

  Widget _filterField(String hint) {
    return SizedBox(
      width: 130,
      height: 28,
      child: TextField(
        controller: _filterCtrl,
        style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 11),
        onChanged: (v) => setState(() => _filter = v.toLowerCase().trim()),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11),
          filled: true,
          fillColor: AppTheme.bgCard,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide.none,
          ),
          prefixIcon: const Icon(Icons.search, color: AppTheme.textHint, size: 13),
          prefixIconConstraints: const BoxConstraints(minWidth: 26, minHeight: 26),
        ),
      ),
    );
  }
}
