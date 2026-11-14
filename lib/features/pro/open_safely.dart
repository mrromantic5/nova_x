// lib/features/pro/open_safely.dart
//
// Open Safely — check a link before it opens, then open it in Safe View:
//  • Follows short links / redirects step by step without loading the page
//    (shows every hop and where it really ends).
//  • Runs the Scam Explainer address checks and NOVA Shield on the result.
//  • Safe View tab: private (nothing saved), scripts off, downloads blocked,
//    pop-ups blocked, no camera/microphone/location, passwords never filled.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cyber/ui/cyber_palette.dart';
import 'pro_tab.dart';
import 'pro_ui.dart';
import 'scam_check.dart';

class LinkHop {
  const LinkHop(this.url, this.status);
  final String url;
  final int? status;
}

class LinkExpander {
  LinkExpander._();

  /// Pure: the next address from a Location header (relative allowed).
  static String? nextUrl(String current, String? location) {
    if (location == null || location.trim().isEmpty) return null;
    try {
      return Uri.parse(current).resolve(location.trim()).toString();
    } catch (_) {
      return null;
    }
  }

  /// Follows redirects one by one (max 10) without reading page bodies.
  static Future<List<LinkHop>> expand(String url) async {
    final hops = <LinkHop>[];
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..userAgent = 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Mobile NOVA-X';
    var current = url;
    try {
      for (var i = 0; i < 10; i++) {
        final uri = Uri.tryParse(current);
        if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) break;
        HttpClientResponse res;
        try {
          var req = await client.openUrl('HEAD', uri).timeout(const Duration(seconds: 8));
          req.followRedirects = false;
          res = await req.close().timeout(const Duration(seconds: 8));
          if (res.statusCode == 405 || res.statusCode == 403 || res.statusCode == 501) {
            await res.drain<void>();
            req = await client.getUrl(uri).timeout(const Duration(seconds: 8));
            req.followRedirects = false;
            res = await req.close().timeout(const Duration(seconds: 8));
          }
        } catch (_) {
          hops.add(LinkHop(current, null));
          break;
        }
        hops.add(LinkHop(current, res.statusCode));
        final loc = res.headers.value(HttpHeaders.locationHeader);
        unawaited(res.listen((_) {}).cancel());
        if (res.statusCode < 300 || res.statusCode >= 400) break;
        final next = nextUrl(current, loc);
        if (next == null || next == current) break;
        current = next;
      }
    } finally {
      client.close(force: true);
    }
    if (hops.isEmpty) hops.add(LinkHop(url, null));
    return hops;
  }
}

/// "Open a link safely…" — [initial] pre-fills the address.
Future<void> showOpenSafely(BuildContext context, {String? initial}) async {
  var text = initial ?? '';
  if (text.isEmpty) {
    try {
      final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
      if (RegExp(r'^https?://\S+$').hasMatch(clip)) text = clip;
    } catch (_) {}
  }
  if (!context.mounted) return;
  await showProDialog<void>(context, (ctx) => _OpenSafelyDialog(initial: text));
}

class _OpenSafelyDialog extends StatefulWidget {
  const _OpenSafelyDialog({required this.initial});
  final String initial;

  @override
  State<_OpenSafelyDialog> createState() => _OpenSafelyDialogState();
}

class _OpenSafelyDialogState extends State<_OpenSafelyDialog> {
  late final TextEditingController _url = TextEditingController(text: widget.initial);
  bool _busy = false;
  List<LinkHop>? _hops;
  ScamVerdict? _v;

  String get _final => _hops?.lastOrNull?.url ?? _normalized;
  String get _normalized {
    final t = _url.text.trim();
    if (t.isEmpty) return '';
    return t.startsWith('http://') || t.startsWith('https://') ? t : 'https://$t';
  }

  @override
  void initState() {
    super.initState();
    if (widget.initial.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final u = _normalized;
    if (u.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _hops = null;
      _v = null;
    });
    final hops = await LinkExpander.expand(u);
    final v = await ScamAnalyzer.check(hops.last.url);
    if (mounted) {
      setState(() {
        _hops = hops;
        _v = v;
        _busy = false;
      });
    }
  }

  void _open({bool safe = false}) {
    final u = _final;
    if (u.isEmpty) return;
    Navigator.pop(context);
    ProTabs.instance.openUrl(u, safe: safe, incognito: safe);
  }

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    final v = _v;
    final hops = _hops;
    return ProDialog(
      icon: Icons.health_and_safety_rounded,
      title: 'Open Safely',
      guide: 'open_safely',
      subtitle: 'See where a link really goes before it opens',
      width: 700,
      height: 600,
      actions: [
        if (hops != null) ...[
          TextButton(onPressed: () => _open(), child: const Text('Open normally')),
          FilledButton.icon(
            onPressed: () => _open(safe: true),
            icon: const Icon(Icons.shield_rounded, size: 18),
            label: const Text('Open in Safe View'),
          ),
        ],
      ],
      child: ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [
          Expanded(child: ProField(controller: _url, hint: 'Paste a link (https://…)', onSubmitted: (_) => _check())),
          const SizedBox(width: 8),
          FilledButton(onPressed: _busy ? null : _check, child: Text(_busy ? 'Checking…' : 'Check')),
        ]),
        const SizedBox(height: 16),
        if (_busy) const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator())),
        if (hops != null) ...[
          ProCard(
            title: hops.length > 1 ? 'Redirects (${hops.length - 1})' : 'Where it goes',
            icon: Icons.alt_route_rounded,
            trailing: IconButton(
                tooltip: 'Copy final address', icon: const Icon(Icons.copy_rounded, size: 16), onPressed: () => proCopy(_final)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < hops.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(i == hops.length - 1 ? Icons.flag_rounded : Icons.subdirectory_arrow_right_rounded,
                        size: 16, color: i == hops.length - 1 ? p.accent : p.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SelectableText(hops[i].url,
                          style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: i == hops.length - 1 ? p.text : p.textMuted)),
                    ),
                    if (hops[i].status != null) ProChip('${hops[i].status}', color: p.textMuted),
                  ]),
                ),
              if (hops.last.status == null)
                Text('The site didn’t answer — it may be down, or block automated checks.', style: p.ui(size: 12, color: p.warning)),
            ]),
          ),
          if (v != null)
            ProCard(
              title: v.label,
              icon: v.score >= 25 ? Icons.warning_amber_rounded : Icons.verified_user_outlined,
              trailing: ProChip('${v.score}/100', color: v.level.color(p)),
              child: v.reasons.isEmpty && v.shieldThreat == null
                  ? Text('No warning signs in the address.', style: p.ui(size: 12.5, color: p.textMuted))
                  : Column(children: [
                      if (v.shieldThreat != null)
                        ProFindingRow(level: ProLevel.critical, title: 'NOVA Shield: ${v.shieldThreat}', detail: 'This site is on a threat list.'),
                      for (final r in v.reasons) ProFindingRow(level: r.level, title: r.title, detail: r.detail),
                    ]),
            ),
          ProCard(
            title: 'Safe View',
            icon: Icons.shield_outlined,
            child: Text(
              'Opens in an incognito tab with scripts turned off and downloads blocked; nothing from it is kept. '
              'Saved passwords aren’t offered. Many pages look plain without scripts — that’s expected. Checking a link contacts its '
              'server (like any visit) but doesn’t run the page.',
              style: p.ui(size: 12.5, color: p.textMuted, height: 1.4),
            ),
          ),
        ] else if (!_busy)
          Text('Paste a link from an email, a message or a QR code and press Check.', style: p.ui(size: 12.5, color: p.textMuted)),
      ]),
    );
  }
}
