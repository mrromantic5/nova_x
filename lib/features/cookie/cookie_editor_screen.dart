// lib/features/cookie/cookie_editor_screen.dart
//
// NOVA X — Premium Cookie Editor
// Uses flutter_inappwebview CookieManager which has FULL access to ALL cookies
// including HttpOnly cookies (which JavaScript cannot read).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/theme/app_theme.dart';

class CookieEditorScreen extends StatefulWidget {
  final String url;
  const CookieEditorScreen({super.key, required this.url});
  @override
  State<CookieEditorScreen> createState() => _CookieEditorScreenState();
}

class _CookieEditorScreenState extends State<CookieEditorScreen>
    with SingleTickerProviderStateMixin {
  List<Cookie> _cookies = [];
  List<Cookie> _filtered = [];
  bool _loading = true;
  String _search = '';
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _load();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cookies = await CookieManager.instance()
          .getCookies(url: WebUri(widget.url));
      _cookies  = cookies;
      _filtered = cookies;
      _animCtrl.forward(from: 0);
    } catch (e) {
      _snack('Could not load cookies: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _applySearch(String q) {
    setState(() {
      _search   = q;
      _filtered = q.isEmpty
          ? _cookies
          : _cookies.where((c) =>
              c.name.toLowerCase().contains(q.toLowerCase()) ||
              (c.value?.toLowerCase().contains(q.toLowerCase()) ?? false) ||
              (c.domain?.toLowerCase().contains(q.toLowerCase()) ?? false)).toList();
    });
  }

  // ── Delete one cookie ────────────────────────────────────────────────────────
  Future<void> _deleteCookie(Cookie c) async {
    final ok = await _confirm(
        'Delete Cookie', 'Delete "${c.name}" from ${c.domain ?? widget.url}?');
    if (!ok) return;
    await CookieManager.instance().deleteCookie(
        url: WebUri(widget.url), name: c.name,
        domain: c.domain ?? '', path: c.path ?? '/');
    _snack('Cookie "${c.name}" deleted');
    _load();
  }

  // ── Delete all cookies ───────────────────────────────────────────────────────
  Future<void> _deleteAll() async {
    final ok = await _confirm('Delete All Cookies',
        'Remove all ${_cookies.length} cookies for this site?');
    if (!ok) return;
    await CookieManager.instance().deleteAllCookies();
    _snack('All cookies deleted');
    _load();
  }

  // ── Add / Edit cookie ────────────────────────────────────────────────────────
  void _showAddEdit([Cookie? existing]) {
    final nameCtrl  = TextEditingController(text: existing?.name ?? '');
    final valueCtrl = TextEditingController(text: existing?.value ?? '');
    final pathCtrl  = TextEditingController(text: existing?.path ?? '/');
    bool isSecure   = existing?.isSecure ?? false;
    bool isHttpOnly = existing?.isHttpOnly ?? false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, setSt) {
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: AppTheme.divider,
                    borderRadius: BorderRadius.circular(2))),

              // Title
              Row(children: [
                Container(width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.cookie_outlined,
                      color: Colors.white, size: 20)),
                const SizedBox(width: 12),
                Text(existing == null ? 'Add Cookie' : 'Edit Cookie',
                    style: GoogleFonts.spaceGrotesk(
                        color: AppTheme.textPrimary, fontSize: 18,
                        fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 20),

              // Name
              _field('Name', nameCtrl,
                  readOnly: existing != null,
                  hint: 'cookie_name'),
              const SizedBox(height: 12),
              _field('Value', valueCtrl, hint: 'cookie_value', maxLines: 3),
              const SizedBox(height: 12),
              _field('Path', pathCtrl, hint: '/'),
              const SizedBox(height: 16),

              // Flags
              Row(children: [
                _flagTile('Secure', isSecure, (v) => setSt(() => isSecure = v)),
                const SizedBox(width: 12),
                _flagTile('HttpOnly', isHttpOnly,
                    (v) => setSt(() => isHttpOnly = v)),
              ]),
              const SizedBox(height: 20),

              // Save button
              GestureDetector(
                onTap: () async {
                  final n = nameCtrl.text.trim();
                  final v = valueCtrl.text.trim();
                  if (n.isEmpty) { _snack('Name is required'); return; }
                  await CookieManager.instance().setCookie(
                    url:        WebUri(widget.url),
                    name:       n,
                    value:      v,
                    path:       pathCtrl.text.trim().isEmpty
                        ? '/' : pathCtrl.text.trim(),
                    isSecure:   isSecure,
                    isHttpOnly: isHttpOnly,
                  );
                  if (mounted) Navigator.pop(context);
                  _snack(existing == null
                      ? 'Cookie added ✓' : 'Cookie updated ✓');
                  _load();
                },
                child: Container(
                  width: double.infinity, height: 52,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: AppTheme.glowShadow,
                  ),
                  child: Center(child: Text(
                    existing == null ? 'Add Cookie' : 'Save Changes',
                    style: GoogleFonts.spaceGrotesk(color: Colors.white,
                        fontSize: 15, fontWeight: FontWeight.w700))),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {bool readOnly = false, String hint = '', int maxLines = 1}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.inter(color: AppTheme.textHint,
            fontSize: 11, fontWeight: FontWeight.w700,
            letterSpacing: .5)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl, readOnly: readOnly,
          maxLines: maxLines,
          style: GoogleFonts.inter(
              color: readOnly ? AppTheme.textHint : AppTheme.textPrimary,
              fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 13),
            filled: true, fillColor: AppTheme.bgElevated,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.accentCyan, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ]);

  Widget _flagTile(String label, bool value, ValueChanged<bool> onChanged) =>
      Expanded(child: GestureDetector(
        onTap: () => onChanged(!value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: value
                ? AppTheme.accentCyan.withOpacity(0.12)
                : AppTheme.bgElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: value ? AppTheme.accentCyan : AppTheme.divider,
            ),
          ),
          child: Row(children: [
            Icon(value ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                color: value ? AppTheme.accentCyan : AppTheme.textHint,
                size: 18),
            const SizedBox(width: 8),
            Text(label, style: GoogleFonts.inter(
                color: value ? AppTheme.accentCyan : AppTheme.textHint,
                fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
      ));

  // ── Confirm dialog ───────────────────────────────────────────────────────────
  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title, style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
          content: Text(body, style: GoogleFonts.inter(
              color: AppTheme.textSecondary)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel', style: GoogleFonts.inter(
                    color: AppTheme.textHint))),
            TextButton(onPressed: () => Navigator.pop(context, true),
                child: Text('Delete', style: GoogleFonts.inter(
                    color: AppTheme.danger, fontWeight: FontWeight.w700))),
          ],
        ),
      ) ?? false;

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
      backgroundColor: AppTheme.bgElevated,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));

  String _domainFromUrl(String url) {
    try { return Uri.parse(url).host; } catch (_) { return url; }
  }

  // ════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final domain = _domainFromUrl(widget.url);
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppTheme.textSecondary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Cookie Editor', style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textPrimary,
              fontSize: 17, fontWeight: FontWeight.w800)),
          Text(domain, style: GoogleFonts.inter(
              color: AppTheme.textHint, fontSize: 11)),
        ]),
        actions: [
          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: AppTheme.accentCyan, size: 20),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
          // Delete all
          if (_cookies.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded,
                  color: AppTheme.danger, size: 20),
              onPressed: _deleteAll,
              tooltip: 'Delete all cookies',
            ),
        ],
      ),

      // FAB — Add new cookie
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEdit(),
        backgroundColor: Colors.transparent,
        elevation: 0,
        label: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(30),
            boxShadow: AppTheme.glowShadow,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.add_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('Add Cookie', style: GoogleFonts.spaceGrotesk(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator(
              color: AppTheme.accentCyan, strokeWidth: 2))
          : FadeTransition(
              opacity: _fadeAnim,
              child: Column(children: [
                // Stats bar
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(children: [
                    _statChip('${_cookies.length}', 'Total', AppTheme.accentCyan),
                    const SizedBox(width: 8),
                    _statChip(
                      '${_cookies.where((c) => c.isSecure == true).length}',
                      'Secure', AppTheme.success),
                    const SizedBox(width: 8),
                    _statChip(
                      '${_cookies.where((c) => c.isHttpOnly == true).length}',
                      'HttpOnly', AppTheme.warning),
                    const SizedBox(width: 8),
                    _statChip(
                      '${_cookies.where((c) => c.isSessionOnly == true).length}',
                      'Session', AppTheme.accentPurple),
                  ]),
                ),

                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: TextField(
                    onChanged: _applySearch,
                    style: GoogleFonts.inter(
                        color: AppTheme.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search cookies…',
                      hintStyle: GoogleFonts.inter(color: AppTheme.textHint),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: AppTheme.textHint, size: 18),
                      suffixIcon: _search.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  color: AppTheme.textHint, size: 16),
                              onPressed: () {
                                _applySearch('');
                              })
                          : null,
                      filled: true, fillColor: AppTheme.bgCard,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                              color: AppTheme.accentCyan, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                ),

                // Cookie list
                if (_filtered.isEmpty)
                  Expanded(child: Center(child: Column(
                    mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.cookie_outlined,
                        color: AppTheme.textHint, size: 48),
                    const SizedBox(height: 14),
                    Text(_search.isEmpty ? 'No cookies found' : 'No matches',
                        style: GoogleFonts.spaceGrotesk(
                            color: AppTheme.textPrimary, fontSize: 18,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(_search.isEmpty
                        ? 'This site has no cookies'
                        : 'Try a different search term',
                        style: GoogleFonts.inter(
                            color: AppTheme.textHint, fontSize: 13)),
                  ])))
                else
                  Expanded(child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) => _buildCookieTile(_filtered[i]),
                  )),
              ]),
            ),
    );
  }

  Widget _statChip(String value, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(value, style: GoogleFonts.spaceGrotesk(
          color: color, fontSize: 14, fontWeight: FontWeight.w800)),
      const SizedBox(width: 5),
      Text(label, style: GoogleFonts.inter(
          color: color.withOpacity(0.8), fontSize: 10,
          fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _buildCookieTile(Cookie cookie) {
    final isHttpOnly = cookie.isHttpOnly == true;
    final isSecure   = cookie.isSecure   == true;
    final isSession  = cookie.isSessionOnly == true;

    return Dismissible(
      key: Key('${cookie.name}_${cookie.domain}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppTheme.danger.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.danger.withOpacity(0.3)),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_rounded, color: AppTheme.danger),
      ),
      confirmDismiss: (_) async {
        final ok = await _confirm('Delete Cookie',
            'Delete "${cookie.name}"?');
        if (ok) {
          await CookieManager.instance().deleteCookie(
              url: WebUri(widget.url), name: cookie.name,
              domain: cookie.domain ?? '', path: cookie.path ?? '/');
          _cookies.remove(cookie);
          setState(() => _filtered = _filtered..remove(cookie));
          _snack('"${cookie.name}" deleted');
        }
        return false; // we handle removal manually
      },
      child: GestureDetector(
        onTap: () => _showCookieDetail(cookie),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(children: [
            // Header row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
              child: Row(children: [
                // Cookie icon
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.bgElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  child: const Icon(Icons.cookie_outlined,
                      color: AppTheme.accentCyan, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(cookie.name, style: GoogleFonts.inter(
                      color: AppTheme.textPrimary, fontSize: 14,
                      fontWeight: FontWeight.w700)),
                  Text(cookie.domain ?? '', style: GoogleFonts.inter(
                      color: AppTheme.textHint, fontSize: 11)),
                ])),
                // Action buttons
                IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      color: AppTheme.accentCyan, size: 16),
                  onPressed: () => _showAddEdit(cookie),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AppTheme.danger, size: 16),
                  onPressed: () => _deleteCookie(cookie),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
            ),

            // Value preview
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.bgElevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: GestureDetector(
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: cookie.value ?? ''));
                    _snack('Value copied');
                  },
                  child: Text(
                    cookie.value ?? '(empty)',
                    style: GoogleFonts.inter(
                        color: AppTheme.textSecondary,
                        fontSize: 12, fontFamily: 'monospace'),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),

            // Badges
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(children: [
                if (isHttpOnly) _badge('HttpOnly', AppTheme.warning),
                if (isHttpOnly) const SizedBox(width: 6),
                if (isSecure) _badge('Secure', AppTheme.success),
                if (isSecure) const SizedBox(width: 6),
                if (isSession) _badge('Session', AppTheme.accentPurple),
                if (!isSession && cookie.expiresDate != null)
                  _badge(
                    'Expires ${_formatExpiry(cookie.expiresDate!)}',
                    AppTheme.accentCyan),
                const Spacer(),
                Text('Swipe to delete',
                    style: GoogleFonts.inter(
                        color: AppTheme.divider, fontSize: 9)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Text(text, style: GoogleFonts.inter(
        color: color, fontSize: 9, fontWeight: FontWeight.w700)),
  );

  String _formatExpiry(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  void _showCookieDetail(Cookie cookie) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2))),
          Text(cookie.name, style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textPrimary, fontSize: 18,
              fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          ...[
            ['Name',       cookie.name],
            ['Value',      cookie.value ?? '(empty)'],
            ['Domain',     cookie.domain ?? '-'],
            ['Path',       cookie.path ?? '/'],
            ['HttpOnly',   cookie.isHttpOnly == true ? 'Yes' : 'No'],
            ['Secure',     cookie.isSecure   == true ? 'Yes' : 'No'],
            ['Session',    cookie.isSessionOnly == true ? 'Yes' : 'No'],
            ['Expires',    cookie.expiresDate != null
                ? _formatExpiry(cookie.expiresDate!) : 'Session'],
          ].map((row) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 80, child: Text(row[0], style: GoogleFonts.inter(
                  color: AppTheme.textHint, fontSize: 12,
                  fontWeight: FontWeight.w600))),
              const SizedBox(width: 12),
              Expanded(child: GestureDetector(
                onLongPress: () {
                  Clipboard.setData(ClipboardData(text: row[1]));
                  _snack('${row[0]} copied');
                },
                child: Text(row[1], style: GoogleFonts.inter(
                    color: AppTheme.textPrimary, fontSize: 13)),
              )),
            ]),
          )),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(color: AppTheme.bgElevated,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.divider)),
                child: Center(child: Text('Close', style: GoogleFonts.inter(
                    color: AppTheme.textHint, fontSize: 14))),
              ),
            )),
            const SizedBox(width: 12),
            Expanded(child: GestureDetector(
              onTap: () { Navigator.pop(context); _showAddEdit(cookie); },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(14)),
                child: Center(child: Text('Edit', style: GoogleFonts.spaceGrotesk(
                    color: Colors.white, fontSize: 14,
                    fontWeight: FontWeight.w700))),
              ),
            )),
          ]),
        ]),
      ),
    );
  }
}
