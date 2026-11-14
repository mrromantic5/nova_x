// lib/features/downloads/screens/downloads_screen.dart
//
// 3.13.1: the Downloads page, like Chrome's — live progress, pause / resume /
// cancel / retry, open, share, delete, and where files are saved
// (Download/NOVA X, a folder you choose, or ask every time).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/theme/app_theme.dart';

import '../../browser/screens/browser_view.dart';
import '../download_manager.dart';
import '../download_names.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});
  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final DownloadManager _dm = DownloadManager.instance;
  String _query = '';
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _dm.addListener(_onChange);
    _dm.ensureLoaded();
  }

  @override
  void dispose() {
    _dm.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: AppTheme.bgElevated,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
  }

  static (IconData, Color) _iconFor(String name, String mime) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final m = mime.toLowerCase();
    if (m.startsWith('image/') || ['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg', 'bmp', 'heic'].contains(ext)) {
      return (Icons.image_rounded, const Color(0xFF22C55E));
    }
    if (m.startsWith('video/') || ['mp4', 'mkv', 'avi', 'mov', 'webm', '3gp'].contains(ext)) {
      return (Icons.movie_rounded, const Color(0xFFF43F5E));
    }
    if (m.startsWith('audio/') || ['mp3', 'aac', 'ogg', 'flac', 'wav', 'm4a'].contains(ext)) {
      return (Icons.music_note_rounded, const Color(0xFFA855F7));
    }
    if (ext == 'pdf' || m == 'application/pdf') return (Icons.picture_as_pdf_rounded, const Color(0xFFEF4444));
    if (['zip', 'rar', 'tar', 'gz', '7z'].contains(ext)) return (Icons.folder_zip_rounded, const Color(0xFFF59E0B));
    if (ext == 'apk') return (Icons.android_rounded, const Color(0xFF84CC16));
    if (['doc', 'docx', 'txt', 'odt', 'rtf', 'md'].contains(ext)) return (Icons.description_rounded, const Color(0xFF3B82F6));
    if (['xls', 'xlsx', 'csv'].contains(ext)) return (Icons.table_chart_rounded, const Color(0xFF10B981));
    if (['ppt', 'pptx'].contains(ext)) return (Icons.slideshow_rounded, const Color(0xFFF97316));
    return (Icons.insert_drive_file_rounded, AppTheme.accentCyan);
  }

  static String _when(DateTime dt) {
    final now = DateTime.now();
    final d = DateTime(dt.year, dt.month, dt.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}${dt.year == now.year ? '' : ', ${dt.year}'}';
  }

  static String _host(String url) {
    final h = Uri.tryParse(url)?.host ?? '';
    return h.startsWith('www.') ? h.substring(4) : h;
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _open(DownloadTask t) async {
    if (t.status != DlStatus.completed) return;
    final ok = await DownloadsPlatform.open(t.savedUri, t.mime);
    if (!ok && mounted) {
      final exists = await DownloadsPlatform.exists(t.savedUri);
      if (!mounted) return;
      _snack(exists ? 'No app on this phone can open this file' : 'The file was moved or deleted');
    }
  }

  Future<void> _confirmDelete(DownloadTask t) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Delete file?', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text('"${t.name}" will be deleted from your phone.',
            style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final ok = await _dm.deleteFile(t);
    if (mounted) _snack(ok ? 'File deleted' : 'Removed from list (the file was already gone)');
  }

  void _menu(DownloadTask t) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) {
        Widget item(IconData icon, String label, VoidCallback fn, {Color? color}) => ListTile(
              leading: Icon(icon, color: color ?? AppTheme.textSecondary, size: 22),
              title: Text(label, style: GoogleFonts.inter(color: color ?? Colors.white, fontSize: 14.5)),
              onTap: () {
                Navigator.pop(c);
                fn();
              },
            );
        final done = t.status == DlStatus.completed;
        final isWeb = t.url.startsWith('http');
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Text(t.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
            if (done) item(Icons.open_in_new_rounded, 'Open', () => _open(t)),
            if (done)
              item(Icons.share_rounded, 'Share', () async {
                if (!await DownloadsPlatform.share(t.savedUri, t.mime) && mounted) _snack('Couldn\'t share this file');
              }),
            if (done && t.dest == 'downloads')
              item(Icons.folder_open_rounded, 'Show in Downloads app', () async {
                if (!await DownloadsPlatform.openDownloadsApp() && mounted) _snack('No Downloads app found');
              }),
            if (isWeb)
              item(Icons.public_rounded, 'Open source page', () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => BrowserView(initialQuery: t.referer.isNotEmpty ? t.referer : t.url)));
              }),
            if (isWeb)
              item(Icons.link_rounded, 'Copy download link', () {
                Clipboard.setData(ClipboardData(text: t.url));
                _snack('Link copied');
              }),
            if (done) item(Icons.delete_outline_rounded, 'Delete file', () => _confirmDelete(t), color: AppTheme.danger),
            item(Icons.playlist_remove_rounded, 'Remove from list', () => _dm.remove(t)),
            const SizedBox(height: 6),
          ]),
        );
      },
    );
  }

  Future<void> _locationSheet() async {
    await DownloadPrompts.locationSettings(context);
  }

  Future<void> _clear() async {
    final n = _dm.tasks.where((t) => t.finished || t.status == DlStatus.paused).length;
    if (n == 0) {
      _snack('Nothing to clear');
      return;
    }
    await _dm.clearFinished();
    if (mounted) _snack('List cleared. Your files are still on the phone.');
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final all = _dm.tasks;
    final list = q.isEmpty ? all : all.where((t) => t.name.toLowerCase().contains(q) || t.url.toLowerCase().contains(q)).toList();

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textSecondary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: _searching
            ? TextField(
                autofocus: true,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
                cursorColor: AppTheme.accentCyan,
                decoration: InputDecoration(
                  hintText: 'Search downloads',
                  hintStyle: GoogleFonts.inter(color: AppTheme.textHint),
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _query = v),
              )
            : Text('Downloads',
                style: GoogleFonts.spaceGrotesk(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded, color: AppTheme.textSecondary),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _query = '';
            }),
          ),
          PopupMenuButton<String>(
            color: AppTheme.bgCard,
            icon: const Icon(Icons.more_vert_rounded, color: AppTheme.textSecondary),
            onSelected: (v) {
              if (v == 'clear') _clear();
              if (v == 'location') _locationSheet();
              if (v == 'app') DownloadsPlatform.openDownloadsApp();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'location', child: Text('Download location', style: GoogleFonts.inter(color: Colors.white))),
              PopupMenuItem(value: 'app', child: Text('Open phone\'s Downloads', style: GoogleFonts.inter(color: Colors.white))),
              PopupMenuItem(value: 'clear', child: Text('Clear list', style: GoogleFonts.inter(color: Colors.white))),
            ],
          ),
        ],
      ),
      body: Column(children: [
        _locationChip(),
        Expanded(child: list.isEmpty ? _empty(q.isNotEmpty) : _list(list)),
      ]),
    );
  }

  Widget _locationChip() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _locationSheet,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              const Icon(Icons.folder_rounded, color: Color(0xFFF59E0B), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Saving to', style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11)),
                  Text(_dm.destinationLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                ]),
              ),
              Text('Change', style: GoogleFonts.inter(color: AppTheme.accentCyan, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _empty(bool searching) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(22)),
            child: const Icon(Icons.download_rounded, color: AppTheme.accentCyan, size: 36),
          ),
          const SizedBox(height: 16),
          Text(searching ? 'No matching downloads' : 'No downloads yet',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            searching ? 'Try a different name.' : 'Files you download in NOVA X appear here and are saved to ${_dm.destinationLabel}.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ]),
      ),
    );
  }

  Widget _list(List<DownloadTask> list) {
    final children = <Widget>[];
    String? lastHeader;
    for (final t in list) {
      final header = t.active || t.status == DlStatus.paused ? 'In progress' : _when(t.finishedAt ?? t.createdAt);
      if (header != lastHeader) {
        lastHeader = header;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Text(header,
              style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
        ));
      }
      children.add(_tile(t));
    }
    children.add(const SizedBox(height: 24));
    return ListView(padding: EdgeInsets.zero, children: children);
  }

  Widget _tile(DownloadTask t) {
    final (icon, color) = _iconFor(t.name, t.mime);
    final host = _host(t.url);
    String line;
    Color lineColor = AppTheme.textSecondary;
    switch (t.status) {
      case DlStatus.queued:
        line = 'Waiting…';
        break;
      case DlStatus.running:
        final left = t.total > 0 ? DownloadNames.timeLeft(t.total - t.received, t.speed) : '';
        line = [
          t.total > 0 ? '${DownloadNames.size(t.received)} of ${DownloadNames.size(t.total)}' : DownloadNames.size(t.received),
          if (t.speed > 0) '${DownloadNames.size(t.speed.round())}/s',
          if (left.isNotEmpty) left,
        ].join(' · ');
        break;
      case DlStatus.saving:
        line = 'Saving to ${t.dest == 'downloads' ? 'Download/NOVA X' : 'your folder'}…';
        break;
      case DlStatus.paused:
        line = 'Paused · ${t.total > 0 ? '${DownloadNames.size(t.received)} of ${DownloadNames.size(t.total)}' : DownloadNames.size(t.received)}';
        break;
      case DlStatus.completed:
        line = [
          if (t.total > 0) DownloadNames.size(t.total),
          if (host.isNotEmpty) host,
          if (t.savedLocation.isNotEmpty) t.savedLocation,
        ].join(' · ');
        break;
      case DlStatus.failed:
        line = t.error.isNotEmpty ? t.error : 'Failed';
        lineColor = AppTheme.danger;
        break;
      case DlStatus.canceled:
        line = 'Canceled${host.isNotEmpty ? ' · $host' : ''}';
        lineColor = AppTheme.textHint;
        break;
    }

    final showBar = t.status == DlStatus.running || t.status == DlStatus.paused || t.status == DlStatus.queued || t.status == DlStatus.saving;
    final dim = t.status == DlStatus.canceled;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: t.status == DlStatus.completed ? () => _open(t) : null,
          onLongPress: () => _menu(t),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Opacity(
                opacity: dim ? 0.45 : 1,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: color, size: 22),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: dim ? AppTheme.textHint : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        decoration: dim ? TextDecoration.lineThrough : null,
                      )),
                  const SizedBox(height: 3),
                  Text(line,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(color: lineColor, fontSize: 12)),
                  if (showBar) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        minHeight: 5,
                        value: t.status == DlStatus.saving || t.status == DlStatus.queued ? null : t.fraction,
                        backgroundColor: AppTheme.bgElevated,
                        valueColor: AlwaysStoppedAnimation(t.status == DlStatus.paused ? AppTheme.textHint : AppTheme.accentCyan),
                      ),
                    ),
                  ],
                ]),
              ),
              const SizedBox(width: 4),
              ..._actions(t),
            ]),
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(DownloadTask t) {
    Widget btn(IconData i, String tip, VoidCallback fn, {Color color = AppTheme.textSecondary}) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          icon: Icon(i, color: color, size: 22),
          onPressed: fn,
        );
    switch (t.status) {
      case DlStatus.running:
      case DlStatus.queued:
        return [
          btn(Icons.pause_rounded, 'Pause', () => _dm.pause(t)),
          btn(Icons.close_rounded, 'Cancel', () => _dm.cancel(t)),
        ];
      case DlStatus.paused:
        return [
          btn(Icons.play_arrow_rounded, 'Resume', () => _dm.resume(t), color: AppTheme.accentCyan),
          btn(Icons.close_rounded, 'Cancel', () => _dm.cancel(t)),
        ];
      case DlStatus.failed:
        return [
          btn(Icons.refresh_rounded, 'Retry', () => _dm.retry(t), color: AppTheme.accentCyan),
          btn(Icons.more_vert_rounded, 'More', () => _menu(t)),
        ];
      case DlStatus.saving:
        return const [SizedBox(width: 44)];
      case DlStatus.completed:
      case DlStatus.canceled:
        return [btn(Icons.more_vert_rounded, 'More', () => _menu(t))];
    }
  }
}

/// Sheets used by the browser and the Downloads page.
class DownloadPrompts {
  DownloadPrompts._();

  /// "Download location" settings sheet.
  static Future<void> locationSettings(BuildContext context) async {
    final dm = DownloadManager.instance;
    await dm.ensureLoaded();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => StatefulBuilder(builder: (c, setSheet) {
        Widget option(DlDestMode mode, IconData icon, Color color, String title, String sub, Future<void> Function() onTap) {
          final selected = dm.destMode == mode;
          return ListTile(
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 20),
            ),
            title: Text(title, style: GoogleFonts.inter(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600)),
            subtitle: Text(sub, style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12)),
            trailing: Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: selected ? AppTheme.accentCyan : AppTheme.textHint),
            onTap: () async {
              await onTap();
              setSheet(() {});
            },
          );
        }

        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Text('Download location',
                  style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
            ),
            option(DlDestMode.downloads, Icons.download_rounded, const Color(0xFF22C55E), 'Downloads',
                'Download/NOVA X on this phone', () => dm.setDestMode(DlDestMode.downloads)),
            option(
              DlDestMode.folder,
              Icons.create_new_folder_rounded,
              const Color(0xFFF59E0B),
              dm.folderTree.isNotEmpty ? dm.folderName : 'Choose a folder',
              dm.folderTree.isNotEmpty ? 'Your chosen folder' : 'Any folder, SD card or cloud drive',
              () async {
                if (dm.folderTree.isNotEmpty && dm.destMode != DlDestMode.folder) {
                  await dm.setDestMode(DlDestMode.folder);
                } else {
                  await dm.chooseFolder();
                }
              },
            ),
            if (dm.folderTree.isNotEmpty)
              TextButton.icon(
                onPressed: () async {
                  await dm.chooseFolder();
                  setSheet(() {});
                },
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text('Choose a different folder'),
              ),
            option(DlDestMode.ask, Icons.help_outline_rounded, const Color(0xFF38BDF8), 'Ask every time',
                'Pick where to save each download', () => dm.setDestMode(DlDestMode.ask)),
            const SizedBox(height: 10),
          ]),
        );
      }),
    );
  }

  /// For "Ask every time": where should this file go? Returns 'downloads',
  /// a folder address, or null when the user cancels.
  static Future<String?> askDestination(BuildContext context, String fileName) async {
    final dm = DownloadManager.instance;
    await dm.ensureLoaded();
    if (!context.mounted) return null;
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
            child: Text('Save file', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text(fileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13)),
          ),
          ListTile(
            leading: const Icon(Icons.download_rounded, color: Color(0xFF22C55E)),
            title: Text('Downloads', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle: Text('Download/NOVA X', style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12)),
            onTap: () => Navigator.pop(c, 'downloads'),
          ),
          if (dm.folderTree.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.folder_rounded, color: Color(0xFFF59E0B)),
              title: Text(dm.folderName, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
              subtitle: Text('Your folder', style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12)),
              onTap: () => Navigator.pop(c, dm.folderTree),
            ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_rounded, color: Color(0xFF38BDF8)),
            title: Text('Choose a folder…', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
            onTap: () async {
              final r = await DownloadsPlatform.pickFolder();
              if (!c.mounted) return;
              Navigator.pop(c, (r != null && (r['tree'] ?? '').isNotEmpty) ? r['tree'] : null);
            },
          ),
          ListTile(
            leading: const Icon(Icons.close_rounded, color: AppTheme.textHint),
            title: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textSecondary)),
            onTap: () => Navigator.pop(c),
          ),
          const SizedBox(height: 6),
        ]),
      ),
    );
  }
}
