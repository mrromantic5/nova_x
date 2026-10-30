// lib/features/browser/devtools/tabs/perf_tab.dart
//
// Performance: Core Web Vitals (LCP, CLS, FCP, TTFB, blocking time) rated
// like Lighthouse, navigation timeline, resources by type, slowest
// requests, DOM size and JS memory. Reload & measure.
//
// Audit: Lighthouse-style checks run on the live page — Performance,
// Accessibility, Best Practices, SEO, PWA — plus security headers and the
// TLS certificate. Tap an element in a finding to highlight it.

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../devtools_bridge.dart';
import '../dt_ui.dart';

class PerformanceTab extends StatefulWidget {
  const PerformanceTab({super.key, required this.bridge, required this.onReload});
  final DevtoolsBridge bridge;
  final Future<void> Function() onReload;

  @override
  State<PerformanceTab> createState() => _PerformanceTabState();
}

class _PerformanceTabState extends State<PerformanceTab> {
  Map<String, dynamic>? _p;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    setState(() => _busy = true);
    final r = await widget.bridge.call('perf');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _p = r.ok ? r.map : null;
      _error = r.error;
    });
  }

  Future<void> _reloadAndMeasure() async {
    setState(() {
      _busy = true;
      _p = null;
    });
    await widget.onReload();
    await Future.delayed(const Duration(seconds: 4));
    if (mounted) await _measure();
  }

  /// (rating color, label) by Web Vitals thresholds.
  (Color, String) _rate(num? v, num good, num poor) {
    if (v == null) return (XC.faint, '—');
    if (v <= good) return (const Color(0xFF0CCE6B), 'Good');
    if (v <= poor) return (const Color(0xFFFFA400), 'Needs work');
    return (const Color(0xFFFF4E42), 'Poor');
  }

  Widget _metric(String name, String value, (Color, String) rating, String hint) => Container(
        width: 160,
        margin: const EdgeInsets.all(5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: XC.bg, borderRadius: BorderRadius.circular(10), border: Border(left: BorderSide(color: rating.$1, width: 3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: XC.ui(11.5, color: XC.dim, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(value, style: XC.ui(20, color: rating.$1, weight: FontWeight.w800)),
          Text(rating.$2, style: XC.ui(11, color: rating.$1)),
          const SizedBox(height: 4),
          Text(hint, style: XC.ui(10.5, color: XC.faint)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Column(children: [
      DtToolbar(children: [
        const SizedBox(width: 12),
        Expanded(child: Text('Measured on this phone, for the page as loaded', style: XC.ui(11.5, color: XC.faint))),
        TextButton.icon(onPressed: _busy ? null : _reloadAndMeasure, icon: const Icon(Icons.replay_rounded, size: 16), label: const Text('Reload & measure')),
        XIconBtn(Icons.refresh_rounded, tooltip: 'Measure again', onTap: _busy ? null : _measure),
      ]),
      if (_busy) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: p == null
            ? (_error != null ? DtEmpty(Icons.speed_rounded, _error!) : const SizedBox.shrink())
            : ListView(padding: const EdgeInsets.all(6), children: [
                Wrap(children: [
                  _metric('LCP', fmtMs(p['lcp'] as num?), _rate(p['lcp'] as num?, 2500, 4000), 'Largest Contentful Paint'),
                  _metric('CLS', '${p['cls'] ?? '—'}', _rate(p['cls'] as num?, 0.1, 0.25), 'Cumulative Layout Shift'),
                  _metric('FCP', fmtMs(p['fcp'] as num?), _rate(p['fcp'] as num?, 1800, 3000), 'First Contentful Paint'),
                  _metric('TTFB', fmtMs(p['ttfb'] as num?), _rate(p['ttfb'] as num?, 800, 1800), 'Server response'),
                  _metric('TBT', fmtMs(p['blocking'] as num?), _rate(p['blocking'] as num?, 200, 600), '${p['longTasks']} long tasks'),
                  _metric('Load', fmtMs(p['load'] as num?), _rate(p['load'] as num?, 3000, 6000), 'load event'),
                ]),
                if (p['lcpElement'] is Map)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.image_search_rounded, color: XC.accent, size: 18),
                    title: Text('LCP element', style: XC.ui(12.5, weight: FontWeight.w700)),
                    subtitle: Text('${(p['lcpElement'] as Map)['label']}', style: XC.mono(11.5)),
                    onTap: () => widget.bridge.call('highlight', (p['lcpElement'] as Map)['path']),
                  ),
                const DtSection('Navigation timeline'),
                _timeline(p),
                const DtSection('Page'),
                DtKV('requests', '${p['requests']}'),
                DtKV('document', '${fmtBytes((p['transfer'] as num?) ?? 0)} transferred · ${fmtBytes((p['docSize'] as num?) ?? 0)} decoded'),
                DtKV('protocol', '${p['protocol'] ?? ''}'),
                DtKV('DOM elements', '${p['dom']} (depth ${p['depth']})', valueColor: ((p['dom'] as num?) ?? 0) > 1500 ? XC.warning : null),
                if (p['memory'] is Map)
                  DtKV('JS heap', '${fmtBytes(((p['memory'] as Map)['used'] as num?) ?? 0)} used of ${fmtBytes(((p['memory'] as Map)['total'] as num?) ?? 0)}'),
                const DtSection('Resources by type'),
                ..._byType(p),
                const DtSection('Slowest requests'),
                for (final s in (p['slow'] as List? ?? const []).whereType<Map>())
                  ListTile(
                    dense: true,
                    title: Text(Uri.tryParse('${s['url']}')?.pathSegments.where((x) => x.isNotEmpty).lastOrNull ?? '${s['url']}', style: XC.mono(12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${s['type']} · ${fmtBytes((s['bytes'] as num?) ?? 0)} · starts at ${fmtMs(s['start'] as num?)}', style: XC.ui(10.5, color: XC.faint)),
                    trailing: Text(fmtMs(s['ms'] as num?), style: XC.mono(12, color: ((s['ms'] as num?) ?? 0) > 1000 ? XC.warning : XC.text)),
                    onLongPress: () => dtCopy(context, '${s['url']}', 'Copied URL'),
                  ),
              ]),
      ),
    ]);
  }

  Widget _timeline(Map<String, dynamic> p) {
    final phases = <(String, num?, Color)>[
      ('DNS', p['dns'] as num?, const Color(0xFF26A69A)),
      ('Connect', p['tcp'] as num?, const Color(0xFFFFA726)),
      ('TLS', p['tls'] as num?, const Color(0xFFAB47BC)),
      ('Waiting (TTFB)', p['request'] as num?, const Color(0xFF66BB6A)),
      ('Download', p['download'] as num?, const Color(0xFF42A5F5)),
    ];
    final marks = <(String, num?)>[
      ('First paint', p['fp'] as num?),
      ('First contentful paint', p['fcp'] as num?),
      ('DOM interactive', p['domInteractive'] as num?),
      ('DOMContentLoaded', p['dcl'] as num?),
      ('Largest contentful paint', p['lcp'] as num?),
      ('Load', p['load'] as num?),
    ];
    final end = marks.fold<num>(1, (m, e) => (e.$2 ?? 0) > m ? e.$2! : m);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (n, v, c) in phases)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(width: 110, child: Text(n, style: XC.ui(11.5, color: XC.dim))),
              Expanded(
                child: LayoutBuilder(builder: (_, cc) {
                  final w = v == null ? 0.0 : (cc.maxWidth * (v / end)).clamp(2.0, cc.maxWidth);
                  return Align(alignment: Alignment.centerLeft, child: Container(height: 8, width: w, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))));
                }),
              ),
              SizedBox(width: 60, child: Text(fmtMs(v), style: XC.mono(11), textAlign: TextAlign.right)),
            ]),
          ),
        const SizedBox(height: 10),
        for (final (n, v) in marks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              const Icon(Icons.flag_outlined, size: 13, color: XC.faint),
              const SizedBox(width: 6),
              Expanded(child: Text(n, style: XC.ui(12))),
              Text(fmtMs(v), style: XC.mono(11.5)),
            ]),
          ),
      ]),
    );
  }

  List<Widget> _byType(Map<String, dynamic> p) {
    final m = (p['byType'] as Map? ?? const {});
    final total = m.values.fold<num>(0, (s, v) => s + (((v as Map)['bytes'] as num?) ?? 0));
    return [
      for (final e in m.entries)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            SizedBox(width: 110, child: Text('${e.key}', style: XC.mono(12))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: total > 0 ? ((((e.value as Map)['bytes'] as num?) ?? 0) / total).toDouble() : 0,
                  minHeight: 6,
                  color: XC.accent,
                  backgroundColor: XC.bg,
                ),
              ),
            ),
            SizedBox(
              width: 120,
              child: Text('${(e.value as Map)['count']} · ${fmtBytes(((e.value as Map)['bytes'] as num?) ?? 0)}',
                  style: XC.ui(11, color: XC.dim), textAlign: TextAlign.right),
            ),
          ]),
        ),
    ];
  }
}

class AuditTab extends StatefulWidget {
  const AuditTab({super.key, required this.bridge, required this.wvc});
  final DevtoolsBridge bridge;
  final InAppWebViewController? wvc;

  @override
  State<AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends State<AuditTab> {
  Map<String, dynamic>? _r;
  Map<String, dynamic>? _sec;
  SslCertificate? _cert;
  bool _busy = false;
  String? _error;
  String _cat = 'perf';

  static const _cats = [('perf', 'Performance'), ('a11y', 'Accessibility'), ('best', 'Best practices'), ('seo', 'SEO'), ('pwa', 'PWA'), ('security', 'Security')];

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await widget.bridge.call('audit');
    final s = await widget.bridge.call('securityHeaders');
    SslCertificate? cert;
    try {
      cert = await widget.wvc?.getCertificate();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _busy = false;
      _r = r.ok ? r.map : null;
      _error = r.error;
      _sec = s.map;
      _cert = cert;
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    if (r == null) {
      return DtEmpty(Icons.fact_check_outlined, _busy ? 'Auditing the page…' : 'Audit this page',
          body: _error ?? 'Checks performance, accessibility, best practices, SEO, PWA and security headers on the live page — like Lighthouse, on your phone.',
          action: _busy
              ? const CircularProgressIndicator(strokeWidth: 2)
              : FilledButton.icon(onPressed: _run, icon: const Icon(Icons.play_arrow_rounded), label: const Text('Run audit')));
    }
    final scores = Map<String, dynamic>.from(r['scores'] as Map? ?? const {});
    final audits = (r['audits'] as List? ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    final secScore = _securityScore();
    return Column(children: [
      SizedBox(
        height: 112,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(8, 10, 8, 4), children: [
          for (final (k, l) in _cats)
            InkWell(
              onTap: () => setState(() => _cat = k),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 92,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(color: _cat == k ? XC.hover : null, borderRadius: BorderRadius.circular(10)),
                child: ScoreRing(k == 'security' ? secScore : ((scores[k] as num?) ?? 0).toInt(), size: 56, label: l),
              ),
            ),
        ]),
      ),
      Row(children: [
        const SizedBox(width: 12),
        Expanded(child: Text('Live page · ${TimeOfDay.now().format(context)}', style: XC.ui(11, color: XC.faint))),
        TextButton.icon(onPressed: _busy ? null : _run, icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('Run again')),
      ]),
      const Divider(height: 1, color: XC.border),
      Expanded(child: _cat == 'security' ? _security() : _list(audits.where((a) => a['cat'] == _cat).toList())),
    ]);
  }

  int _securityScore() {
    final h = Map<String, dynamic>.from((_sec?['headers'] as Map?) ?? const {});
    final checks = [
      widget.wvc != null && (_cert != null),
      h.containsKey('strict-transport-security'),
      h.containsKey('content-security-policy'),
      h.containsKey('x-content-type-options'),
      h.containsKey('x-frame-options') || '${h['content-security-policy'] ?? ''}'.contains('frame-ancestors'),
      h.containsKey('referrer-policy'),
      h.containsKey('permissions-policy'),
    ];
    return (100 * checks.where((c) => c).length / checks.length).round();
  }

  Widget _security() {
    final h = Map<String, dynamic>.from((_sec?['headers'] as Map?) ?? const {});
    final all = (_sec?['all'] as List? ?? const []).whereType<List>().toList();
    Widget check(String name, String header, String why) {
      final v = h[header];
      return ListTile(
        dense: true,
        leading: Icon(v != null ? Icons.check_circle_rounded : Icons.cancel_rounded, color: v != null ? XC.ok : XC.error, size: 18),
        title: Text(name, style: XC.ui(13, weight: FontWeight.w600)),
        subtitle: Text(v != null ? '$v' : why, style: v != null ? XC.mono(11, color: XC.dim) : XC.ui(11.5, color: XC.faint), maxLines: 3, overflow: TextOverflow.ellipsis),
      );
    }

    final c = _cert;
    return ListView(children: [
      const DtSection('Connection'),
      if (c == null)
        ListTile(
          dense: true,
          leading: const Icon(Icons.lock_open_rounded, color: XC.error, size: 18),
          title: Text('Not secure (no TLS certificate)', style: XC.ui(13, weight: FontWeight.w600)),
        )
      else ...[
        ListTile(dense: true, leading: const Icon(Icons.lock_rounded, color: XC.ok, size: 18), title: Text('Secure connection (TLS)', style: XC.ui(13, weight: FontWeight.w600))),
        DtKV('issued to', c.issuedTo?.CName ?? ''),
        DtKV('issued by', '${c.issuedBy?.CName ?? ''} ${c.issuedBy?.OName ?? ''}'.trim()),
        DtKV('valid from', c.validNotBeforeDate?.toLocal().toString().split('.').first ?? ''),
        DtKV('valid until', c.validNotAfterDate?.toLocal().toString().split('.').first ?? '',
            valueColor: c.validNotAfterDate != null && c.validNotAfterDate!.difference(DateTime.now()).inDays < 14 ? XC.warning : null),
      ],
      const DtSection('Security headers'),
      check('Strict-Transport-Security', 'strict-transport-security', 'Forces HTTPS on future visits.'),
      check('Content-Security-Policy', 'content-security-policy', 'Limits where scripts can come from — the main defence against XSS.'),
      check('X-Content-Type-Options', 'x-content-type-options', 'Should be “nosniff”.'),
      check('X-Frame-Options', 'x-frame-options', 'Prevents clickjacking (or use CSP frame-ancestors).'),
      check('Referrer-Policy', 'referrer-policy', 'Controls what URL is sent to other sites.'),
      check('Permissions-Policy', 'permissions-policy', 'Limits camera, microphone, location… for the page and its iframes.'),
      if (h['server'] != null || h['x-powered-by'] != null) ...[
        const DtSection('Information disclosure'),
        if (h['server'] != null) DtKV('server', '${h['server']}', valueColor: XC.warning),
        if (h['x-powered-by'] != null) DtKV('x-powered-by', '${h['x-powered-by']}', valueColor: XC.warning),
      ],
      if (all.isNotEmpty) ...[
        DtSection('All response headers (${all.length})'),
        for (final e in all) if (e.length >= 2) DtKV('${e[0]}', '${e[1]}'),
      ],
      if (_sec?['error'] != null)
        Padding(padding: const EdgeInsets.all(12), child: Text('Headers unavailable: ${_sec!['error']}', style: XC.ui(12, color: XC.faint))),
    ]);
  }

  Widget _list(List<Map<String, dynamic>> audits) {
    final failed = audits.where((a) => a['pass'] != true).toList();
    final passed = audits.where((a) => a['pass'] == true).toList();
    return ListView(children: [
      if (failed.isNotEmpty) DtSection('To improve (${failed.length})'),
      for (final a in failed) _audit(a),
      if (passed.isNotEmpty) DtSection('Passed (${passed.length})'),
      for (final a in passed) _audit(a),
    ]);
  }

  Widget _audit(Map<String, dynamic> a) {
    final pass = a['pass'] == true;
    final items = (a['items'] as List? ?? const []).whereType<Map>().toList();
    final title = Row(children: [
      Icon(pass ? Icons.check_circle_rounded : Icons.error_rounded, size: 16, color: pass ? const Color(0xFF0CCE6B) : const Color(0xFFFF4E42)),
      const SizedBox(width: 8),
      Expanded(child: Text('${a['title']}', style: XC.ui(13, weight: FontWeight.w600))),
    ]);
    final detail = '${a['detail'] ?? ''}';
    if (items.isEmpty) {
      return ListTile(dense: true, title: title, subtitle: detail.isEmpty ? null : Padding(padding: const EdgeInsets.only(left: 24), child: Text(detail, style: XC.ui(11.5, color: XC.faint))));
    }
    return ExpansionTile(
      dense: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      title: title,
      subtitle: Padding(padding: const EdgeInsets.only(left: 24), child: Text(detail, style: XC.ui(11.5, color: XC.faint))),
      children: [
        for (final i in items)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 40, right: 12),
            title: Text('${i['label']}', style: XC.mono(11.5), maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: '${i['note'] ?? ''}'.isEmpty ? null : Text('${i['note']}', style: XC.ui(10.5, color: XC.faint), maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: i['path'] is List ? const Icon(Icons.ads_click_rounded, size: 16, color: XC.accent) : null,
            onTap: i['path'] is List
                ? () {
                    widget.bridge.call('edit', {'path': i['path'], 'op': 'scroll'});
                    widget.bridge.call('highlight', i['path']);
                    xToast(context, 'Highlighted on the page');
                  }
                : () => dtCopy(context, '${i['label']}'),
          ),
      ],
    );
  }
}
