// lib/features/browser/devtools/tabs/network_tab.dart
//
// Network: fetch / XHR / WebSocket requests made by the page (live), plus
// everything the browser loaded (scripts, CSS, images, fonts) from the
// page's Resource Timing. Filters by type and status, search, a waterfall,
// and per request: headers, payload, response (pretty JSON / tree),
// timing, WebSocket frames, copy as cURL / fetch, replay.
//
// Headers and bodies are recorded only after Dev Tools was opened on this
// tab (reload to capture the page's first requests).

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../devtools_bridge.dart';
import '../dt_ui.dart';

class NetworkTab extends StatefulWidget {
  const NetworkTab({super.key, required this.bridge, required this.logs, required this.changes, required this.onClear, required this.onReload});
  final DevtoolsBridge bridge;
  final List<Map<String, dynamic>> logs;
  final Stream<void>? changes;
  final VoidCallback? onClear;
  final VoidCallback onReload;

  @override
  State<NetworkTab> createState() => _NetworkTabState();
}

class _NetworkTabState extends State<NetworkTab> {
  StreamSubscription<void>? _sub;
  String _type = 'all';
  String _filter = '';
  bool _errorsOnly = false;
  bool _showResources = true;
  List<Map<String, dynamic>> _resources = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _sub = widget.changes?.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 250), () {
        if (mounted) setState(() {});
      });
    });
    _loadResources();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadResources() async {
    final all = await widget.bridge.call('resources');
    if (!mounted) return;
    setState(() => _resources = all.items.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList());
  }

  String _kind(Map<String, dynamic> e) {
    final t = '${e['type'] ?? ''}';
    if (t == 'fetch' || t == 'xhr') return 'fetch';
    if (t == 'websocket') return 'ws';
    if (t == 'script') return 'js';
    if (t == 'stylesheet') return 'css';
    if (t == 'image') return 'img';
    if (t == 'font') return 'font';
    if (t == 'document') return 'doc';
    return 'other';
  }

  List<Map<String, dynamic>> get _rows {
    final live = widget.logs;
    final liveUrls = live.map((e) => e['url']).toSet();
    final res = _showResources
        ? _resources
            .where((r) => r['type'] != 'fetch' && !liveUrls.contains(r['url']))
            .map((r) => {...r, 'method': 'GET', 'status': 200, 'fromTiming': true})
        : const <Map<String, dynamic>>[];
    final f = _filter.toLowerCase();
    return [...res, ...live].where((e) {
      if (_type != 'all' && _kind(e) != _type) return false;
      final s = e['status'] is num ? (e['status'] as num).toInt() : 0;
      if (_errorsOnly && !(s >= 400 || (s == 0 && e['pending'] != true) || e['error'] != null)) return false;
      return f.isEmpty || '${e['url']}'.toLowerCase().contains(f) || '${e['method']}'.toLowerCase() == f;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final total = rows.fold<num>(0, (s, e) => s + ((e['size'] as num?) ?? 0));
    final maxMs = rows.fold<num>(1, (m, e) => math.max(m, (e['ms'] as num?) ?? 0));
    return Column(children: [
      DtToolbar(children: [
        XIconBtn(Icons.block_rounded, tooltip: 'Clear', size: 18, onTap: () {
          widget.onClear?.call();
          setState(() => _resources = []);
        }),
        Expanded(child: DtFilter(onChanged: (v) => setState(() => _filter = v), hint: 'Filter URLs')),
        XIconBtn(Icons.refresh_rounded, tooltip: 'Reload page and record', onTap: () {
          widget.onClear?.call();
          setState(() => _resources = []);
          widget.onReload();
          Future.delayed(const Duration(seconds: 3), _loadResources);
        }),
      ]),
      SizedBox(
        height: 34,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5), children: [
          for (final (k, l) in const [('all', 'All'), ('fetch', 'Fetch/XHR'), ('doc', 'Doc'), ('js', 'JS'), ('css', 'CSS'), ('img', 'Img'), ('font', 'Font'), ('ws', 'WS'), ('other', 'Other')])
            DtChip(l, selected: _type == k, onTap: () => setState(() => _type = k)),
          DtChip('Errors', selected: _errorsOnly, onTap: () => setState(() => _errorsOnly = !_errorsOnly), color: XC.error),
          DtChip('Page files', selected: _showResources, onTap: () => setState(() => _showResources = !_showResources)),
        ]),
      ),
      Expanded(
        child: rows.isEmpty
            ? DtEmpty(Icons.wifi_tethering_rounded, 'No requests yet',
                body: 'Requests appear as the page makes them. Reload to record everything from the start (headers and bodies are captured while Dev Tools is open on this tab).',
                action: OutlinedButton.icon(onPressed: widget.onReload, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Reload page')))
            : ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) => _row(rows[i], maxMs),
              ),
      ),
      Container(
        color: XC.bar,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(children: [
          Text('${rows.length} requests', style: XC.ui(11, color: XC.dim)),
          const SizedBox(width: 12),
          Text('${fmtBytes(total)} transferred', style: XC.ui(11, color: XC.dim)),
          const Spacer(),
          Text('${widget.logs.where((e) => e['pending'] == true).length} pending', style: XC.ui(11, color: XC.faint)),
        ]),
      ),
    ]);
  }

  Widget _row(Map<String, dynamic> e, num maxMs) {
    final url = '${e['url']}';
    final u = Uri.tryParse(url);
    final name = (u?.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? u?.host ?? url);
    final status = e['status'] is num ? (e['status'] as num).toInt() : 0;
    final pending = e['pending'] == true;
    final ms = (e['ms'] as num?) ?? 0;
    final failed = !pending && (status == 0 || status >= 400 || e['error'] != null);
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _RequestScreen(entry: e, bridge: widget.bridge))),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: failed ? XC.error.withOpacity(0.06) : null,
          border: const Border(bottom: BorderSide(color: Color(0xFF13203A))),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 44,
              padding: const EdgeInsets.symmetric(vertical: 1),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: XC.bg, borderRadius: BorderRadius.circular(4)),
              child: Text('${e['method'] ?? 'GET'}', style: XC.mono(10, color: XC.info, weight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(_dec(name.isEmpty ? url : name), style: XC.mono(12.5, color: failed ? const Color(0xFFFF8A80) : XC.text), maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 6),
            pending
                ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5))
                : Text(e['fromTiming'] == true ? '' : (status == 0 ? 'failed' : '$status'), style: XC.mono(11.5, color: statusColor(status), weight: FontWeight.w700)),
          ]),
          const SizedBox(height: 3),
          Row(children: [
            const SizedBox(width: 52),
            Expanded(child: Text(u?.host ?? '', style: XC.ui(10.5, color: XC.faint), maxLines: 1, overflow: TextOverflow.ellipsis)),
            Text('${_kind(e)} · ${fmtBytes((e['size'] as num?) ?? 0)} · ${fmtMs(ms)}', style: XC.ui(10.5, color: XC.faint)),
          ]),
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.only(left: 52),
            child: LayoutBuilder(builder: (_, c) {
              final w = (c.maxWidth * (ms / maxMs)).clamp(2.0, c.maxWidth);
              return Align(
                alignment: Alignment.centerLeft,
                child: Container(height: 3, width: w, decoration: BoxDecoration(color: failed ? XC.error : (ms > 1000 ? XC.warning : XC.accent), borderRadius: BorderRadius.circular(2))),
              );
            }),
          ),
        ]),
      ),
    );
  }
}

String _dec(String s) {
  try {
    return Uri.decodeComponent(s);
  } catch (_) {
    return s;
  }
}

String _decQ(String s) {
  try {
    return Uri.decodeQueryComponent(s);
  } catch (_) {
    return s;
  }
}

class _RequestScreen extends StatefulWidget {
  const _RequestScreen({required this.entry, required this.bridge});
  final Map<String, dynamic> entry;
  final DevtoolsBridge bridge;

  @override
  State<_RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends State<_RequestScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _tree = true;

  Map<String, dynamic> get e => widget.entry;
  bool get _ws => e['type'] == 'websocket';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _ws ? 3 : 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Map<String, String> _h(Object? m) =>
      m is Map ? {for (final x in m.entries) '${x.key}': '${x.value}'} : const {};

  String _curl() {
    final b = StringBuffer("curl '${'${e['url']}'.replaceAll("'", "'\\''")}'");
    final m = '${e['method'] ?? 'GET'}';
    if (m != 'GET') b.write(' -X $m');
    _h(e['reqHeaders']).forEach((k, v) => b.write(" \\\n  -H '$k: ${v.replaceAll("'", "'\\''")}'"));
    final body = '${e['reqBody'] ?? ''}';
    if (body.isNotEmpty) b.write(" \\\n  --data-raw '${body.replaceAll("'", "'\\''")}'");
    return b.toString();
  }

  String _fetch() {
    final opts = <String, Object?>{
      'method': e['method'] ?? 'GET',
      if (_h(e['reqHeaders']).isNotEmpty) 'headers': _h(e['reqHeaders']),
      if ('${e['reqBody'] ?? ''}'.isNotEmpty) 'body': e['reqBody'],
    };
    return 'await fetch(${jsonEncode('${e['url']}')}, ${const JsonEncoder.withIndent('  ').convert(opts)});';
  }

  Future<void> _replay() async {
    xToast(context, 'Sending again from the page…');
    final r = await widget.bridge.evaluate('${_fetch().replaceFirst('await fetch', '(await fetch').replaceFirst(RegExp(r';$'), '')}).status');
    if (!mounted) return;
    xToast(context, r['type'] == 'error' ? '${r['text']}'.split('\n').first : 'Replayed → status ${r['text']} (see the list)', error: r['type'] == 'error');
  }

  @override
  Widget build(BuildContext context) {
    final url = '${e['url']}';
    final status = e['status'] is num ? (e['status'] as num).toInt() : 0;
    final reqH = _h(e['reqHeaders']);
    final resH = _h(e['resHeaders']);
    final resBody = '${e['resBody'] ?? ''}';
    final reqBody = '${e['reqBody'] ?? ''}';
    final captured = e['resHeaders'] != null || e['reqHeaders'] != null;
    Object? json;
    try {
      if (resBody.isNotEmpty && RegExp(r'^\s*[\[{]').hasMatch(resBody)) json = jsonDecode(resBody);
    } catch (_) {}
    final u = Uri.tryParse(url);
    return Scaffold(
      backgroundColor: XC.side,
      appBar: AppBar(
        backgroundColor: XC.bar,
        titleSpacing: 0,
        title: Text(u?.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? url, style: XC.mono(14), overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            color: XC.side,
            icon: const Icon(Icons.more_vert_rounded, color: XC.dim),
            onSelected: (v) {
              switch (v) {
                case 'url':
                  dtCopy(context, url, 'Copied URL');
                case 'curl':
                  dtCopy(context, _curl(), 'Copied as cURL');
                case 'fetch':
                  dtCopy(context, _fetch(), 'Copied as fetch');
                case 'body':
                  dtCopy(context, resBody, 'Copied response');
                case 'replay':
                  _replay();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'url', child: Text('Copy URL')),
              const PopupMenuItem(value: 'curl', child: Text('Copy as cURL')),
              const PopupMenuItem(value: 'fetch', child: Text('Copy as fetch')),
              if (resBody.isNotEmpty) const PopupMenuItem(value: 'body', child: Text('Copy response')),
              if (!_ws && e['fromTiming'] != true) const PopupMenuItem(value: 'replay', child: Text('Replay request')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          labelColor: XC.accent,
          unselectedLabelColor: XC.dim,
          indicatorColor: XC.accent,
          tabs: [
            const Tab(text: 'Headers'),
            if (!_ws) const Tab(text: 'Payload'),
            Tab(text: _ws ? 'Messages' : 'Response'),
            const Tab(text: 'Timing'),
          ],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        ListView(children: [
          const DtSection('General'),
          DtKV('Request URL', url),
          DtKV('Method', '${e['method'] ?? 'GET'}'),
          DtKV('Status', e['fromTiming'] == true ? '(loaded by the browser)' : (status == 0 ? 'failed${e['error'] != null ? ' — ${e['error']}' : ''}' : '$status ${e['statusText'] ?? ''}'),
              valueColor: statusColor(status)),
          DtKV('Type', '${e['type'] ?? ''}${e['mime'] != null && '${e['mime']}'.isNotEmpty ? ' · ${e['mime']}' : ''}'),
          if (e['redirected'] == true) const DtKV('Redirected', 'yes'),
          DtKV('Initiator page', '${e['page'] ?? ''}'),
          if (!captured && e['fromTiming'] != true)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Headers and bodies are recorded for requests made after Dev Tools was opened on this tab. Reload the page to capture them.',
                  style: XC.ui(12, color: XC.warning)),
            ),
          if (e['fromTiming'] == true)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Loaded directly by the browser engine (script, style, image or font). Its timing and size come from the page’s Resource Timing; headers aren’t exposed to pages.',
                  style: XC.ui(12, color: XC.faint)),
            ),
          if (resH.isNotEmpty) ...[
            DtSection('Response headers (${resH.length})'),
            for (final h in resH.entries) DtKV(h.key, h.value),
          ],
          if (reqH.isNotEmpty) ...[
            DtSection('Request headers (${reqH.length})'),
            for (final h in reqH.entries) DtKV(h.key, h.value),
          ],
          if (u != null && u.queryParameters.isNotEmpty) ...[
            DtSection('Query string (${u.queryParameters.length})'),
            for (final q in u.queryParametersAll.entries) DtKV(q.key, q.value.join(', ')),
          ],
        ]),
        if (!_ws)
          reqBody.isEmpty
              ? const DtEmpty(Icons.upload_outlined, 'No request body')
              : ListView(children: [
                  if (reqBody.contains('=') && !reqBody.trimLeft().startsWith('{')) ...[
                    const DtSection('Form data'),
                    for (final p in reqBody.split('&'))
                      DtKV(_decQ(p.split('=').first), p.contains('=') ? _decQ(p.substring(p.indexOf('=') + 1)) : ''),
                  ],
                  const DtSection('Raw'),
                  DtCode(prettyJson(reqBody), label: 'payload'),
                ]),
        if (_ws)
          ListView(children: [
            for (final f in (e['frames'] as List? ?? const []).whereType<Map>())
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: f['dir'] == 'out' ? XC.added.withOpacity(0.5) : (f['dir'] == 'close' ? XC.removed.withOpacity(0.5) : null),
                  border: const Border(bottom: BorderSide(color: Color(0xFF13203A))),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(f['dir'] == 'out' ? Icons.arrow_upward_rounded : (f['dir'] == 'in' ? Icons.arrow_downward_rounded : Icons.close_rounded),
                      size: 14, color: f['dir'] == 'out' ? XC.ok : XC.info),
                  const SizedBox(width: 8),
                  Expanded(child: SelectableText('${f['data']}', style: XC.mono(11.5))),
                ]),
              ),
            if ((e['frames'] as List? ?? const []).isEmpty)
              const Padding(padding: EdgeInsets.all(20), child: Text('No messages recorded yet.', style: TextStyle(color: XC.faint))),
          ])
        else
          resBody.isEmpty
              ? DtEmpty(Icons.download_outlined, 'No response body recorded',
                  body: e['fromTiming'] == true
                      ? 'Open it in Sources to read the file.'
                      : (captured ? 'Binary or empty response.' : 'Reload with Dev Tools open to capture response bodies.'))
              : Column(children: [
                  if (json != null)
                    Row(children: [
                      const SizedBox(width: 8),
                      DtChip('Tree', selected: _tree, onTap: () => setState(() => _tree = true)),
                      DtChip('Raw', selected: !_tree, onTap: () => setState(() => _tree = false)),
                      const Spacer(),
                      Text(fmtBytes(resBody.length), style: XC.ui(11, color: XC.faint)),
                      const SizedBox(width: 10),
                    ]),
                  Expanded(
                    child: json != null && _tree
                        ? ListView(padding: const EdgeInsets.symmetric(vertical: 6), children: [JsonTree(json)])
                        : ListView(children: [DtCode(json != null ? const JsonEncoder.withIndent('  ').convert(json) : resBody, label: 'response')]),
                  ),
                ]),
        ListView(padding: const EdgeInsets.all(12), children: [
          DtKV('Started', e['start'] is num ? DateTime.fromMillisecondsSinceEpoch((e['start'] as num).toInt()).toIso8601String().replaceFirst('T', ' ').substring(0, 23) : '—'),
          DtKV('Duration', fmtMs(e['ms'] as num?)),
          DtKV('Size', fmtBytes((e['size'] as num?) ?? 0)),
          const SizedBox(height: 12),
          if (e['ms'] is num)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: 1,
                minHeight: 10,
                color: ((e['ms'] as num) > 1000) ? XC.warning : XC.accent,
                backgroundColor: XC.bg,
              ),
            ),
        ]),
      ]),
    );
  }
}
