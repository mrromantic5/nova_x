// lib/features/nova_capture/screens/capture_dashboard.dart
//
// NOVA Capture home: what is happening now, quick actions, recent captures,
// storage and permissions — every state ends in success, failure or cancel.

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/capture_controller.dart';
import '../models/capture_models.dart';
import '../models/media_asset.dart';
import '../services/media_library_service.dart';
import '../services/webpage_capture_service.dart';
import '../widgets/capture_flows.dart';
import '../widgets/capture_thumb.dart';
import '../widgets/capture_ui.dart';
import 'capture_media_library.dart';
import 'recording_settings_screen.dart';

class CaptureDashboard extends StatefulWidget {
  const CaptureDashboard({super.key});

  @override
  State<CaptureDashboard> createState() => _CaptureDashboardState();
}

class _CaptureDashboardState extends State<CaptureDashboard> with WidgetsBindingObserver {
  final _c = CaptureController.instance;
  List<MediaAsset> _recent = const [];
  int _captureBytes = 0;
  int _free = -1;
  bool _loading = true;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c.libraryVersion.addListener(_load);
    _init();
  }

  Future<void> _init() async {
    await _c.init();
    await _c.refresh();
    final lost = _c.capabilities.lostRecordings;
    if (lost > 0) {
      captureToast('A recording that was running when NOVA X was closed by Android could not be recovered.', ok: false);
    }
    await _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Android settings (microphone, overlay…): show the new status.
    if (state == AppLifecycleState.resumed) _c.refreshCapabilities();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.libraryVersion.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final items = await MediaLibraryService.instance.list();
    final (free, _) = await _c.storageInfo();
    if (!mounted) return;
    setState(() {
      _recent = MediaLibrary.apply(items, const MediaLibraryQuery()).take(8).toList();
      _captureBytes = MediaLibrary.totalBytes(items);
      _free = free;
      _loading = false;
    });
  }

  Future<void> _record() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      await CaptureFlows.startRecording(context);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        elevation: 0,
        title: Text('NOVA Capture', style: captureText(18, weight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Recording settings',
            icon: const Icon(Icons.tune_rounded, color: AppTheme.textPrimary),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const RecordingSettingsScreen())),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _c,
        builder: (context, _) => RefreshIndicator(
          onRefresh: () async {
            await _c.refresh();
            await _load();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              _statusCard(),
              const SizedBox(height: 12),
              _bubbleCard(),
              const CaptureSectionTitle('Capture'),
              _actions(),
              CaptureSectionTitle('Recent', trailing: TextButton(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const CaptureMediaLibrary())),
                child: const Text('See all'),
              )),
              _recentStrip(),
              const CaptureSectionTitle('Storage'),
              _storageCard(),
              const CaptureSectionTitle('Permissions'),
              _permissionsCard(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Status ──────────────────────────────────────────────────────────────

  Widget _statusCard() {
    final s = _c.snapshot;
    final st = s.state;
    final active = st.isCapturing;
    final border = st == RecordingState.recording
        ? CaptureColors.record.withOpacity(0.5)
        : (st == RecordingState.paused ? CaptureColors.paused.withOpacity(0.5) : null);
    String detail;
    if (active) {
      final audio = switch (s.audio) {
        'mic' => 'microphone',
        'device' => 'app sound',
        'mic_device' => 'microphone + app sound',
        _ => 'no audio',
      };
      detail = '${s.width}×${s.height} · ${s.fps} fps · $audio';
    } else {
      detail = switch (st) {
        RecordingState.awaitingConsent => 'Answer Android’s screen-capture question to continue.',
        RecordingState.starting => s.countdown > 0 ? 'Starting in ${s.countdown}…' : 'Starting…',
        RecordingState.stopping || RecordingState.finalizing => 'Saving your video — this can take a moment.',
        RecordingState.saved => 'Your last recording was saved to Movies › NOVA X.',
        RecordingState.failed || RecordingState.cancelled => s.userMessage ?? st.label,
        _ => 'Record your screen or take a screenshot. Everything stays on this phone.',
      };
    }
    return CaptureCard(
      borderColor: border,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        RecordingStatusIndicator(state: st, elapsed: _c.elapsed),
        const SizedBox(height: 8),
        Text(detail, style: captureText(13.5, color: AppTheme.textSecondary)),
        for (final w in s.warnings)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline_rounded, size: 16, color: CaptureColors.paused),
              const SizedBox(width: 8),
              Expanded(child: Text(w, style: captureText(12.5, color: AppTheme.textSecondary))),
            ]),
          ),
        if (s.hasUnsaved && !st.isActive) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentCyan, minimumSize: const Size.fromHeight(44)),
                onPressed: () async => captureReport(await _c.retrySave(), success: 'Recording saved.'),
                icon: const Icon(Icons.refresh_rounded, color: Colors.black),
                label: Text('Try saving again', style: captureText(13.5, weight: FontWeight.w800, color: Colors.black)),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: () => _c.discardUnsaved(), child: const Text('Discard')),
          ]),
        ],
        if (active) ...[
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46),
                    side: const BorderSide(color: AppTheme.glassBorder)),
                onPressed: () async => captureReport(st == RecordingState.paused ? await _c.resume() : await _c.pause()),
                icon: Icon(st == RecordingState.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    color: AppTheme.textPrimary),
                label: Text(st == RecordingState.paused ? 'Resume' : 'Pause', style: captureText(14)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: CaptureColors.record, minimumSize: const Size.fromHeight(46)),
                onPressed: () => CaptureFlows.stopAndSave(),
                icon: const Icon(Icons.stop_rounded, color: Colors.white),
                label: Text('Stop & save', style: captureText(14, weight: FontWeight.w800)),
              ),
            ),
          ]),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => CaptureFlows.cancelRecording(context),
              child: Text('Discard recording', style: captureText(13, color: AppTheme.textSecondary)),
            ),
          ),
        ],
      ]),
    );
  }

  // ── Floating button ─────────────────────────────────────────────────────

  Widget _bubbleCard() {
    final on = _c.bubbleEnabled;
    return CaptureCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      borderColor: on ? AppTheme.accentCyan.withOpacity(0.4) : null,
      child: SwitchListTile(
        value: on,
        activeColor: AppTheme.accentCyan,
        secondary: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.bgElevated,
            border: Border.all(color: AppTheme.accentCyan, width: 2),
          ),
          child: const Icon(Icons.screenshot_monitor_rounded, color: Colors.white, size: 20),
        ),
        title: Text('Floating capture button', style: captureText(14.5, weight: FontWeight.w700)),
        subtitle: Text(
          on
              ? 'On screen and over other apps. Tap it for Record, Screenshot and more; drag it onto ✕ to close.'
              : 'A small round button on your screen, in NOVA X and over other apps.',
          style: captureText(12, color: AppTheme.textSecondary),
        ),
        onChanged: (v) => CaptureFlows.toggleBubble(context, v),
      ),
    );
  }

  // ── Quick actions ───────────────────────────────────────────────────────

  Widget _actions() {
    final page = WebpageCaptureService.current;
    final busy = _c.isBusy || _starting;
    final tiles = <Widget>[
      _ActionTile(
        icon: Icons.fiber_manual_record_rounded,
        color: CaptureColors.record,
        title: 'Record screen',
        subtitle: _c.settings.audio.label,
        enabled: !busy,
        onTap: _record,
      ),
      _ActionTile(
        icon: Icons.screenshot_monitor_rounded,
        color: AppTheme.accentCyan,
        title: 'Capture screen',
        subtitle: 'Everything on screen',
        enabled: !busy,
        onTap: () => CaptureFlows.captureScreen(context),
      ),
      if (page != null) ...[
        _ActionTile(
          icon: Icons.crop_free_rounded,
          color: AppTheme.accentPurple,
          title: 'This page',
          subtitle: 'Visible part',
          enabled: !_c.snapshot.screenshotBusy,
          onTap: () => CaptureFlows.captureWebpage(context, page, fullPage: false),
        ),
        _ActionTile(
          icon: Icons.view_day_rounded,
          color: AppTheme.accentPurple,
          title: 'Full page',
          subtitle: 'Top to bottom',
          enabled: !_c.snapshot.screenshotBusy,
          onTap: () => CaptureFlows.captureWebpage(context, page, fullPage: true),
        ),
      ],
    ];
    return LayoutBuilder(builder: (context, box) {
      final w = (box.maxWidth - 12) / 2;
      return Wrap(spacing: 12, runSpacing: 12, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
    });
  }

  Widget _recentStrip() {
    if (_loading) {
      return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_recent.isEmpty) {
      return CaptureCard(
        child: Row(children: [
          const Icon(Icons.photo_library_outlined, color: AppTheme.textHint),
          const SizedBox(width: 12),
          Expanded(
            child: Text('No captures yet. Screenshots and recordings you make appear here.',
                style: captureText(13.5, color: AppTheme.textSecondary)),
          ),
        ]),
      );
    }
    final lib = MediaLibraryService.instance;
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _recent.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final a = _recent[i];
          return Semantics(
            button: true,
            label: '${a.isVideo ? 'Recording' : 'Screenshot'} ${a.name}, ${formatCaptureDate(a.created)}',
            child: GestureDetector(
              onTap: () => CaptureFlows.openPreview(context, a),
              child: SizedBox(
                width: a.isVideo ? 96 : 84,
                child: CaptureThumb(asset: a, favorite: lib.isFavorite(a.uri)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _storageCard() {
    final perMin = _c.settings.estimatedBytesPerMinute();
    final minutes = _free > 0 && perMin > 0 ? ((_free - 150 * 1024 * 1024) ~/ perMin) : 0;
    final low = _free >= 0 && _free < 300 * 1024 * 1024;
    return CaptureCard(
      borderColor: low ? AppTheme.warning.withOpacity(0.5) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.sd_storage_rounded, color: low ? AppTheme.warning : AppTheme.accentCyan),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_free < 0 ? 'Free space unknown' : '${formatBytes(_free)} free on this phone',
                style: captureText(14.5, weight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 8),
        Text('NOVA X captures use ${formatBytes(_captureBytes)}.', style: captureText(13, color: AppTheme.textSecondary)),
        if (_free > 0)
          Text('About ${minutes < 0 ? 0 : minutes} minutes of recording at your current settings (estimate).',
              style: captureText(13, color: AppTheme.textSecondary)),
        if (low)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Your phone is almost full. Recording needs at least 300 MB free.',
                style: captureText(13, weight: FontWeight.w700, color: AppTheme.warning)),
          ),
      ]),
    );
  }

  Widget _permissionsCard() {
    final caps = _c.capabilities;
    if (!caps.available) {
      return CaptureCard(child: Text("NOVA Capture isn't available on this device.", style: captureText(13.5)));
    }
    return CaptureCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(children: [
        _PermissionRow(
          icon: Icons.screen_share_rounded,
          title: 'Screen capture',
          status: 'Asked by Android every time',
          ok: true,
        ),
        _PermissionRow(
          icon: Icons.mic_rounded,
          title: 'Microphone',
          status: caps.micGranted ? 'Allowed — used only while recording with sound' : 'Not allowed — recordings have no sound',
          ok: caps.micGranted,
          action: caps.micGranted
              ? null
              : () async {
                  if (!await CapturePermissionSheet.microphone(context)) return;
                  final g = await _c.requestPermissions(['mic']);
                  if (g['mic'] != true && g['micCanAsk'] != true) await _c.openAppSettings();
                },
        ),
        _PermissionRow(
          icon: Icons.notifications_rounded,
          title: 'Notifications',
          status: caps.notificationsGranted ? 'Recording controls show in notifications' : 'Off — controls only inside NOVA X',
          ok: caps.notificationsGranted,
          action: caps.notificationsGranted
              ? null
              : () async {
                  if (!await CapturePermissionSheet.notifications(context)) return;
                  final g = await _c.requestPermissions(['notifications']);
                  if (g['notifications'] != true) await _c.openAppSettings();
                },
        ),
        _PermissionRow(
          icon: Icons.picture_in_picture_alt_rounded,
          title: 'Display over other apps',
          status: caps.overlayPermission
              ? 'Allowed — used only by the floating button'
              : 'Not allowed (only needed for the floating button)',
          ok: caps.overlayPermission || !_c.bubbleEnabled,
          action: caps.overlayPermission ? null : () => CaptureFlows.toggleBubble(context, true),
        ),
        if (caps.sdk > 0 && caps.sdk < 29)
          _PermissionRow(
            icon: Icons.folder_rounded,
            title: 'Storage',
            status: caps.needsStoragePermission ? 'Needed to save on this Android version' : 'Allowed',
            ok: !caps.needsStoragePermission,
            action: caps.needsStoragePermission ? () => _c.requestPermissions(['storage']) : null,
          ),
      ]),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$title. $subtitle',
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Material(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: enabled ? onTap : null,
            child: Container(
              constraints: const BoxConstraints(minHeight: 104),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.glassBorder),
              ),
              child: ExcludeSemantics(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(height: 12),
                  Text(title, style: captureText(14.5, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: captureText(12, color: AppTheme.textSecondary)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.icon, required this.title, required this.status, required this.ok, this.action});
  final IconData icon;
  final String title;
  final String status;
  final bool ok;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: ok ? AppTheme.success : AppTheme.warning),
      title: Text(title, style: captureText(14, weight: FontWeight.w600)),
      subtitle: Text(status, style: captureText(12.5, color: AppTheme.textSecondary)),
      trailing: action == null
          ? Icon(ok ? Icons.check_circle_rounded : Icons.info_outline_rounded,
              color: ok ? AppTheme.success : AppTheme.warning, semanticLabel: ok ? 'OK' : 'Needs attention')
          : TextButton(onPressed: action, child: const Text('Fix')),
    );
  }
}
