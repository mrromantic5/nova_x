// lib/features/browser/devtools/tabs/device_tab.dart
//
// Device & page settings for this tab (until you change them back):
// user-agent presets / custom UA, desktop layout, JavaScript, images, cache,
// text zoom, dark mode for the page, and page info (frameworks detected,
// viewport, DPR, element counts).

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../devtools_bridge.dart';
import '../dt_ui.dart';

class DeviceTab extends StatefulWidget {
  const DeviceTab({super.key, required this.bridge, required this.wvc});
  final DevtoolsBridge bridge;
  final InAppWebViewController? wvc;

  @override
  State<DeviceTab> createState() => _DeviceTabState();
}

class _DeviceTabState extends State<DeviceTab> {
  InAppWebViewSettings? _s;
  Map<String, dynamic>? _info;

  static const _uas = <(String, String)>[
    ('Default (this phone)', ''),
    ('Chrome · Android', 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36'),
    ('Safari · iPhone', 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1'),
    ('Safari · iPad', 'Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1'),
    ('Chrome · Windows', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'),
    ('Chrome · macOS', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'),
    ('Firefox · Windows', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:127.0) Gecko/20100101 Firefox/127.0'),
    ('Googlebot (smartphone)', 'Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await widget.wvc?.getSettings();
    final i = await widget.bridge.call('info');
    if (!mounted) return;
    setState(() {
      _s = s;
      _info = i.ok ? i.map : null;
    });
  }

  Future<void> _apply(InAppWebViewSettings change, {bool reload = true}) async {
    final c = widget.wvc;
    if (c == null) return;
    await c.setSettings(settings: change);
    if (reload) await c.reload();
    await Future.delayed(const Duration(milliseconds: 300));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final info = _info;
    if (widget.wvc == null) return const DtEmpty(Icons.phone_android_rounded, 'No page');
    final ua = s?.userAgent ?? '';
    return ListView(children: [
      const DtSection('User agent'),
      for (final (label, value) in _uas)
        RadioListTile<String>(
          dense: true,
          value: value,
          groupValue: _uas.any((e) => e.$2 == ua) ? ua : '__custom',
          activeColor: XC.accent,
          title: Text(label, style: XC.ui(13)),
          onChanged: (v) => _apply(InAppWebViewSettings(userAgent: v ?? '')),
        ),
      ListTile(
        dense: true,
        leading: const Icon(Icons.edit_outlined, size: 18, color: XC.dim),
        title: Text('Custom user agent…', style: XC.ui(13)),
        subtitle: ua.isNotEmpty && !_uas.any((e) => e.$2 == ua) ? Text(ua, style: XC.mono(10.5, color: XC.faint), maxLines: 2) : null,
        onTap: () async {
          final v = await xPrompt(context, title: 'Custom user agent', initial: ua, action: 'Apply');
          if (v != null) _apply(InAppWebViewSettings(userAgent: v));
        },
      ),
      const DtSection('Page'),
      SwitchListTile(
        dense: true,
        activeColor: XC.accent,
        title: Text('Desktop layout', style: XC.ui(13)),
        subtitle: Text('Wide viewport, zoomed out to fit', style: XC.ui(11.5, color: XC.faint)),
        value: s?.preferredContentMode == UserPreferredContentMode.DESKTOP,
        onChanged: (v) => _apply(InAppWebViewSettings(
          preferredContentMode: v ? UserPreferredContentMode.DESKTOP : UserPreferredContentMode.RECOMMENDED,
          useWideViewPort: true,
          loadWithOverviewMode: v,
        )),
      ),
      SwitchListTile(
        dense: true,
        activeColor: XC.accent,
        title: Text('JavaScript', style: XC.ui(13)),
        subtitle: Text('Turn off to see the page without scripts (Dev Tools needs it to inspect)', style: XC.ui(11.5, color: XC.faint)),
        value: s?.javaScriptEnabled ?? true,
        onChanged: (v) => _apply(InAppWebViewSettings(javaScriptEnabled: v)),
      ),
      SwitchListTile(
        dense: true,
        activeColor: XC.accent,
        title: Text('Load images', style: XC.ui(13)),
        value: !(s?.blockNetworkImage ?? false),
        onChanged: (v) => _apply(InAppWebViewSettings(blockNetworkImage: !v, loadsImagesAutomatically: v)),
      ),
      SwitchListTile(
        dense: true,
        activeColor: XC.accent,
        title: Text('Use cache', style: XC.ui(13)),
        subtitle: Text('Off = like “Disable cache” in desktop Dev Tools', style: XC.ui(11.5, color: XC.faint)),
        value: s?.cacheEnabled ?? true,
        onChanged: (v) => _apply(InAppWebViewSettings(cacheEnabled: v, cacheMode: v ? CacheMode.LOAD_DEFAULT : CacheMode.LOAD_NO_CACHE)),
      ),
      SwitchListTile(
        dense: true,
        activeColor: XC.accent,
        title: Text('Force dark page', style: XC.ui(13)),
        subtitle: Text('Lets the browser darken pages that have no dark theme', style: XC.ui(11.5, color: XC.faint)),
        value: s?.algorithmicDarkeningAllowed ?? false,
        onChanged: (v) => _apply(InAppWebViewSettings(algorithmicDarkeningAllowed: v, forceDark: v ? ForceDark.ON : ForceDark.AUTO), reload: false),
      ),
      ListTile(
        dense: true,
        title: Text('Text zoom', style: XC.ui(13)),
        subtitle: Slider(
          value: ((s?.textZoom ?? 100).clamp(50, 200)).toDouble(),
          min: 50,
          max: 200,
          divisions: 15,
          label: '${s?.textZoom ?? 100}%',
          onChanged: (v) => setState(() => _s?.textZoom = v.round()),
          onChangeEnd: (v) => _apply(InAppWebViewSettings(textZoom: v.round()), reload: false),
        ),
        trailing: Text('${s?.textZoom ?? 100}%', style: XC.mono(12)),
      ),
      ListTile(
        dense: true,
        leading: const Icon(Icons.cleaning_services_outlined, size: 18, color: XC.dim),
        title: Text('Clear browser cache & hard reload', style: XC.ui(13)),
        onTap: () async {
          await InAppWebViewController.clearAllCache();
          await widget.wvc?.reloadFromOrigin();
          if (context.mounted) xToast(context, 'Cache cleared');
        },
      ),
      if (info != null) ...[
        const DtSection('This page'),
        DtKV('title', '${info['title']}'),
        DtKV('URL', '${info['url']}'),
        DtKV('secure context', '${info['secure']}', valueColor: info['secure'] == true ? XC.ok : XC.warning),
        DtKV('viewport meta', '${info['viewport']}'.isEmpty ? '(none)' : '${info['viewport']}'),
        DtKV('window', '${info['window']} CSS px · DPR ${info['dpr']}'),
        DtKV('screen', '${info['screen']}'),
        DtKV('charset · lang', '${info['charset']} · ${'${info['lang']}'.isEmpty ? '(no lang)' : info['lang']}'),
        DtKV('render mode', '${info['mode']}${'${info['doctype']}'.isEmpty ? ' (no doctype)' : ''}'),
        DtKV('frameworks', ((info['frameworks'] as List?) ?? const []).isEmpty ? 'none detected' : (info['frameworks'] as List).join(', ')),
        if (info['counts'] is Map)
          for (final e in (info['counts'] as Map).entries) DtKV('${e.key}', '${e.value}'),
        DtKV('user agent', '${info['ua']}'),
      ],
    ]);
  }
}
