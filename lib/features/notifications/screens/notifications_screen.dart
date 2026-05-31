// lib/features/notifications/screens/notifications_screen.dart
import 'dart:async';
import 'package:nova_x/core/services/rewards_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/services/advert_service.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import 'package:nova_x/features/browser/screens/browser_view.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AdvertModel> _adverts = [];
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _hasError = false; });
    try {
      final ads = await AdvertService.fetchAdverts();
      if (!mounted) return;
      await AdvertService.markAllRead(ads); // clears badge
      setState(() { _adverts = ads; _loading = false; });
    } catch (_) {
      setState(() { _loading = false; _hasError = true; });
    }
  }

  Future<void> _openUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    if (mounted) {
      Navigator.push(context, MaterialPageRoute(
          builder: (_) => BrowserView(initialQuery: url)));
    }
  }

  void _dismiss(AdvertModel ad) {
    setState(() => _adverts.remove(ad));
    AdvertService.dismiss(ad.id);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Removed', style: GoogleFonts.inter(color: Colors.white)),
      backgroundColor: AppTheme.bgElevated,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Group adverts by date ─────────────────────────────────────────────────
  List<Object> get _grouped {
    final items = <Object>[];
    String? lastDate;
    for (final ad in _adverts) {
      final dateLabel = _formatDateLabel(ad.createdAt);
      if (dateLabel != lastDate) {
        items.add(dateLabel);
        lastDate = dateLabel;
      }
      items.add(ad);
    }
    return items;
  }

  String _formatDateLabel(DateTime dt) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d     = DateTime(dt.year, dt.month, dt.day);
    final diff  = today.difference(d).inDays;
    final months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    final day  = dt.day;
    final sfx  = _daySuffix(day);
    final time = _formatTime(dt);

    if (diff == 0) return 'Today $time';
    if (diff == 1) return 'Yesterday $time';
    return '${months[dt.month-1]} $day$sfx $time';
  }

  String _daySuffix(int d) {
    if (d >= 11 && d <= 13) return 'th';
    switch (d % 10) {
      case 1: return 'st';
      case 2: return 'nd';
      case 3: return 'rd';
      default: return 'th';
    }
  }

  String _formatTime(DateTime dt) {
    final h  = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m  = dt.minute.toString().padLeft(2, '0');
    final pm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $pm';
  }

  // ═════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Notifications', style: GoogleFonts.spaceGrotesk(
            color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
        actions: [
          if (_adverts.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh_rounded,
                  color: AppTheme.textHint, size: 20),
              onPressed: _load,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(color: AppTheme.divider, height: 1),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(
              color: AppTheme.accentCyan))
          : _hasError
              ? _errorState()
              : _adverts.isEmpty
                  ? _emptyState()
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppTheme.accentCyan,
                      backgroundColor: AppTheme.bgCard,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: _grouped.length,
                        itemBuilder: (_, i) {
                          final item = _grouped[i];
                          if (item is String) return _dateHeader(item);
                          return _advertCard(item as AdvertModel);
                        },
                      ),
                    ),
    );
  }

  // ── Date header ───────────────────────────────────────────────────────────
  Widget _dateHeader(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
    child: Text(label, style: GoogleFonts.inter(
        color: AppTheme.textHint, fontSize: 12,
        fontWeight: FontWeight.w700, letterSpacing: .5)),
  );

  // ── Advert card ───────────────────────────────────────────────────────────
  Widget _advertCard(AdvertModel ad) {
    return Dismissible(
      key: Key('ad_${ad.id}'),
      direction: DismissDirection.horizontal,
      background: _swipeBg(
          color: AppTheme.danger,
          icon: Icons.delete_rounded,
          label: 'Delete',
          alignment: Alignment.centerLeft),
      secondaryBackground: _swipeBg(
          color: AppTheme.success,
          icon: Icons.open_in_browser_rounded,
          label: 'Open',
          alignment: Alignment.centerRight),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          // Swipe right → delete
          _dismiss(ad);
          return true;
        } else {
          // Swipe left → open URL
          if (ad.url != null && ad.url!.isNotEmpty) {
            await _openUrl(ad.url);
          }
          return false;
        }
      },
      child: GestureDetector(
        onTap: () { RewardsService.trackNotif(ad.id); _openUrl(ad.url); },
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.divider),
            boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Media ───────────────────────────────────────────────────
              if (ad.mediaUrl != null && ad.mediaType != 'none')
                _mediaWidget(ad),

              // ── Text content ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title + NOVA badge
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.notifications_rounded,
                            color: Colors.white, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(ad.title, style: GoogleFonts.spaceGrotesk(
                              color: Colors.white, fontSize: 15,
                              fontWeight: FontWeight.w800)),
                          if (ad.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(ad.description, style: GoogleFonts.inter(
                                color: AppTheme.textSecondary, fontSize: 13,
                                height: 1.5)),
                          ],
                        ],
                      )),
                    ]),

                    // URL tag
                    if (ad.url != null && ad.url!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppTheme.accentCyan.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppTheme.accentCyan.withOpacity(0.3)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.link_rounded,
                              color: AppTheme.accentCyan, size: 12),
                          const SizedBox(width: 5),
                          Text('Tap to open link', style: GoogleFonts.inter(
                              color: AppTheme.accentCyan, fontSize: 11,
                              fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ],

                    // Swipe hint
                    const SizedBox(height: 10),
                    Row(children: [
                      const Icon(Icons.swipe_rounded,
                          color: AppTheme.textHint, size: 12),
                      const SizedBox(width: 4),
                      Text('Swipe right to delete  ·  Swipe left to open',
                          style: GoogleFonts.inter(
                              color: AppTheme.textHint, fontSize: 10)),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Media widget (image or video) ─────────────────────────────────────────
  Widget _mediaWidget(AdvertModel ad) {
    if (ad.mediaType == 'video') {
      return _VideoCard(url: ad.mediaUrl!);
    }
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      child: Image.network(
        ad.mediaUrl!,
        width: double.infinity,
        height: 220,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, prog) => prog == null
            ? child
            : Container(height: 220,
                color: AppTheme.bgElevated,
                child: const Center(child: CircularProgressIndicator(
                    color: AppTheme.accentCyan, strokeWidth: 2))),
        errorBuilder: (_, __, ___) => Container(
          height: 120, color: AppTheme.bgElevated,
          child: const Center(child: Icon(Icons.broken_image_outlined,
              color: AppTheme.textHint, size: 36))),
      ),
    );
  }

  // ── Swipe background ──────────────────────────────────────────────────────
  Widget _swipeBg({required Color color, required IconData icon,
      required String label, required Alignment alignment}) =>
      Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(18)),
        alignment: alignment,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.inter(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _emptyState() => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.notifications_none_rounded,
          color: AppTheme.textHint, size: 64),
      const SizedBox(height: 16),
      Text('No notifications yet', style: GoogleFonts.spaceGrotesk(
          color: AppTheme.textPrimary, fontSize: 18,
          fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text('Adverts and updates from NOVA X\nwill appear here.',
          style: GoogleFonts.inter(color: AppTheme.textHint,
              fontSize: 14, height: 1.6),
          textAlign: TextAlign.center),
    ],
  ));

  Widget _errorState() => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.wifi_off_rounded, color: AppTheme.textHint, size: 48),
      const SizedBox(height: 12),
      Text('Could not load notifications', style: GoogleFonts.inter(
          color: AppTheme.textHint, fontSize: 14)),
      const SizedBox(height: 12),
      TextButton.icon(
        onPressed: _load,
        icon: const Icon(Icons.refresh_rounded, color: AppTheme.accentCyan),
        label: Text('Retry', style: GoogleFonts.inter(
            color: AppTheme.accentCyan, fontWeight: FontWeight.w700)),
      ),
    ],
  ));
}

// ── Video card widget ─────────────────────────────────────────────────────────
class _VideoCard extends StatefulWidget {
  final String url;
  const _VideoCard({required this.url});
  @override State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard> {
  VideoPlayerController? _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) setState(() => _ready = true);
      });
  }

  @override
  void dispose() { _ctrl?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
    child: SizedBox(
      height: 220, width: double.infinity,
      child: _ready && _ctrl != null
          ? Stack(children: [
              VideoPlayer(_ctrl!),
              // Play/pause overlay
              Center(child: GestureDetector(
                onTap: () => setState(() =>
                    _ctrl!.value.isPlaying
                        ? _ctrl!.pause() : _ctrl!.play()),
                child: Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: Colors.black54, shape: BoxShape.circle),
                  child: Icon(
                    _ctrl!.value.isPlaying
                        ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white, size: 28),
                ),
              )),
            ])
          : Container(color: AppTheme.bgElevated,
              child: const Center(child: CircularProgressIndicator(
                  color: AppTheme.accentCyan, strokeWidth: 2))),
    ),
  );
}
