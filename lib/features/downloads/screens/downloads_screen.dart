import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/database/local_db.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import '../../browser/screens/browser_view.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});
  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  List<Map<String, dynamic>> _downloads = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() => _downloads = LocalDB.getDownloads());

  IconData _iconFor(String? mime, String filename) {
    final ext = filename.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg'].contains(ext)) {
      return Icons.image_outlined;
    }
    if (['mp4', 'mkv', 'avi', 'mov', 'webm'].contains(ext)) {
      return Icons.movie_outlined;
    }
    if (['mp3', 'aac', 'ogg', 'flac', 'wav'].contains(ext)) {
      return Icons.music_note_outlined;
    }
    if (['pdf'].contains(ext)) return Icons.picture_as_pdf_outlined;
    if (['zip', 'rar', 'tar', 'gz'].contains(ext)) return Icons.folder_zip_outlined;
    if (['apk'].contains(ext)) return Icons.android_outlined;
    if (['doc', 'docx', 'txt', 'odt'].contains(ext)) return Icons.description_outlined;
    return Icons.download_outlined;
  }

  String _formatSize(dynamic bytes) {
    if (bytes == null || bytes == 0) return 'Unknown size';
    final b = bytes is int ? bytes : int.tryParse(bytes.toString()) ?? 0;
    if (b < 1024)      return '$b B';
    if (b < 1048576)   return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1048576).toStringAsFixed(1)} MB';
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    try {
      final dt   = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1)  return 'Just now';
      if (diff.inHours   < 1)  return '${diff.inMinutes}m ago';
      if (diff.inDays    < 1)  return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) { return ''; }
  }

  // ═══════════════════════════════════════════════════════════════════════════
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
        title: Text('Downloads',
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary,
                fontSize: 18, fontWeight: FontWeight.bold)),
        actions: [
          if (_downloads.isNotEmpty)
            TextButton(
              onPressed: _confirmClear,
              child: Text('Clear',
                  style: GoogleFonts.inter(
                      color: AppTheme.danger, fontSize: 13)),
            ),
        ],
      ),
      body: _downloads.isEmpty ? _buildEmpty() : _buildList(),
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 80, height: 80,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Icon(Icons.download_outlined,
            color: AppTheme.textHint, size: 36),
      ),
      const SizedBox(height: 20),
      Text('No downloads yet',
          style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textPrimary,
              fontSize: 18, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Text(
          'Files you download from websites will appear here',
          style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ),
    ]),
  );

  Widget _buildList() => ListView.separated(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
    itemCount: _downloads.length,
    separatorBuilder: (_, __) =>
        const Divider(color: AppTheme.divider, height: 1),
    itemBuilder: (_, i) => _buildTile(_downloads[i]),
  );

  Widget _buildTile(Map<String, dynamic> item) {
    final filename = item['filename'] as String? ?? 'Unknown file';
    final url      = item['url']      as String? ?? '';
    final mime     = item['mime']     as String?;
    final size     = item['size'];
    final time     = item['timestamp'] as String?;
    final icon     = _iconFor(mime, filename);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 6),
      leading: Container(
        width: 46, height: 46,
        decoration: BoxDecoration(
          color: AppTheme.primaryBlue.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppTheme.primaryBlue, size: 22),
      ),
      title: Text(filename,
          style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 13.5, fontWeight: FontWeight.w500),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_formatSize(size),
              style: GoogleFonts.inter(
                  color: AppTheme.textHint, fontSize: 11)),
          Text(_timeAgo(time),
              style: GoogleFonts.inter(
                  color: AppTheme.textHint, fontSize: 10)),
        ],
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        color: AppTheme.bgCard,
        icon: const Icon(Icons.more_vert_rounded,
            color: AppTheme.textHint, size: 18),
        onSelected: (v) {
          if (v == 'open') {
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => BrowserView(initialQuery: url)));
          } else if (v == 'copy') {
            Clipboard.setData(ClipboardData(text: url));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('URL copied',
                  style: GoogleFonts.inter(color: Colors.white)),
              backgroundColor: AppTheme.bgElevated,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ));
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'open',
            child: Row(children: [
              const Icon(Icons.open_in_browser_rounded,
                  color: AppTheme.textSecondary, size: 16),
              const SizedBox(width: 10),
              Text('Open URL',
                  style: GoogleFonts.inter(
                      color: AppTheme.textPrimary, fontSize: 13)),
            ]),
          ),
          PopupMenuItem(
            value: 'copy',
            child: Row(children: [
              const Icon(Icons.copy_rounded,
                  color: AppTheme.textSecondary, size: 16),
              const SizedBox(width: 10),
              Text('Copy URL',
                  style: GoogleFonts.inter(
                      color: AppTheme.textPrimary, fontSize: 13)),
            ]),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Clear Downloads',
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        content: Text('Remove all download records?',
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
      await LocalDB.clearDownloads();
      _load();
    }
  }
}
