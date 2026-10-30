// lib/features/browser/devtools/tabs/application_tab.dart
//
// Application: Local Storage, Session Storage, Cookies (all cookies of the
// site, including HttpOnly, from the browser's cookie store), IndexedDB,
// Cache Storage, Service Workers, Web App Manifest, storage usage and
// "Clear site data".

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../devtools_bridge.dart';
import '../dt_ui.dart';

class ApplicationTab extends StatefulWidget {
  const ApplicationTab({super.key, required this.bridge, required this.pageUrl});
  final DevtoolsBridge bridge;
  final String pageUrl;

  @override
  State<ApplicationTab> createState() => _ApplicationTabState();
}

class _ApplicationTabState extends State<ApplicationTab> {
  String _section = 'local';

  static const _sections = [
    ('local', Icons.storage_rounded, 'Local storage'),
    ('session', Icons.timelapse_rounded, 'Session storage'),
    ('cookies', Icons.cookie_outlined, 'Cookies'),
    ('idb', Icons.dataset_outlined, 'IndexedDB'),
    ('cache', Icons.inventory_2_outlined, 'Cache storage'),
    ('sw', Icons.settings_suggest_outlined, 'Service workers'),
    ('manifest', Icons.install_mobile_rounded, 'Manifest'),
    ('usage', Icons.pie_chart_outline_rounded, 'Storage & clear'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        height: 38,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), children: [
          for (final (k, _, l) in _sections) DtChip(l, selected: _section == k, onTap: () => setState(() => _section = k)),
        ]),
      ),
      const Divider(height: 1, color: XC.border),
      Expanded(
        child: switch (_section) {
          'local' => _StorageView(key: const ValueKey('local'), bridge: widget.bridge, kind: 'local'),
          'session' => _StorageView(key: const ValueKey('session'), bridge: widget.bridge, kind: 'session'),
          'cookies' => _CookiesView(bridge: widget.bridge, url: widget.pageUrl),
          'idb' => _IdbView(bridge: widget.bridge),
          'cache' => _CacheView(bridge: widget.bridge),
          'sw' => _WorkersView(bridge: widget.bridge),
          'manifest' => _ManifestView(bridge: widget.bridge),
          _ => _UsageView(bridge: widget.bridge, url: widget.pageUrl),
        },
      ),
    ]);
  }
}

Future<(String, String)?> _editPair(BuildContext context, {String title = 'Edit', String k = '', String v = '', bool keyEditable = true}) {
  final kc = TextEditingController(text: k), vc = TextEditingController(text: v);
  return showModalBottomSheet<(String, String)>(
    context: context,
    isScrollControlled: true,
    backgroundColor: XC.side,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: XC.ui(15, weight: FontWeight.w700)),
            const SizedBox(height: 10),
            TextField(
              controller: kc,
              enabled: keyEditable,
              style: XC.mono(13),
              decoration: InputDecoration(labelText: 'Key', filled: true, fillColor: XC.bg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.4),
              child: TextField(
                controller: vc,
                maxLines: null,
                minLines: 3,
                style: XC.mono(12.5),
                decoration: InputDecoration(labelText: 'Value', filled: true, fillColor: XC.bg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              ),
            ),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: () {
                  final p = prettyJson(vc.text);
                  vc.text = p;
                },
                child: const Text('Format JSON'),
              ),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  if (kc.text.trim().isNotEmpty) Navigator.pop(ctx, (kc.text.trim(), vc.text));
                },
                child: const Text('Save'),
              ),
            ]),
          ]),
        ),
      ),
    ),
  );
}

class _StorageView extends StatefulWidget {
  const _StorageView({super.key, required this.bridge, required this.kind});
  final DevtoolsBridge bridge;
  final String kind;

  @override
  State<_StorageView> createState() => _StorageViewState();
}

class _StorageViewState extends State<_StorageView> {
  List<List<dynamic>>? _items;
  String? _error;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.bridge.call('storage', widget.kind);
    if (!mounted) return;
    setState(() {
      _error = r.ok ? null : r.error;
      _items = r.items.whereType<List>().toList();
    });
  }

  Future<void> _set(String op, {String? key, String? value, String? oldKey}) async {
    final r = await widget.bridge.call('storageSet', {'kind': widget.kind, 'op': op, 'key': key, 'value': value, 'oldKey': oldKey});
    if (!mounted) return;
    if (!r.ok) xToast(context, r.error ?? 'Failed', error: true);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = (_items ?? const []).where((e) => _filter.isEmpty || '${e[0]} ${e[1]}'.toLowerCase().contains(_filter.toLowerCase())).toList();
    final total = (_items ?? const []).fold<int>(0, (s, e) => s + '${e[0]}'.length + '${e[1]}'.length);
    return Column(children: [
      DtToolbar(children: [
        Expanded(child: DtFilter(onChanged: (v) => setState(() => _filter = v))),
        XIconBtn(Icons.add_rounded, tooltip: 'Add item', onTap: () async {
          final r = await _editPair(context, title: 'New item');
          if (r != null) _set('set', key: r.$1, value: r.$2);
        }),
        XIconBtn(Icons.delete_sweep_outlined, tooltip: 'Clear all', onTap: () async {
          if (await xConfirm(context, 'Clear ${widget.kind} storage?', 'All keys of this site are removed.')) _set('clear');
        }),
        XIconBtn(Icons.refresh_rounded, tooltip: 'Refresh', onTap: _load),
      ]),
      Expanded(
        child: _items == null
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _error != null
                ? DtEmpty(Icons.error_outline_rounded, _error!)
                : items.isEmpty
                    ? DtEmpty(Icons.storage_rounded, 'No ${widget.kind} storage', body: 'This site hasn’t stored anything here.')
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final e = items[i];
                          return Dismissible(
                            key: ValueKey('${e[0]}'),
                            direction: DismissDirection.endToStart,
                            background: Container(color: XC.error.withOpacity(0.3), alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 16), child: const Icon(Icons.delete_outline_rounded)),
                            onDismissed: (_) => _set('remove', key: '${e[0]}'),
                            child: ListTile(
                              dense: true,
                              title: Text('${e[0]}', style: XC.mono(12.5, color: const Color(0xFF9CDCFE))),
                              subtitle: Text('${e[1]}', style: XC.mono(11.5), maxLines: 3, overflow: TextOverflow.ellipsis),
                              onTap: () async {
                                final r = await _editPair(context, k: '${e[0]}', v: '${e[1]}');
                                if (r != null) _set('set', key: r.$1, value: r.$2, oldKey: '${e[0]}');
                              },
                              onLongPress: () => dtCopy(context, '${e[1]}', 'Copied value'),
                            ),
                          );
                        },
                      ),
      ),
      Container(
        color: XC.bar,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(children: [
          Text('${_items?.length ?? 0} keys · ~${fmtBytes(total * 2)}', style: XC.ui(11, color: XC.dim)),
          const Spacer(),
          Text('Swipe ← to delete · long-press to copy', style: XC.ui(10.5, color: XC.faint)),
        ]),
      ),
    ]);
  }
}

class _CookiesView extends StatefulWidget {
  const _CookiesView({required this.bridge, required this.url});
  final DevtoolsBridge bridge;
  final String url;

  @override
  State<_CookiesView> createState() => _CookiesViewState();
}

class _CookiesViewState extends State<_CookiesView> {
  List<Cookie>? _cookies;
  Set<String> _readable = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await CookieManager.instance().getCookies(url: WebUri(widget.url));
    final page = await widget.bridge.call('cookies');
    if (!mounted) return;
    setState(() {
      _cookies = list;
      _readable = page.items.whereType<List>().map((e) => '${e[0]}').toSet();
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = _cookies;
    return Column(children: [
      DtToolbar(children: [
        const SizedBox(width: 12),
        Expanded(child: Text(Uri.tryParse(widget.url)?.host ?? '', style: XC.mono(12, color: XC.dim), overflow: TextOverflow.ellipsis)),
        XIconBtn(Icons.add_rounded, tooltip: 'Add cookie', onTap: () async {
          final r = await _editPair(context, title: 'New cookie');
          if (r == null) return;
          await CookieManager.instance().setCookie(url: WebUri(widget.url), name: r.$1, value: r.$2, path: '/', isSecure: widget.url.startsWith('https'));
          _load();
        }),
        XIconBtn(Icons.delete_sweep_outlined, tooltip: 'Delete all cookies of this site', onTap: () async {
          if (!await xConfirm(context, 'Delete all cookies?', 'You may be signed out of this site.')) return;
          await CookieManager.instance().deleteCookies(url: WebUri(widget.url));
          await widget.bridge.call('clearSite'); // also page-readable ones on other paths
          _load();
        }),
        XIconBtn(Icons.refresh_rounded, tooltip: 'Refresh', onTap: _load),
      ]),
      Expanded(
        child: list == null
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : list.isEmpty
                ? const DtEmpty(Icons.cookie_outlined, 'No cookies for this page')
                : ListView(children: [
                    for (final c in list)
                      ListTile(
                        dense: true,
                        title: Row(children: [
                          Expanded(child: Text(c.name, style: XC.mono(12.5, color: const Color(0xFF9CDCFE)))),
                          if (!_readable.contains(c.name))
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(border: Border.all(color: XC.warning), borderRadius: BorderRadius.circular(4)),
                              child: Text('HttpOnly', style: XC.ui(9.5, color: XC.warning, weight: FontWeight.w700)),
                            ),
                        ]),
                        subtitle: Text('${c.value}', style: XC.mono(11.5), maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () async {
                          final r = await _editPair(context, title: 'Edit cookie', k: c.name, v: '${c.value}', keyEditable: false);
                          if (r == null) return;
                          await CookieManager.instance().setCookie(url: WebUri(widget.url), name: c.name, value: r.$2, path: c.path ?? '/', domain: c.domain);
                          _load();
                        },
                        onLongPress: () => dtCopy(context, '${c.name}=${c.value}', 'Copied cookie'),
                        trailing: XIconBtn(Icons.close_rounded, tooltip: 'Delete', size: 16, onTap: () async {
                          await CookieManager.instance().deleteCookie(url: WebUri(widget.url), name: c.name, path: c.path ?? '/', domain: c.domain);
                          await widget.bridge.call('cookieDelete', c.name);
                          _load();
                        }),
                      ),
                  ]),
      ),
      Container(
        color: XC.bar,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Text('${list?.length ?? 0} cookies · HttpOnly = hidden from page scripts', style: XC.ui(11, color: XC.dim)),
      ),
    ]);
  }
}

class _IdbView extends StatefulWidget {
  const _IdbView({required this.bridge});
  final DevtoolsBridge bridge;

  @override
  State<_IdbView> createState() => _IdbViewState();
}

class _IdbViewState extends State<_IdbView> {
  DtResult? _r;

  @override
  void initState() {
    super.initState();
    widget.bridge.call('idb').then((r) {
      if (mounted) setState(() => _r = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    if (r == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (!r.ok) return DtEmpty(Icons.dataset_outlined, r.error!);
    if (r.items.isEmpty) return const DtEmpty(Icons.dataset_outlined, 'No IndexedDB databases');
    return ListView(children: [
      for (final db in r.items.whereType<Map>()) ...[
        DtSection('${db['name']} · v${db['version']}'),
        if (db['error'] != null) DtKV('error', '${db['error']}', valueColor: XC.error),
        for (final s in (db['stores'] as List? ?? const []).whereType<Map>())
          ListTile(
            dense: true,
            leading: const Icon(Icons.table_rows_outlined, size: 18, color: XC.dim),
            title: Text('${s['name']}', style: XC.mono(12.5)),
            trailing: Text('${s['count']} records', style: XC.ui(11, color: XC.faint)),
            onTap: () async {
              final rec = await widget.bridge.call('idbRecords', {'db': db['name'], 'store': s['name']});
              if (!context.mounted) return;
              Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
                    backgroundColor: XC.side,
                    appBar: AppBar(backgroundColor: XC.bar, title: Text('${db['name']} › ${s['name']}', style: XC.mono(14))),
                    body: ListView(children: [
                      for (final e in rec.items.whereType<List>())
                        ExpansionTile(
                          title: Text('${e[0]}', style: XC.mono(12.5, color: const Color(0xFF9CDCFE))),
                          children: [_valueView('${e[1]}')],
                        ),
                      if (rec.items.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('Empty', style: TextStyle(color: XC.faint))),
                    ]),
                  )));
            },
          ),
      ],
    ]);
  }
}

Widget _valueView(String v) {
  try {
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: JsonTree(jsonDecode(v)));
  } catch (_) {
    return DtCode(v);
  }
}

class _CacheView extends StatefulWidget {
  const _CacheView({required this.bridge});
  final DevtoolsBridge bridge;

  @override
  State<_CacheView> createState() => _CacheViewState();
}

class _CacheViewState extends State<_CacheView> {
  DtResult? _r;

  @override
  void initState() {
    super.initState();
    widget.bridge.call('caches').then((r) {
      if (mounted) setState(() => _r = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    if (r == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (!r.ok) return DtEmpty(Icons.inventory_2_outlined, r.error!);
    if (r.items.isEmpty) return const DtEmpty(Icons.inventory_2_outlined, 'No Cache Storage');
    return ListView(children: [
      for (final c in r.items.whereType<Map>())
        ExpansionTile(
          title: Text('${c['name']}', style: XC.mono(13)),
          subtitle: Text('${c['count']} entries', style: XC.ui(11, color: XC.faint)),
          children: [
            for (final u in (c['urls'] as List? ?? const []))
              ListTile(dense: true, title: Text('$u', style: XC.mono(11.5), maxLines: 2, overflow: TextOverflow.ellipsis), onLongPress: () => dtCopy(context, '$u', 'Copied URL')),
          ],
        ),
    ]);
  }
}

class _WorkersView extends StatefulWidget {
  const _WorkersView({required this.bridge});
  final DevtoolsBridge bridge;

  @override
  State<_WorkersView> createState() => _WorkersViewState();
}

class _WorkersViewState extends State<_WorkersView> {
  DtResult? _r;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.bridge.call('workers');
    if (mounted) setState(() => _r = r);
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    if (r == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (!r.ok) return DtEmpty(Icons.settings_suggest_outlined, r.error!);
    if (r.items.isEmpty) return const DtEmpty(Icons.settings_suggest_outlined, 'No service workers', body: 'This site doesn’t register a service worker.');
    return ListView(children: [
      for (final w in r.items.whereType<Map>())
        Card(
          color: XC.bg,
          margin: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            DtKV('scope', '${w['scope']}'),
            DtKV('script', '${w['script']}'),
            DtKV('state', '${w['state']}', valueColor: w['state'] == 'activated' ? XC.ok : XC.warning),
            DtKV('controls page', '${w['controlling']}'),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () async {
                await widget.bridge.call('workerAction', {'scope': w['scope'], 'op': 'update'});
                _load();
              }, child: const Text('Update')),
              TextButton(onPressed: () async {
                await widget.bridge.call('workerAction', {'scope': w['scope'], 'op': 'unregister'});
                _load();
              }, child: const Text('Unregister', style: TextStyle(color: XC.error))),
            ]),
          ]),
        ),
    ]);
  }
}

class _ManifestView extends StatefulWidget {
  const _ManifestView({required this.bridge});
  final DevtoolsBridge bridge;

  @override
  State<_ManifestView> createState() => _ManifestViewState();
}

class _ManifestViewState extends State<_ManifestView> {
  DtResult? _r;

  @override
  void initState() {
    super.initState();
    widget.bridge.call('manifest').then((r) {
      if (mounted) setState(() => _r = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    if (r == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    final text = r.map['text'] as String?;
    if (text == null) return DtEmpty(Icons.install_mobile_rounded, r.error ?? 'No manifest');
    Object? json;
    try {
      json = jsonDecode(text);
    } catch (_) {}
    final m = json is Map ? json : const {};
    final icons = (m['icons'] as List? ?? const []).whereType<Map>().toList();
    final base = Uri.tryParse('${r.map['url']}');
    final checks = <(String, bool)>[
      ('name or short_name', m['name'] != null || m['short_name'] != null),
      ('start_url', m['start_url'] != null),
      ('display: standalone / fullscreen / minimal-ui', ['standalone', 'fullscreen', 'minimal-ui'].contains(m['display'])),
      ('icon 192×192 or larger', icons.any((i) => '${i['sizes']}'.split(' ').any((s) => (int.tryParse(s.split('x').first) ?? 0) >= 192))),
      ('icon 512×512 (splash)', icons.any((i) => '${i['sizes']}'.contains('512'))),
      ('theme_color', m['theme_color'] != null),
    ];
    return ListView(children: [
      DtKV('URL', '${r.map['url']}'),
      const DtSection('Installability'),
      for (final (label, ok) in checks)
        ListTile(dense: true, leading: Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded, color: ok ? XC.ok : XC.error, size: 18), title: Text(label, style: XC.ui(13))),
      if (icons.isNotEmpty) ...[
        const DtSection('Icons'),
        SizedBox(
          height: 90,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(10), children: [
            for (final i in icons)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Image.network(base?.resolve('${i['src']}').toString() ?? '${i['src']}', errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: XC.faint)),
                  ),
                  Text('${i['sizes'] ?? ''}', style: XC.ui(10, color: XC.faint)),
                ]),
              ),
          ]),
        ),
      ],
      const DtSection('manifest.json'),
      json != null ? JsonTree(json) : DtCode(text),
    ]);
  }
}

class _UsageView extends StatefulWidget {
  const _UsageView({required this.bridge, required this.url});
  final DevtoolsBridge bridge;
  final String url;

  @override
  State<_UsageView> createState() => _UsageViewState();
}

class _UsageViewState extends State<_UsageView> {
  DtResult? _r;
  List<String>? _cleared;

  @override
  void initState() {
    super.initState();
    widget.bridge.call('estimate').then((r) {
      if (mounted) setState(() => _r = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = _r?.map ?? const {};
    final usage = (m['usage'] as num?) ?? 0, quota = (m['quota'] as num?) ?? 0;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Text('Storage used by ${Uri.tryParse(widget.url)?.host ?? 'this site'}', style: XC.ui(14, weight: FontWeight.w700)),
      const SizedBox(height: 10),
      if (_r == null)
        const LinearProgressIndicator()
      else if (!_r!.ok)
        Text(_r!.error!, style: XC.ui(12.5, color: XC.faint))
      else ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: quota > 0 ? (usage / quota).clamp(0.0, 1.0) : 0, minHeight: 10, color: XC.accent, backgroundColor: XC.bg),
        ),
        const SizedBox(height: 6),
        Text('${fmtBytes(usage)} of ${fmtBytes(quota)} quota', style: XC.ui(12, color: XC.dim)),
        if (m['details'] is Map) for (final e in (m['details'] as Map).entries) DtKV('${e.key}', fmtBytes((e.value as num?) ?? 0)),
      ],
      const SizedBox(height: 24),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: XC.error),
        onPressed: () async {
          if (!await xConfirm(context, 'Clear site data?',
              'Removes local & session storage, cookies, Cache Storage, IndexedDB and service workers of this site. You may be signed out.',
              action: 'Clear')) {
            return;
          }
          final r = await widget.bridge.call('clearSite');
          await CookieManager.instance().deleteCookies(url: WebUri(widget.url));
          if (!mounted) return;
          setState(() => _cleared = (r.map['done'] as List? ?? const []).map((e) => '$e').toList()..add('all cookies'));
        },
        icon: const Icon(Icons.cleaning_services_outlined),
        label: const Text('Clear site data'),
      ),
      if (_cleared != null) ...[
        const SizedBox(height: 10),
        Text('Cleared: ${_cleared!.join(', ')}. Reload the page to see the effect.', style: XC.ui(12.5, color: XC.ok)),
      ],
    ]);
  }
}
