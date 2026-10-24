// lib/features/ai/widgets/nova_limit_sheet.dart
//
// "Limit reached" message for NOVA AI photo uploads and image generation:
// what the limit is, a live countdown ring to the reset, and what still works.
// Used by the NOVA AI chat and the "Hey NOVA" panel.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../services/nova_quota.dart';

/// Before picking photos: how many may be added now (0 = the limit message
/// was shown instead).
Future<int> novaPhotoRoom(BuildContext context, int room) async {
  final q = await NovaQuota.status(NovaQuotaKind.upload);
  if (!context.mounted) return 0;
  if (q.exhausted) {
    await showNovaLimitSheet(context, q);
    return 0;
  }
  return math.min(room, q.remaining);
}

/// After picking / capturing: counts [n] photo uploads. False (with the
/// limit message shown) when they don't fit.
Future<bool> novaCountPhotos(BuildContext context, int n) async {
  final blocked = await NovaQuota.tryUse(NovaQuotaKind.upload, n);
  if (blocked == null) return true;
  if (context.mounted) await showNovaLimitSheet(context, blocked);
  return false;
}

Future<void> showNovaLimitSheet(BuildContext context, NovaQuotaStatus status) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => NovaLimitSheet(status: status),
  );
}

class NovaLimitSheet extends StatefulWidget {
  const NovaLimitSheet({super.key, required this.status});
  final NovaQuotaStatus status;

  @override
  State<NovaLimitSheet> createState() => _NovaLimitSheetState();
}

class _NovaLimitSheetState extends State<NovaLimitSheet> {
  Timer? _tick;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String clock(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.status;
    final isUpload = st.kind == NovaQuotaKind.upload;
    final left = st.leftAt(_now);
    final ready = left == Duration.zero;
    final fraction = ready ? 0.0 : left.inMilliseconds / NovaQuotaRules.window.inMilliseconds;
    final what = isUpload ? 'photo uploads' : 'image generations';
    final title = ready
        ? (isUpload ? 'You can add photos again' : 'You can create images again')
        : (isUpload ? 'Photo upload limit reached' : 'Image generation limit reached');
    final bottom = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 12, 24, bottom + 20),
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(color: AppTheme.divider, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: 132,
          height: 132,
          child: CustomPaint(
            painter: _CountdownRing(fraction, ready),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  ready
                      ? Icons.check_rounded
                      : (isUpload ? Icons.add_photo_alternate_rounded : Icons.auto_awesome_rounded),
                  color: ready ? AppTheme.success : const Color(0xFFFFC83D),
                  size: 24,
                ),
                const SizedBox(height: 4),
                Text(ready ? 'Ready' : clock(left),
                    style: GoogleFonts.spaceGrotesk(
                        color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                if (!ready)
                  Text('until reset',
                      style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 10.5)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(title,
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          ready
              ? 'Your ${st.limit} $what are available again.'
              : 'You\'ve used ${st.used} of ${st.limit} $what. NOVA allows ${st.limit} every '
                  '${NovaQuotaRules.window.inHours} hours to keep the service fast and fair for everyone.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13, height: 1.45),
        ),
        const SizedBox(height: 14),
        // Used / limit pips.
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < st.limit; i++)
            Container(
              width: 26,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: !ready && i < st.used ? const Color(0xFFFFC83D) : AppTheme.bgElevated,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ]),
        const SizedBox(height: 16),
        if (!ready)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.accentCyan.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              const Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.accentCyan, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text('You can keep chatting with NOVA by text and voice meanwhile.',
                    style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12)),
              ),
            ]),
          ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentCyan,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(ready ? 'Continue' : 'Got it',
                style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ]),
    );
  }
}

class _CountdownRing extends CustomPainter {
  _CountdownRing(this.fraction, this.ready);
  final double fraction; // share of the window still to wait
  final bool ready;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 6;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = Colors.white.withOpacity(0.06),
    );
    final rect = Rect.fromCircle(center: c, radius: r);
    final sweep = 2 * math.pi * (ready ? 1.0 : fraction.clamp(0.0, 1.0));
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 8
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: -math.pi / 2 + 2 * math.pi,
          colors: ready
              ? const [AppTheme.success, AppTheme.success]
              : const [Color(0xFFFFA000), Color(0xFFFFE08A), Color(0xFFFFA000)],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_CountdownRing old) => old.fraction != fraction || old.ready != ready;
}
