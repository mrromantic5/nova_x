// lib/features/offline/screens/offline_pages_screen.dart
//
// Lists pages saved for offline reading. Tap to open the offline copy; delete
// to remove it (and its file).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import 'package:nova_x/core/services/offline_service.dart';
import 'package:nova_x/features/offline/screens/offline_viewer_screen.dart';

class OfflinePagesScreen extends StatefulWidget {
  const OfflinePagesScreen({super.key});
  @override
  State<OfflinePagesScreen> createState() => _OfflinePagesScreenState();
}

class _OfflinePagesScreenState extends State<OfflinePagesScreen> {
  final _svc = OfflineService.instance;

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

  String _when(int ms) {
    if (ms == 0) return '';
    final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        title: Text('Offline Pages',
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
      ),
      body: ListenableBuilder(
        listenable: _svc,
        builder: (_, __) {
          if (_svc.pages.isEmpty) return _empty();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: _svc.pages.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _tile(_svc.pages[i]),
          );
        },
      ),
    );
  }

  Widget _tile(OfflinePage p) => GestureDetector(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    OfflineViewerScreen(path: p.path, title: p.title))),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF00C853).withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.offline_pin_rounded,
                  color: Color(0xFF00C853), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Row(children: [
                  Flexible(
                    child: Text(_host(p.url),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11.5)),
                  ),
                  if (_when(p.savedAt).isNotEmpty)
                    Text('  ·  ${_when(p.savedAt)}',
                        style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11.5)),
                ]),
              ]),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.textHint),
              onPressed: () => _svc.remove(p.id),
            ),
          ]),
        ),
      );

  Widget _empty() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_download_outlined, color: AppTheme.textHint, size: 56),
          const SizedBox(height: 14),
          Text('No offline pages yet',
              style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Open a page in the browser, then tap the ⋮ menu → "Save page offline" to read it later without internet.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 13, height: 1.5),
            ),
          ),
        ]),
      );
}
