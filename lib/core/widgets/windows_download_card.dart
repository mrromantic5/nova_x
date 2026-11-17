// lib/core/widgets/windows_download_card.dart
//
// 3.13.1: "Download NOVA X Browser for Windows" — shown at the bottom of the
// profile and on pages where the PC version adds the most (Settings,
// Security Center, Feature Guide, NOVA Cyber's code scan). The download page
// opens inside NOVA X's own browser, never in another browser.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../features/browser/screens/browser_view.dart';

class WindowsDownload {
  WindowsDownload._();

  static const String url = 'https://nova-x.t-lyfe.com.ng';

  /// Opens the Windows download page in a NOVA X browser tab.
  static void open(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BrowserView(initialQuery: url)));
  }
}

/// Four-pane window mark (drawn, so no image asset is needed).
class WindowsMark extends StatelessWidget {
  const WindowsMark({super.key, this.size = 22, this.color = const Color(0xFF38BDF8)});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final gap = size * 0.08;
    final pane = (size - gap) / 2;
    Widget sq() => Container(width: pane, height: pane, color: color);
    return SizedBox(
      width: size,
      height: size,
      child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [sq(), sq()]),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [sq(), sq()]),
      ]),
    );
  }
}

/// A card that recommends the Windows version.
/// [reason] is one short line about why the PC version helps on this page.
class WindowsDownloadCard extends StatelessWidget {
  const WindowsDownloadCard({
    super.key,
    this.reason = 'Same account, coins and Premium — on a big screen.',
    this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 16),
    this.compact = false,
  });

  final String reason;
  final EdgeInsetsGeometry margin;

  /// A single-line row (for lists such as Settings).
  final bool compact;

  static const Color _blue = Color(0xFF38BDF8);

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return ListTile(
        onTap: () => WindowsDownload.open(context),
        leading: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: _blue.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: const WindowsMark(size: 18),
        ),
        title: Text('Download NOVA X Browser for Windows',
            style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(reason, style: GoogleFonts.inter(color: Colors.white54, fontSize: 11.5)),
        trailing: const Icon(Icons.open_in_new_rounded, color: Colors.white38, size: 18),
      );
    }
    return Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => WindowsDownload.open(context),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [Color(0xFF0B2545), Color(0xFF13315C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: _blue.withValues(alpha: 0.35)),
            ),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: _blue.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                child: const WindowsMark(size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Download NOVA X Browser',
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 1),
                  Text('Windows version',
                      style: GoogleFonts.inter(color: _blue, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(reason, style: GoogleFonts.inter(color: Colors.white70, fontSize: 12, height: 1.35)),
                ]),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(20)),
                child: Text('Get it',
                    style: GoogleFonts.inter(color: const Color(0xFF04263B), fontSize: 12.5, fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 3.14.0: a small "Windows" chip shown next to features that only exist in
/// NOVA X for Windows.
class WindowsBadge extends StatelessWidget {
  const WindowsBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const WindowsMark(size: 9),
          const SizedBox(width: 4),
          Text('Windows', style: GoogleFonts.inter(color: const Color(0xFF7DD3FC), fontSize: 10, fontWeight: FontWeight.w700)),
        ]),
      );
}

/// 3.14.0: what Android shows instead of a PC-only feature — a sheet with
/// the feature's name, one line on what it does on Windows, and the
/// Windows download card. Never a disabled or broken screen.
class WindowsOnly {
  WindowsOnly._();

  static Future<void> show(BuildContext context, {required String title, required String reason}) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0D1626),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: Text(title, style: GoogleFonts.inter(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              const WindowsBadge(),
            ]),
            const SizedBox(height: 6),
            Text('Available in NOVA X for Windows.', style: GoogleFonts.inter(color: Colors.white60, fontSize: 13)),
            WindowsDownloadCard(reason: reason, margin: const EdgeInsets.fromLTRB(0, 14, 0, 4)),
          ]),
        ),
      ),
    );
  }
}
