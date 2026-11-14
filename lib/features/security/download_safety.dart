// lib/features/security/download_safety.dart
//
// Download safety (3.13.0, Android version of the PC's Download Verdict).
//
// NOVA X never installs apps: it has no install permission, and it doesn't
// open downloaded app files itself. When a page starts downloading an
// Android app (.apk / .apks / .xapk), NOVA X first shows where it comes from
// and any warning signs (insecure connection, raw IP address, reached through
// an ad, look-alike or risky address), and the download is only kept in
// Downloads if the user chooses so. Installing is always up to Android's own
// installer and its warnings.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cyber/ui/cyber_palette.dart';
import '../guide/guide_screen.dart';
import '../pro/pro_ui.dart';
import '../pro/scam_check.dart';

class DownloadSafety {
  DownloadSafety._();

  static const String _kOn = 'nova_download_safety_on';

  static Future<bool> enabled() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_kOn) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setEnabled(bool v) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_kOn, v);
    } catch (_) {}
  }

  /// Is [name] / [mime] an Android app package?
  static bool isApp(String name, String? mime) {
    final n = name.toLowerCase().split('?').first;
    return n.endsWith('.apk') || n.endsWith('.apks') || n.endsWith('.xapk') || n.endsWith('.apkm') ||
        (mime ?? '').toLowerCase() == 'application/vnd.android.package-archive';
  }

  /// Warning signs about where a download comes from (same rules as PC).
  static List<String> sourceReasons(String url, String page) {
    final out = <String>[];
    final u = Uri.tryParse(url);
    if (u == null) return out;
    if (u.scheme == 'http') out.add('Downloaded over an insecure connection (http)');
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(u.host)) out.add('Downloaded from a raw IP address');
    final lower = '$url $page'.toLowerCase();
    if (RegExp(r'(googleadservices|doubleclick\.net|/aclk\?|gclid=|msclkid=|bing\.com/aclick)').hasMatch(lower)) {
      out.add('Reached through an ad link — fake apps are often advertised');
    }
    for (final r in ScamAnalyzer.analyzeUrl(url)) {
      if (r.points >= 25) out.add('Download site: ${r.title}');
    }
    if (page.startsWith('http') && Uri.tryParse(page)?.host != u.host) {
      for (final r in ScamAnalyzer.analyzeUrl(page)) {
        if (r.points >= 25) out.add('Page: ${r.title}');
      }
    }
    return out.toSet().toList();
  }

  /// Asks before keeping an app download. Returns true to keep it.
  static Future<bool> confirmApp(BuildContext context, {required String name, required String url, required String page}) async {
    final reasons = sourceReasons(url, page);
    final from = Uri.tryParse(url)?.host ?? url;
    final pageHost = Uri.tryParse(page)?.host ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => NovaThemed(
        child: Builder(builder: (ctx) {
          final p = NovaThemeScope.of(ctx);
          final risky = reasons.isNotEmpty;
          return AlertDialog(
            backgroundColor: p.surface,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            title: Row(children: [
              Icon(risky ? Icons.gpp_bad_rounded : Icons.android_rounded, color: risky ? p.danger : p.warning),
              const SizedBox(width: 10),
              Expanded(child: Text(risky ? 'Careful with this app file' : 'This is an app file', style: p.title(size: 17))),
            ]),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: p.ui(size: 14, weight: FontWeight.w700)),
                const SizedBox(height: 8),
                ProKv('From', from),
                if (pageHost.isNotEmpty && pageHost != from) ProKv('Page', pageHost),
                const SizedBox(height: 8),
                if (risky) ...[
                  for (final r in reasons) ProFindingRow(level: ProLevel.high, title: r),
                  const SizedBox(height: 4),
                ],
                Text(
                  'Apps from outside Google Play can read your messages, steal passwords or show ads everywhere. '
                  'Only install apps from developers you trust. NOVA X never installs apps — Android will ask you, with its own warnings.',
                  style: p.ui(size: 12.5, color: p.textMuted, height: 1.45),
                ),
                const SizedBox(height: 6),
                const ReadMoreLink('download_verdict', compact: true),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(risky ? 'Keep anyway' : 'Keep in Downloads')),
              FilledButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel download')),
            ],
          );
        }),
      ),
    );
    return ok == true;
  }
}
