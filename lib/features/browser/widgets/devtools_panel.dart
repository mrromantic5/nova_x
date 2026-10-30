// lib/features/browser/widgets/devtools_panel.dart
//
// NOVA X Developer Tools (3.11.0) — a Chrome-DevTools-style inspector docked
// under the page:
//   Elements · Console · Sources · Network · Application · Performance ·
//   Audit (Lighthouse-style + security) · Device · Tools
//
// Usage (unchanged): showDevTools(context, wvc: …, url: …, pageTitle: …,
//   consoleLogs: …, onClearConsole: …, networkLogs: …, onClearNetwork: …)
// New optional: inspectPath (select an element), changes (live updates).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:nova_x/core/services/rewards_entitlements.dart';
import 'package:nova_x/core/services/rewards_service.dart';
import 'package:nova_x/core/widgets/feature_lock.dart';

import '../devtools/devtools_bridge.dart';
import '../devtools/dt_ui.dart';
import '../devtools/tabs/application_tab.dart';
import '../devtools/tabs/console_tab.dart';
import '../devtools/tabs/device_tab.dart';
import '../devtools/tabs/elements_tab.dart';
import '../devtools/tabs/network_tab.dart';
import '../devtools/tabs/perf_tab.dart';
import '../devtools/tabs/sources_tab.dart';
import '../devtools/tabs/tools_tab.dart';

void showDevTools(
  BuildContext context, {
  required InAppWebViewController? wvc,
  required String url,
  required String pageTitle,
  required List<Map<String, dynamic>> consoleLogs,
  required VoidCallback onClearConsole,
  List<Map<String, dynamic>> networkLogs = const [],
  VoidCallback? onClearNetwork,
  List<int>? inspectPath,
  Stream<void>? changes,
}) {
  if (!RewardsEntitlements.isUnlocked(RewardFeature.devtools)) {
    showFeatureUnlockSheet(context, RewardFeature.devtools);
    return;
  }
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black26,
    useSafeArea: true,
    builder: (_) => DevToolsSheet(
      wvc: wvc,
      url: url,
      pageTitle: pageTitle,
      consoleLogs: consoleLogs,
      onClearConsole: onClearConsole,
      networkLogs: networkLogs,
      onClearNetwork: onClearNetwork,
      inspectPath: inspectPath,
      changes: changes,
    ),
  );
}

class DevToolsSheet extends StatefulWidget {
  const DevToolsSheet({
    super.key,
    required this.wvc,
    required this.url,
    required this.pageTitle,
    required this.consoleLogs,
    required this.onClearConsole,
    required this.networkLogs,
    required this.onClearNetwork,
    this.inspectPath,
    this.changes,
  });

  final InAppWebViewController? wvc;
  final String url;
  final String pageTitle;
  final List<Map<String, dynamic>> consoleLogs;
  final VoidCallback onClearConsole;
  final List<Map<String, dynamic>> networkLogs;
  final VoidCallback? onClearNetwork;
  final List<int>? inspectPath;
  final Stream<void>? changes;

  @override
  State<DevToolsSheet> createState() => _DevToolsSheetState();
}

class _DevToolsSheetState extends State<DevToolsSheet> with SingleTickerProviderStateMixin {
  static int _lastTab = 0;
  static double _lastSize = 0.62;

  late final DevtoolsBridge _bridge = DevtoolsBridge(widget.wvc);
  late final TabController _tabs;
  late double _size = _lastSize;
  final _consoleSeed = ValueNotifier<String>('');
  List<int>? _reveal;
  int _revealGen = 0;
  StreamSubscription<void>? _sub;

  static const _tabDefs = <(IconData, String)>[
    (Icons.code_rounded, 'Elements'),
    (Icons.terminal_rounded, 'Console'),
    (Icons.folder_open_rounded, 'Sources'),
    (Icons.swap_vert_rounded, 'Network'),
    (Icons.storage_rounded, 'Application'),
    (Icons.speed_rounded, 'Performance'),
    (Icons.fact_check_outlined, 'Audit'),
    (Icons.phone_android_rounded, 'Device'),
    (Icons.build_outlined, 'Tools'),
  ];

  @override
  void initState() {
    super.initState();
    _reveal = widget.inspectPath;
    _tabs = TabController(length: _tabDefs.length, vsync: this, initialIndex: widget.inspectPath != null ? 0 : _lastTab);
    _tabs.addListener(() => _lastTab = _tabs.index);
    _sub = widget.changes?.listen((_) {
      if (mounted && (_tabs.index == 1 || _tabs.index == 3)) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _bridge.call('unhighlight');
    _bridge.call('cancelPick');
    _tabs.dispose();
    _consoleSeed.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final r = await _bridge.call('pick');
    if (!mounted) return;
    if (!r.ok) {
      xToast(context, 'Can’t inspect this page: ${r.error}', error: true);
      return;
    }
    Navigator.pop(context); // the page reports the tapped element → Dev Tools reopens on it
  }

  void _revealElement(List<int> path) {
    setState(() {
      _reveal = path;
      _revealGen++;
    });
    _tabs.animateTo(0);
  }

  void _useInConsole(String expr) {
    _consoleSeed.value = '';
    _consoleSeed.value = expr;
    _tabs.animateTo(1);
  }

  Future<void> _reload() async {
    await widget.wvc?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final errors = widget.consoleLogs.where((l) => l['type'] == 'error').length;
    final host = Uri.tryParse(widget.url)?.host ?? widget.url;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: h * _size,
      decoration: const BoxDecoration(
        color: XC.side,
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 18)],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (d) => setState(() => _size = (_size - d.delta.dy / h).clamp(0.3, 0.97)),
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 900 && _size < 0.45) {
              Navigator.pop(context);
              return;
            }
            // snap
            const snaps = [0.35, 0.62, 0.95];
            final target = snaps.reduce((a, b) => (a - _size).abs() < (b - _size).abs() ? a : b);
            setState(() => _size = target);
            _lastSize = target;
          },
          child: Container(
            color: XC.bar,
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 2),
            child: Column(children: [
              Container(width: 36, height: 4, decoration: BoxDecoration(color: XC.border, borderRadius: BorderRadius.circular(2))),
              Row(children: [
                const Icon(Icons.developer_mode_rounded, color: XC.accent, size: 18),
                const SizedBox(width: 8),
                Text('DevTools', style: XC.ui(14.5, weight: FontWeight.w800)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(host, style: XC.mono(11.5, color: XC.faint), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                XIconBtn(Icons.ads_click_rounded, tooltip: 'Select an element on the page', onTap: _pick, color: XC.accent),
                XIconBtn(Icons.refresh_rounded, tooltip: 'Reload page', onTap: _reload),
                XIconBtn(_size > 0.9 ? Icons.close_fullscreen_rounded : Icons.open_in_full_rounded,
                    tooltip: _size > 0.9 ? 'Dock' : 'Full height',
                    onTap: () => setState(() => _lastSize = _size = _size > 0.9 ? 0.62 : 0.95),
                    size: 18),
                XIconBtn(Icons.close_rounded, tooltip: 'Close', onTap: () => Navigator.pop(context)),
              ]),
            ]),
          ),
        ),
        Container(
          color: XC.bar,
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: XC.accent,
            unselectedLabelColor: XC.dim,
            indicatorColor: XC.accent,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: XC.ui(12.5, weight: FontWeight.w700),
            unselectedLabelStyle: XC.ui(12.5),
            dividerColor: XC.border,
            labelPadding: const EdgeInsets.symmetric(horizontal: 10),
            tabs: [
              for (final (i, (icon, label)) in _tabDefs.indexed)
                Tab(
                  height: 38,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 15),
                    const SizedBox(width: 5),
                    Text(label),
                    if (i == 1 && errors > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: XC.error, borderRadius: BorderRadius.circular(8)),
                        child: Text('$errors', style: XC.ui(9.5, color: Colors.white, weight: FontWeight.w800)),
                      ),
                    ],
                    if (i == 3 && widget.networkLogs.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text('${widget.networkLogs.length}', style: XC.ui(10, color: XC.faint)),
                    ],
                  ]),
                ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              ElementsTab(
                key: ValueKey('el$_revealGen'),
                bridge: _bridge,
                initialPath: _reveal,
                onPick: _pick,
                onUseInConsole: _useInConsole,
              ),
              ConsoleTab(
                bridge: _bridge,
                logs: widget.consoleLogs,
                changes: widget.changes,
                onClear: () {
                  widget.onClearConsole();
                  setState(() {});
                },
                inputSeed: _consoleSeed,
                onRevealElement: _revealElement,
              ),
              SourcesTab(bridge: _bridge, pageUrl: widget.url),
              NetworkTab(
                bridge: _bridge,
                logs: widget.networkLogs,
                changes: widget.changes,
                onClear: widget.onClearNetwork == null
                    ? null
                    : () {
                        widget.onClearNetwork!();
                        setState(() {});
                      },
                onReload: _reload,
              ),
              ApplicationTab(bridge: _bridge, pageUrl: widget.url),
              PerformanceTab(bridge: _bridge, onReload: _reload),
              AuditTab(bridge: _bridge, wvc: widget.wvc),
              DeviceTab(bridge: _bridge, wvc: widget.wvc),
              const ToolsTab(),
            ],
          ),
        ),
      ]),
    );
  }
}
