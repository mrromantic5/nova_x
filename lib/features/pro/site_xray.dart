// lib/features/pro/site_xray.dart
//
// Site Data X-ray — what the current site keeps on this phone and who else it
// talks to: cookies (first / third party, flags, expiry), local & session
// storage, IndexedDB, caches, service workers, permissions, and every
// other company the page loaded something from (ads, analytics, social,
// session recording). Delete a cookie, block a tracker for good (Rewrite
// Rules), or wipe everything the site stored.
// Android (3.13.0): cookies come from Android's CookieManager, which gives
// names and values of the cookies sent to this page (not their flags —
// Security Lens shows the flags the server sets).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../cyber/ui/cyber_palette.dart';
import 'page_rules.dart';
import 'pro_tab.dart';
import 'pro_ui.dart';

enum TrackerKind { ads, analytics, social, replay, cdn, other }

extension TrackerKindX on TrackerKind {
  String get label => switch (this) {
        TrackerKind.ads => 'Advertising',
        TrackerKind.analytics => 'Analytics',
        TrackerKind.social => 'Social media',
        TrackerKind.replay => 'Session recording',
        TrackerKind.cdn => 'Content / fonts',
        TrackerKind.other => 'Other',
      };
  ProLevel get level => switch (this) {
        TrackerKind.ads || TrackerKind.replay => ProLevel.high,
        TrackerKind.analytics || TrackerKind.social => ProLevel.medium,
        TrackerKind.cdn => ProLevel.info,
        TrackerKind.other => ProLevel.low,
      };
}

class SiteXray {
  SiteXray._();

  static const Map<String, TrackerKind> known = {
    'doubleclick.net': TrackerKind.ads,
    'googlesyndication.com': TrackerKind.ads,
    'googleadservices.com': TrackerKind.ads,
    'adservice.google.com': TrackerKind.ads,
    'amazon-adsystem.com': TrackerKind.ads,
    'adnxs.com': TrackerKind.ads,
    'criteo.com': TrackerKind.ads,
    'criteo.net': TrackerKind.ads,
    'taboola.com': TrackerKind.ads,
    'outbrain.com': TrackerKind.ads,
    'rubiconproject.com': TrackerKind.ads,
    'pubmatic.com': TrackerKind.ads,
    'openx.net': TrackerKind.ads,
    'casalemedia.com': TrackerKind.ads,
    'adsrvr.org': TrackerKind.ads,
    'moatads.com': TrackerKind.ads,
    'media.net': TrackerKind.ads,
    'bat.bing.com': TrackerKind.ads,
    'ads.linkedin.com': TrackerKind.ads,
    'ads-twitter.com': TrackerKind.ads,
    'google-analytics.com': TrackerKind.analytics,
    'googletagmanager.com': TrackerKind.analytics,
    'analytics.google.com': TrackerKind.analytics,
    'scorecardresearch.com': TrackerKind.analytics,
    'quantserve.com': TrackerKind.analytics,
    'chartbeat.com': TrackerKind.analytics,
    'mixpanel.com': TrackerKind.analytics,
    'segment.io': TrackerKind.analytics,
    'segment.com': TrackerKind.analytics,
    'amplitude.com': TrackerKind.analytics,
    'heap.io': TrackerKind.analytics,
    'newrelic.com': TrackerKind.analytics,
    'nr-data.net': TrackerKind.analytics,
    'matomo.cloud': TrackerKind.analytics,
    'hs-analytics.net': TrackerKind.analytics,
    'clarity.ms': TrackerKind.replay,
    'hotjar.com': TrackerKind.replay,
    'hotjar.io': TrackerKind.replay,
    'fullstory.com': TrackerKind.replay,
    'mouseflow.com': TrackerKind.replay,
    'smartlook.com': TrackerKind.replay,
    'logrocket.io': TrackerKind.replay,
    'luckyorange.com': TrackerKind.replay,
    'facebook.net': TrackerKind.social,
    'facebook.com': TrackerKind.social,
    'connect.facebook.net': TrackerKind.social,
    'platform.twitter.com': TrackerKind.social,
    'tiktok.com': TrackerKind.social,
    'analytics.tiktok.com': TrackerKind.social,
    'snap.licdn.com': TrackerKind.social,
    'pinterest.com': TrackerKind.social,
    'ct.pinterest.com': TrackerKind.social,
    'snapchat.com': TrackerKind.social,
    'gstatic.com': TrackerKind.cdn,
    'googleapis.com': TrackerKind.cdn,
    'cloudflare.com': TrackerKind.cdn,
    'cdnjs.cloudflare.com': TrackerKind.cdn,
    'jsdelivr.net': TrackerKind.cdn,
    'unpkg.com': TrackerKind.cdn,
    'fontawesome.com': TrackerKind.cdn,
    'akamaihd.net': TrackerKind.cdn,
    'cloudfront.net': TrackerKind.cdn,
    'fastly.net': TrackerKind.cdn,
    'ytimg.com': TrackerKind.cdn,
  };

  /// What kind of company [host] is (longest known suffix wins).
  static TrackerKind kindOf(String host) {
    final h = host.toLowerCase();
    TrackerKind? best;
    var bestLen = 0;
    known.forEach((suffix, kind) {
      if ((h == suffix || h.endsWith('.$suffix')) && suffix.length > bestLen) {
        best = kind;
        bestLen = suffix.length;
      }
    });
    return best ?? TrackerKind.other;
  }

  static const String storageJs = r'''
(function(){
  var out={ls:0,lsBytes:0,ss:0,ssBytes:0,res:{}};
  try{ for(var i=0;i<localStorage.length;i++){var k=localStorage.key(i);out.ls++;out.lsBytes+=(k.length+(localStorage.getItem(k)||'').length)*2;} }catch(_){}
  try{ for(var j=0;j<sessionStorage.length;j++){var k2=sessionStorage.key(j);out.ss++;out.ssBytes+=(k2.length+(sessionStorage.getItem(k2)||'').length)*2;} }catch(_){}
  try{
    performance.getEntriesByType('resource').forEach(function(e){
      try{ var h=new URL(e.name).hostname; if(!h) return;
        var r=out.res[h]||(out.res[h]={n:0,bytes:0,types:{}}); r.n++; r.bytes+=(e.transferSize||0); r.types[e.initiatorType||'other']=1; }catch(_){}
    });
  }catch(_){}
  try{ out.cookieApi = (document.cookie||'').split(';').filter(function(x){return x.trim();}).length; }catch(_){ out.cookieApi = 0; }
  return JSON.stringify(out);
})();''';

  static const String asyncJs = r'''
var out={idb:[],caches:[],sw:0,perms:{}};
try{ if(indexedDB.databases){ out.idb=(await indexedDB.databases()).map(function(d){return d.name+' (v'+d.version+')';}); } }catch(_){}
try{ out.caches=await caches.keys(); }catch(_){}
try{ out.sw=(await navigator.serviceWorker.getRegistrations()).length; }catch(_){}
var names=['geolocation','notifications','camera','microphone','clipboard-read','persistent-storage'];
for (var i=0;i<names.length;i++){ try{ out.perms[names[i]]=(await navigator.permissions.query({name:names[i]})).state; }catch(_){} }
return JSON.stringify(out);''';
}

Future<void> showSiteXray(BuildContext context, ProTab t) => showProDialog<void>(context, (ctx) => _XrayDialog(tab: t));

class _Cookie {
  _Cookie(Cookie c, String host)
      : name = c.name,
        size = c.name.length + '${c.value ?? ''}'.length,
        domain = (c.domain == null || '${c.domain}'.isEmpty) ? host : '${c.domain}',
        path = (c.path == null || '${c.path}'.isEmpty) ? '/' : '${c.path}';
  final String name, domain, path;
  final int size;
}

class _XrayDialog extends StatefulWidget {
  const _XrayDialog({required this.tab});
  final ProTab tab;

  @override
  State<_XrayDialog> createState() => _XrayDialogState();
}

class _XrayDialogState extends State<_XrayDialog> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  bool _loading = true;
  List<_Cookie> _cookies = [];
  Map<String, dynamic> _store = {};
  Map<String, dynamic> _async = {};

  ProTab get t => widget.tab;
  String get host => t.host;
  String get base => proBaseDomain(host);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = t.web;
    if (c == null) {
      setState(() => _loading = false);
      return;
    }
    List<_Cookie> cookies = [];
    try {
      final list = await CookieManager.instance().getCookies(url: WebUri(t.url));
      cookies = [for (final k in list) _Cookie(k, host)];
    } catch (_) {}
    Map<String, dynamic> store = {};
    try {
      final r = await c.evaluateJavascript(source: SiteXray.storageJs);
      final d = r is String ? jsonDecode(r) : r;
      if (d is Map) store = Map<String, dynamic>.from(d);
    } catch (_) {}
    Map<String, dynamic> extra = {};
    try {
      final r = await c.callAsyncJavaScript(functionBody: SiteXray.asyncJs);
      final v = r?.value;
      final d = v is String ? jsonDecode(v) : v;
      if (d is Map) extra = Map<String, dynamic>.from(d);
    } catch (_) {}
    cookies.sort((a, b) => a.domain.compareTo(b.domain));
    if (mounted) {
      setState(() {
        _cookies = cookies;
        _store = store;
        _async = extra;
        _loading = false;
      });
    }
  }

  bool _thirdParty(String domain) => proBaseDomain(domain.replaceFirst(RegExp(r'^\.'), '')) != base;

  Future<void> _deleteCookie(_Cookie k) async {
    try {
      await CookieManager.instance().deleteCookie(url: WebUri(t.url), name: k.name, path: k.path);
      if (k.domain != host) {
        await CookieManager.instance().deleteCookie(url: WebUri(t.url), name: k.name, domain: k.domain, path: k.path);
      }
    } catch (_) {}
    setState(() => _cookies.remove(k));
    proToast('Cookie “${k.name}” deleted');
  }

  Future<void> _wipe() async {
    final c = t.web;
    final uri = Uri.tryParse(t.url);
    if (c == null || uri == null || uri.host.isEmpty) return;
    try {
      await WebStorageManager.instance().deleteOrigin(origin: uri.origin);
    } catch (_) {}
    try {
      await CookieManager.instance().deleteCookies(url: WebUri(t.url));
      await CookieManager.instance().deleteCookies(url: WebUri(t.url), domain: '.$base');
    } catch (_) {}
    await c.reload();
    if (mounted) Navigator.pop(context);
    proToast('Everything ${uri.host} stored on this phone was removed');
  }

  void _block(String h) {
    PageRules.instance.addBlock('*://$h/*', note: 'Blocked from Site Data X-ray');
    if (h.split('.').length == 2) PageRules.instance.addBlock('*://*.$h/*', note: 'Blocked from Site Data X-ray');
    setState(() {});
    proToast('$h is now blocked on every site (Rewrite Rules)');
  }

  static String _bytes(num b) {
    if (b < 1024) return '${b.round()} B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    final res = (_store['res'] is Map) ? Map<String, dynamic>.from(_store['res'] as Map) : <String, dynamic>{};
    final others = res.keys.where((h) => proBaseDomain(h) != base).toList()
      ..sort((a, b) => SiteXray.kindOf(a).index.compareTo(SiteXray.kindOf(b).index));
    final trackers = others.where((h) {
      final k = SiteXray.kindOf(h);
      return k == TrackerKind.ads || k == TrackerKind.analytics || k == TrackerKind.social || k == TrackerKind.replay;
    }).length;
    final third = _cookies.where((k) => _thirdParty(k.domain)).length;
    return ProDialog(
      icon: Icons.manage_search_rounded,
      title: 'Site Data X-ray',
      guide: 'site_xray',
      subtitle: host,
      width: 860,
      actions: [
        TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Refresh')),
        FilledButton.icon(
          onPressed: _wipe,
          style: FilledButton.styleFrom(backgroundColor: p.danger, foregroundColor: Colors.white),
          icon: const Icon(Icons.delete_sweep_rounded, size: 18),
          label: const Text('Remove all site data'),
        ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                child: Wrap(spacing: 10, runSpacing: 10, children: [
                  _stat(p, Icons.cookie_outlined, '${_cookies.length}', 'cookies', third > 0 ? '$third from other companies' : null),
                  _stat(p, Icons.storage_rounded, '${(_store['ls'] ?? 0)}', 'saved items',
                      _bytes((_store['lsBytes'] as num? ?? 0) + (_store['ssBytes'] as num? ?? 0))),
                  _stat(p, Icons.public_rounded, '${others.length}', 'other companies', trackers > 0 ? '$trackers trackers' : 'no known trackers'),
                  _stat(p, Icons.dns_outlined, '${(_async['idb'] as List?)?.length ?? 0}', 'databases',
                      '${_async['sw'] ?? 0} background workers'),
                ]),
              ),
              TabBar(
                controller: _tabs,
                labelColor: p.accent,
                unselectedLabelColor: p.textMuted,
                indicatorColor: p.accent,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: const [Tab(text: 'Who it talks to'), Tab(text: 'Cookies'), Tab(text: 'Storage & permissions')],
              ),
              Expanded(
                child: TabBarView(controller: _tabs, children: [
                  _companies(p, others, res),
                  _cookieList(p),
                  _storage(p),
                ]),
              ),
            ]),
    );
  }

  Widget _stat(NovaPalette p, IconData icon, String big, String label, String? sub) => Container(
        width: 160,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
        child: Row(children: [
          Icon(icon, color: p.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$big $label', style: p.ui(size: 13, weight: FontWeight.w700, color: p.text)),
              if (sub != null) Text(sub, style: p.ui(size: 11, color: p.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      );

  Widget _companies(NovaPalette p, List<String> others, Map<String, dynamic> res) {
    if (others.isEmpty) {
      return const ProEmpty(icon: Icons.verified_user_outlined, title: 'Only this site', text: 'The page didn’t load anything from other companies.');
    }
    final blocked = PageRules.instance.blockedPatterns().toSet();
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final h in others)
        Builder(builder: (_) {
          final k = SiteXray.kindOf(h);
          final r = Map<String, dynamic>.from(res[h] as Map);
          final isBlocked = blocked.contains('*://$h/*');
          return ProFindingRow(
            level: k.level,
            title: h,
            detail: '${k.label} · ${r['n']} request(s) · ${_bytes(r['bytes'] as num? ?? 0)}',
            trailing: isBlocked
                ? ProChip('Blocked', color: p.success)
                : TextButton(onPressed: t.web == null ? null : () => _block(h), child: const Text('Block')),
          );
        }),
      const SizedBox(height: 8),
      Text('Blocking adds a Rewrite Rule. If a site stops working, turn the rule off in Rewrite Rules.',
          style: p.ui(size: 11.5, color: p.textFaint)),
    ]);
  }

  Widget _cookieList(NovaPalette p) {
    if (_cookies.isEmpty) {
      return const ProEmpty(icon: Icons.cookie_outlined, title: 'No cookies', text: 'This site hasn’t stored any cookies for this page.');
    }
    if (_cookies.length > 1000) {
      return const ProEmpty(icon: Icons.cookie_outlined, title: 'Too many cookies', text: 'This page has more cookies than can be listed.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _cookies.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: p.border),
      itemBuilder: (_, i) {
        final k = _cookies[i];
        final third = _thirdParty(k.domain);
        return ListTile(
          dense: true,
          title: Row(children: [
            Flexible(child: Text(k.name, style: p.ui(size: 13, weight: FontWeight.w700, color: p.text), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            if (third) ProChip('Other company', color: p.warning),
          ]),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${k.domain}${k.path} · ${k.size} B', style: p.ui(size: 11.5, color: p.textMuted)),
          ),
          trailing: IconButton(
            tooltip: 'Delete this cookie',
            icon: Icon(Icons.delete_outline_rounded, color: p.danger),
            onPressed: () => _deleteCookie(k),
          ),
        );
      },
    );
  }

  Widget _storage(NovaPalette p) {
    final perms = (_async['perms'] is Map) ? Map<String, dynamic>.from(_async['perms'] as Map) : <String, dynamic>{};
    final idb = (_async['idb'] as List?) ?? const [];
    final caches = (_async['caches'] as List?) ?? const [];
    return ListView(padding: const EdgeInsets.all(16), children: [
      ProCard(
        title: 'Saved on this phone',
        icon: Icons.storage_rounded,
        child: Column(children: [
          ProKv('Local storage', '${_store['ls'] ?? 0} items · ${_bytes(_store['lsBytes'] as num? ?? 0)}'),
          ProKv('Session storage', '${_store['ss'] ?? 0} items · ${_bytes(_store['ssBytes'] as num? ?? 0)}'),
          ProKv('Databases (IndexedDB)', idb.isEmpty ? 'None' : idb.join(', ')),
          ProKv('Offline caches', caches.isEmpty ? 'None' : caches.join(', ')),
          ProKv('Background workers', '${_async['sw'] ?? 0}'),
        ]),
      ),
      ProCard(
        title: 'Permissions',
        icon: Icons.admin_panel_settings_outlined,
        child: perms.isEmpty
            ? Text('Not available for this page.', style: p.ui(size: 12.5, color: p.textMuted))
            : Column(children: [
                for (final e in perms.entries)
                  ProKv(
                    switch (e.key) {
                      'geolocation' => 'Location',
                      'notifications' => 'Notifications',
                      'camera' => 'Camera',
                      'microphone' => 'Microphone',
                      'clipboard-read' => 'Read clipboard',
                      'persistent-storage' => 'Keep data permanently',
                      _ => e.key,
                    },
                    switch ('${e.value}') { 'granted' => 'Allowed', 'denied' => 'Blocked', _ => 'Asks first' },
                    valueColor: '${e.value}' == 'granted' ? p.warning : null,
                  ),
              ]),
      ),
    ]);
  }
}
