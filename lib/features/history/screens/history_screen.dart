import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/database/local_db.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import '../../browser/screens/browser_view.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _history = LocalDB.getHistory());

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Clear History',
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.bold)),
        content: Text('All browsing history will be deleted.',
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
      await LocalDB.clearHistory();
      _load();
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
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
        title: Text('History',
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        actions: [
          if (_history.isNotEmpty)
            TextButton(
              onPressed: _confirmClear,
              child: Text('Clear',
                  style: GoogleFonts.inter(
                      color: AppTheme.danger, fontSize: 13)),
            ),
        ],
      ),
      body: _history.isEmpty ? _buildEmpty() : _buildList(),
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
          child: const Icon(Icons.history_rounded,
              color: AppTheme.textHint, size: 36),
        ),
        const SizedBox(height: 20),
        Text('No history yet',
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('Sites you visit will appear here',
            style: GoogleFonts.inter(
                color: AppTheme.textHint, fontSize: 13)),
      ]),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      itemCount: _history.length,
      separatorBuilder: (_, __) =>
          const Divider(color: AppTheme.divider, height: 1),
      itemBuilder: (_, i) => _buildTile(_history[i]),
    );
  }

  Widget _buildTile(Map<String, dynamic> item) {
    final url   = item['url']       as String? ?? '';
    final title = item['title']     as String? ?? url;
    final date  = _formatDate(item['timestamp'] as String?);
    final host  = Uri.tryParse(url)?.host ?? url;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.public_rounded,
            color: AppTheme.textHint, size: 20),
      ),
      title: Text(title,
          style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      subtitle: Row(children: [
        Expanded(
          child: Text(host,
              style: GoogleFonts.inter(
                  color: AppTheme.textHint, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        Text(date,
            style: GoogleFonts.inter(
                color: AppTheme.textHint, fontSize: 10)),
      ]),
      trailing: const Icon(Icons.north_east_rounded,
          color: AppTheme.textHint, size: 14),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => BrowserView(initialQuery: url)),
      ),
    );
  }
}
