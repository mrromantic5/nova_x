// lib/features/browser/screens/tabs_screen.dart
//
// Brave-style tab switcher with tab groups. Reads/edits TabsService and returns
// a TabsResult to the browser (which opens the chosen tab / new tab).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import 'package:nova_x/core/services/tabs_service.dart';

class TabsScreen extends StatefulWidget {
  const TabsScreen({super.key});
  @override
  State<TabsScreen> createState() => _TabsScreenState();
}

class _TabsScreenState extends State<TabsScreen> {
  final _svc = TabsService.instance;

  static const List<int> _palette = [
    0xFF00D4FF, 0xFF7C4DFF, 0xFF00C853, 0xFFFFC83D, 0xFFFF6B6B, 0xFF1E7BFF,
  ];

  @override
  void initState() {
    super.initState();
    _svc.ensureLoaded();
  }

  String _host(String url) {
    try {
      final u = Uri.parse(url);
      return u.host.isNotEmpty ? u.host : url;
    } catch (_) {
      return url;
    }
  }

  void _openTab(BrowserTabItem t) =>
      Navigator.pop(context, TabsResult(url: t.url, tabId: t.id));
  void _newTab() => Navigator.pop(context, TabsResult(newTab: true));
  void _newPrivateTab() =>
      Navigator.pop(context, TabsResult(newTab: true, incognito: true));

  // ── New group dialog ───────────────────────────────────────────────────────
  Future<void> _newGroup() async {
    final ctrl = TextEditingController();
    int color = _palette.first;
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, setLocal) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text('New tab group',
              style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              style: GoogleFonts.inter(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Group name',
                hintStyle: GoogleFonts.inter(color: AppTheme.textHint),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppTheme.divider),
                    borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: AppTheme.accentCyan),
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(spacing: 10, children: [
              for (final c in _palette)
                GestureDetector(
                  onTap: () => setLocal(() => color = c),
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: color == c ? Colors.white : Colors.transparent,
                          width: 2),
                    ),
                  ),
                ),
            ]),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: GoogleFonts.inter(color: AppTheme.textSecondary)),
            ),
            TextButton(
              onPressed: () {
                final name = ctrl.text.trim().isEmpty ? 'Group' : ctrl.text.trim();
                _svc.createGroup(name, color);
                Navigator.pop(context);
              },
              child: Text('Create',
                  style: GoogleFonts.inter(
                      color: AppTheme.accentCyan, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Long-press a tab → assign group / close ─────────────────────────────────
  void _tabActions(BrowserTabItem t) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(
                  color: AppTheme.textHint, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(t.title,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
          ),
          const Divider(color: AppTheme.divider, height: 1),
          if (_svc.groups.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('ADD TO GROUP',
                    style: GoogleFonts.inter(
                        color: AppTheme.textHint, fontSize: 11,
                        fontWeight: FontWeight.w700, letterSpacing: 1)),
              ),
            ),
            for (final g in _svc.groups)
              ListTile(
                leading: Icon(Icons.circle, color: Color(g.color), size: 14),
                title: Text(g.name,
                    style: GoogleFonts.inter(color: AppTheme.textPrimary)),
                trailing: t.groupId == g.id
                    ? const Icon(Icons.check_rounded, color: AppTheme.accentCyan)
                    : null,
                onTap: () {
                  _svc.assignToGroup(t.id, t.groupId == g.id ? null : g.id);
                  Navigator.pop(context);
                },
              ),
            const Divider(color: AppTheme.divider, height: 1),
          ],
          ListTile(
            leading: const Icon(Icons.close_rounded, color: Color(0xFFFF6B6B)),
            title: Text('Close tab',
                style: GoogleFonts.inter(color: const Color(0xFFFF6B6B))),
            onTap: () { _svc.closeTab(t.id); Navigator.pop(context); },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _groupMenu(TabGroup g) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline_rounded,
                color: AppTheme.accentCyan),
            title: Text('Rename group',
                style: GoogleFonts.inter(color: AppTheme.textPrimary)),
            onTap: () { Navigator.pop(context); _renameGroup(g); },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF6B6B)),
            title: Text('Ungroup & delete',
                style: GoogleFonts.inter(color: const Color(0xFFFF6B6B))),
            onTap: () { _svc.deleteGroup(g.id); Navigator.pop(context); },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _renameGroup(TabGroup g) async {
    final ctrl = TextEditingController(text: g.name);
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Rename group',
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl, autofocus: true,
          style: GoogleFonts.inter(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppTheme.divider),
                borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: AppTheme.accentCyan),
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) _svc.renameGroup(g.id, ctrl.text.trim());
              Navigator.pop(context);
            },
            child: Text('Save',
                style: GoogleFonts.inter(
                    color: AppTheme.accentCyan, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── UI ──────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _svc,
          builder: (_, __) {
            final ungrouped = _svc.tabsInGroup(null);
            return Column(children: [
              _header(),
              Expanded(
                child: _svc.tabs.isEmpty
                    ? _emptyState()
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                        children: [
                          for (final g in _svc.groups) ..._groupSection(g),
                          if (ungrouped.isNotEmpty) _grid(ungrouped),
                        ],
                      ),
              ),
            ]);
          },
        ),
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(children: [
          Container(
            width: 26, height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.textPrimary, width: 2),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text('${_svc.tabs.length}',
                style: GoogleFonts.inter(
                    color: AppTheme.textPrimary, fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Text('Tabs',
              style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.textPrimary, fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
            onPressed: () => Navigator.pop(context),
          ),
        ]),
      );

  List<Widget> _groupSection(TabGroup g) {
    final items = _svc.tabsInGroup(g.id);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Color(g.color).withOpacity(0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Color(g.color).withOpacity(0.5)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.circle, color: Color(g.color), size: 10),
              const SizedBox(width: 7),
              Text(g.name,
                  style: GoogleFonts.inter(
                      color: Color(g.color), fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Text('${items.length}',
                  style: GoogleFonts.inter(
                      color: Color(g.color).withOpacity(0.7), fontSize: 12)),
            ]),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded, color: AppTheme.textHint),
            onPressed: () => _groupMenu(g),
          ),
        ]),
      ),
      if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text('No tabs in this group yet',
              style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12)),
        )
      else
        _grid(items),
      const SizedBox(height: 6),
    ];
  }

  Widget _grid(List<BrowserTabItem> items) {
    final w = (MediaQuery.of(context).size.width - 32 - 12) / 2;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [for (final t in items) SizedBox(width: w, child: _tabCard(t))],
    );
  }

  Widget _tabCard(BrowserTabItem t) {
    return GestureDetector(
      onTap: () => _openTab(t),
      onLongPress: () => _tabActions(t),
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.divider),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // header row: favicon dot + close
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.divider)),
            ),
            child: Row(children: [
              Container(
                width: 18, height: 18,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [AppTheme.accentCyan, AppTheme.accentPurple]),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Icon(Icons.public_rounded, color: Colors.white, size: 12),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(t.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        color: AppTheme.textPrimary, fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ),
              GestureDetector(
                onTap: () => _svc.closeTab(t.id),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close_rounded, color: AppTheme.textHint, size: 16),
                ),
              ),
            ]),
          ),
          // body: host preview
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(Icons.language_rounded,
                      color: AppTheme.textHint, size: 22),
                  const SizedBox(height: 8),
                  Text(_host(t.url),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          color: AppTheme.textSecondary, fontSize: 11.5)),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.tab_rounded, color: AppTheme.textHint, size: 56),
          const SizedBox(height: 14),
          Text('No open tabs',
              style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.textPrimary, fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Tap + to open a new tab',
              style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 13)),
        ]),
      );

  Widget _bottomBar() => Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          border: Border(top: BorderSide(color: AppTheme.divider)),
        ),
        padding: EdgeInsets.fromLTRB(
            20, 10, 20, MediaQuery.of(context).padding.bottom + 10),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.grid_view_rounded, color: AppTheme.textSecondary),
            onPressed: () => _newGroup(),
            tooltip: 'New tab group',
          ),
          const Spacer(),
          GestureDetector(
            onTap: _newTab,
            child: Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppTheme.accentCyan, AppTheme.accentPurple]),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                      color: AppTheme.accentCyan.withOpacity(0.4), blurRadius: 14),
                ],
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded, color: AppTheme.textSecondary),
            onPressed: _moreMenu,
            tooltip: 'More',
          ),
        ]),
      );

  void _moreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 14),
          ListTile(
            leading: const Icon(Icons.add_box_outlined, color: AppTheme.accentCyan),
            title: Text('New tab',
                style: GoogleFonts.inter(color: AppTheme.textPrimary)),
            onTap: () { Navigator.pop(context); _newTab(); },
          ),
          ListTile(
            leading: const Icon(Icons.remove_red_eye_outlined,
                color: AppTheme.accentPurple),
            title: Text('New private tab',
                style: GoogleFonts.inter(color: AppTheme.textPrimary)),
            onTap: () { Navigator.pop(context); _newPrivateTab(); },
          ),
          ListTile(
            leading: const Icon(Icons.grid_view_rounded, color: AppTheme.accentCyan),
            title: Text('New tab group',
                style: GoogleFonts.inter(color: AppTheme.textPrimary)),
            onTap: () { Navigator.pop(context); _newGroup(); },
          ),
          ListTile(
            leading: const Icon(Icons.close_rounded, color: Color(0xFFFF6B6B)),
            title: Text('Close all tabs',
                style: GoogleFonts.inter(color: const Color(0xFFFF6B6B))),
            onTap: () { _svc.closeAll(); Navigator.pop(context); },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}
