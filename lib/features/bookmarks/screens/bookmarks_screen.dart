import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/database/local_db.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import '../../browser/screens/browser_view.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  List<Map<String, dynamic>> _bookmarks = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _bookmarks = LocalDB.getBookmarks());

  Future<void> _delete(String url) async {
    await LocalDB.removeBookmark(url);
    _load();
  }

  void _open(String url) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => BrowserView(initialQuery: url)));
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Clear All Bookmarks',
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.bold)),
        content: Text('This action cannot be undone.',
            style: GoogleFonts.inter(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel',
                  style: GoogleFonts.inter(color: AppTheme.textHint))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Clear',
                  style: GoogleFonts.inter(color: AppTheme.danger))),
        ],
      ),
    );
    if (ok == true) {
      await LocalDB.clearBookmarks();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppTheme.textSecondary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Bookmarks',
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        actions: [
          if (_bookmarks.isNotEmpty)
            TextButton(
              onPressed: _confirmClear,
              child: Text('Clear all',
                  style: GoogleFonts.inter(
                      color: AppTheme.danger, fontSize: 13)),
            ),
        ],
      ),
      body: _bookmarks.isEmpty ? _buildEmpty() : _buildList(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Icon(Icons.bookmark_border_rounded,
              color: AppTheme.textHint, size: 36),
        ),
        const SizedBox(height: 20),
        Text('No bookmarks yet',
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('Tap ★ in the browser to save pages',
            style: GoogleFonts.inter(
                color: AppTheme.textHint, fontSize: 13)),
      ]),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      itemCount: _bookmarks.length,
      separatorBuilder: (_, __) =>
          const Divider(color: AppTheme.divider, height: 1),
      itemBuilder: (_, i) => _buildTile(_bookmarks[i]),
    );
  }

  Widget _buildTile(Map<String, dynamic> item) {
    final url   = item['url']   as String? ?? '';
    final title = item['title'] as String? ?? url;
    final host  = Uri.tryParse(url)?.host ?? url;

    return Dismissible(
      key: ValueKey(url),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppTheme.danger.withOpacity(0.15),
        child: const Icon(Icons.delete_outline_rounded,
            color: AppTheme.danger),
      ),
      onDismissed: (_) => _delete(url),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 4),
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              title.isNotEmpty ? title[0].toUpperCase() : 'B',
              style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.accentCyan,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ),
        title: Text(title,
            style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Text(host,
            style: GoogleFonts.inter(
                color: AppTheme.textHint, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.arrow_forward_ios_rounded,
            color: AppTheme.textHint, size: 14),
        onTap: () => _open(url),
      ),
    );
  }
}
