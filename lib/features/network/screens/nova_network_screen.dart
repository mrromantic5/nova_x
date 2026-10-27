// lib/features/network/screens/nova_network_screen.dart
//
// NOVA Network — real internet speed test and connection centre.
//   Speed   : ping/jitter → multi-connection download → upload (real data
//             against the nearest NOVA speed server), live gauge + chart,
//             loaded latency (bufferbloat), quality for streaming/gaming/
//             calls/browsing, data used, copy result. Light mode for mobile data.
//   Device  : device name, Android, battery %, charging, temperature;
//             connection type, Wi-Fi band/link speed/signal or mobile
//             operator; public IP, ISP, approximate location (from the IP —
//             no GPS); local IPs, DNS, Private DNS, IPv6; RAM, storage, CPU.
//   Tools   : latency monitor (30 s), DNS lookup speed, popular service check.
//   History : past tests on this phone with averages and a chart.
// "Hey NOVA, what's my internet speed?" runs the same test in the background.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../models/network_models.dart';
import '../services/network_services.dart';
import '../services/speed_math.dart';
import '../services/speed_test_engine.dart';
import '../widgets/cyber_widgets.dart';

class NovaNetworkScreen extends StatefulWidget {
  const NovaNetworkScreen({super.key, this.autoStart = false});

  /// Start a test as soon as the page opens.
  final bool autoStart;

  @override
  State<NovaNetworkScreen> createState() => _NovaNetworkScreenState();
}

class _NovaNetworkScreenState extends State<NovaNetworkScreen> with TickerProviderStateMixin {
  static const _tabs = ['Speed', 'Device', 'Tools', 'History'];
  int _tab = 0;

  // Speed test
  SpeedTestEngine? _engine;
  SpeedProgress? _progress;
  SpeedTestResult? _result;
  String? _error;
  bool _light = false;
  double _maxSeen = 0;

  // Info
  NetworkMeta? _meta;
  String? _metaError;
  DeviceSnapshot? _device;
  bool _hideIp = false;
  Timer? _deviceTimer;

  // History
  List<SpeedTestResult> _history = const [];

  // Tools
  final List<LatencySample> _latency = [];
  StreamSubscription<LatencySample>? _latencySub;
  List<DnsCheck> _dns = const [];
  bool _dnsRunning = false;
  List<SiteCheck> _sites = const [];
  bool _sitesRunning = false;

  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  bool get _running => _engine != null;

  @override
  void initState() {
    super.initState();
    _loadInfo();
    SpeedHistory.load().then((h) {
      if (mounted) setState(() => _history = h);
    });
    _deviceTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _tab == 1 && !_running) _refreshDevice();
    });
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start(skipDataWarning: true));
    }
  }

  @override
  void dispose() {
    _engine?.cancel();
    _deviceTimer?.cancel();
    _latencySub?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _loadInfo() async {
    await _refreshDevice();
    try {
      final meta = await SpeedTestEngine().fetchMeta();
      if (mounted) {
        setState(() {
          _meta = meta;
          _metaError = null;
        });
      }
    } on SpeedTestException catch (e) {
      if (mounted) setState(() => _metaError = e.message);
    }
  }

  Future<void> _refreshDevice() async {
    final d = await DeviceInfoService.read();
    if (mounted) setState(() => _device = d);
  }

  // ── Speed test ─────────────────────────────────────────────────────────────

  Future<void> _start({bool skipDataWarning = false}) async {
    if (_running) return;
    final device = _device;
    if (device != null && !device.connected) {
      setState(() => _error = "You're offline. Turn on Wi-Fi or mobile data and try again.");
      return;
    }
    if (!skipDataWarning && !_light && device != null && (device.transport == 'cellular' || device.metered)) {
      final choice = await _dataWarning();
      if (choice == null || !mounted) return;
      setState(() => _light = choice == 'light');
    }
    final engine = SpeedTestEngine();
    HapticFeedback.mediumImpact();
    setState(() {
      _engine = engine;
      _result = null;
      _error = null;
      _maxSeen = 0;
      _progress = const SpeedProgress(phase: SpeedPhase.connecting, progress: 0.01);
    });
    try {
      final result = await engine.run(
        _light ? SpeedTestOptions.light : SpeedTestOptions.full,
        meta: _meta,
        connection: device?.connectionLabel ?? '',
        onProgress: (p) {
          if (!mounted || !identical(_engine, engine)) return;
          setState(() {
            _progress = p;
            _maxSeen = math.max(_maxSeen, p.liveMbps);
          });
        },
      );
      final history = await SpeedHistory.add(result);
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _result = result;
        _history = history;
      });
      if (_meta == null) _loadInfo();
    } on SpeedTestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'The speed test could not finish. Please try again.');
    } finally {
      if (mounted && identical(_engine, engine)) setState(() => _engine = null);
    }
  }

  void _stop() {
    _engine?.cancel();
    setState(() {
      _engine = null;
      _progress = null;
      _error = 'Speed test stopped.';
    });
  }

  Future<String?> _dataWarning() => showModalBottomSheet<String>(
        context: context,
        backgroundColor: Cyber.panel,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.signal_cellular_alt_rounded, color: Cyber.amber),
                const SizedBox(width: 10),
                Text("You're on mobile data", style: GoogleFonts.spaceGrotesk(color: Cyber.text, fontSize: 18, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 10),
              Text(
                'A full test downloads and uploads as much as your connection allows for about 20 seconds '
                '— on fast 4G/5G that can be several hundred MB. The light test uses about 50 MB.',
                style: Cyber.label(13.5, color: Cyber.dim).copyWith(height: 1.5),
              ),
              const SizedBox(height: 18),
              _sheetButton(ctx, 'Light test (≈ 50 MB)', 'light', filled: true),
              const SizedBox(height: 10),
              _sheetButton(ctx, 'Full test', 'full'),
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: Cyber.label(14, color: Cyber.dim)),
                ),
              ),
            ]),
          ),
        ),
      );

  Widget _sheetButton(BuildContext ctx, String label, String value, {bool filled = false}) => SizedBox(
        width: double.infinity,
        height: 48,
        child: filled
            ? DecoratedBox(
                decoration: BoxDecoration(gradient: AppTheme.primaryGradient, borderRadius: BorderRadius.circular(14)),
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, value),
                  child: Text(label, style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              )
            : OutlinedButton(
                onPressed: () => Navigator.pop(ctx, value),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Cyber.cyan.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(label, style: GoogleFonts.spaceGrotesk(color: Cyber.cyan, fontSize: 15, fontWeight: FontWeight.w700)),
              ),
      );

  void _copyResult(SpeedTestResult r) {
    final lines = [
      'NOVA Network speed test — ${_dateTime(r.time)}',
      'Download ${SpeedMath.speedText(r.downloadMbps)} Mbps · Upload ${SpeedMath.speedText(r.uploadMbps)} Mbps',
      'Ping ${r.pingMs.round()} ms · Jitter ${r.jitterMs.round()} ms'
          '${r.loadedDownMs > 0 ? ' · Loaded ${r.loadedDownMs.round()} ms' : ''}',
      [if (r.connection.isNotEmpty) r.connection, if (r.isp != null) r.isp!, if (r.server != null) 'Server ${r.server}']
          .join(' · '),
      'Tested with NOVA X Browser',
    ];
    Clipboard.setData(ClipboardData(text: lines.where((l) => l.isNotEmpty).join('\n')));
    _toast('Result copied');
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)));

  // ── Tools ──────────────────────────────────────────────────────────────────

  void _toggleLatency() {
    if (_latencySub != null) {
      _latencySub?.cancel();
      setState(() => _latencySub = null);
      return;
    }
    setState(() => _latency.clear());
    _latencySub = NetworkTools.latencyMonitor().listen(
      (s) {
        if (mounted) setState(() => _latency.add(s));
      },
      onDone: () {
        if (mounted) setState(() => _latencySub = null);
      },
    );
    setState(() {});
  }

  Future<void> _runDns() async {
    setState(() {
      _dnsRunning = true;
      _dns = const [];
    });
    await NetworkTools.dnsLookups(onEach: (c) {
      if (mounted) setState(() => _dns = [..._dns, c]);
    });
    if (mounted) setState(() => _dnsRunning = false);
  }

  Future<void> _runSites() async {
    setState(() {
      _sitesRunning = true;
      _sites = const [];
    });
    await NetworkTools.checkSites(onEach: (c) {
      if (mounted) setState(() => _sites = [..._sites, c]);
    });
    if (mounted) setState(() => _sitesRunning = false);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Cyber.bg,
      body: CyberBackground(
        child: SafeArea(
          child: Column(children: [
            _appBar(),
            _tabBar(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: KeyedSubtree(
                  key: ValueKey(_tab),
                  child: switch (_tab) {
                    0 => _speedTab(),
                    1 => _deviceTab(),
                    2 => _toolsTab(),
                    _ => _historyTab(),
                  },
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _appBar() => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 12, 4),
        child: Row(children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded, color: Cyber.text),
          ),
          ShaderMask(
            shaderCallback: (b) => AppTheme.primaryGradient.createShader(b),
            child: Text('NOVA', style: GoogleFonts.getFont('Orbitron', color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 3)),
          ),
          const SizedBox(width: 8),
          Text('NETWORK', style: GoogleFonts.getFont('Orbitron', color: Cyber.text, fontSize: 18, fontWeight: FontWeight.w500, letterSpacing: 3)),
          const Spacer(),
          _statusDot(),
        ]),
      );

  Widget _statusDot() {
    final d = _device;
    final online = d == null || d.connected;
    final color = !online ? Cyber.red : (_running ? Cyber.amber : Cyber.green);
    final text = !online ? 'OFFLINE' : (_running ? 'TESTING' : 'ONLINE');
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4 + 0.5 * (1 - _pulse.value)), blurRadius: 8)],
            ),
          ),
          const SizedBox(width: 6),
          Text(text, style: GoogleFonts.spaceGrotesk(color: color, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
        ]),
      ),
    );
  }

  Widget _tabBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: Container(
          height: 44,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Cyber.panel.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Cyber.line),
          ),
          child: Row(children: [
            for (var i = 0; i < _tabs.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _tab = i);
                    if (i == 1) _refreshDevice();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: _tab == i ? AppTheme.primaryGradient : null,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_tabs[i],
                        style: GoogleFonts.spaceGrotesk(
                          color: _tab == i ? Colors.white : Cyber.dim,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        )),
                  ),
                ),
              ),
          ]),
        ),
      );

  // ── Speed tab ──────────────────────────────────────────────────────────────

  Widget _speedTab() {
    final p = _progress;
    final r = _result;
    final phase = p?.phase ?? SpeedPhase.idle;
    final live = _running && (phase == SpeedPhase.download || phase == SpeedPhase.upload) ? p!.liveMbps : 0.0;
    final gaugeValue = _running ? live : (r?.downloadMbps ?? 0.0);
    final gaugeColor = phase == SpeedPhase.upload ? Cyber.purple : Cyber.cyan;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        _connectionStrip(),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, c) {
          final size = math.min(c.maxWidth, 340.0);
          return Center(
            child: SizedBox(
              width: size,
              child: SpeedGauge(
                mbps: gaugeValue,
                scale: SpeedMath.ticksFor(math.max(_maxSeen, r?.downloadMbps ?? 0.0)),
                color: gaugeColor,
                center: _gaugeCenter(phase, live, r),
              ),
            ),
          );
        }),
        _phaseSteps(phase),
        const SizedBox(height: 14),
        _statTiles(p, r),
        if (_running || r != null) ...[
          const SizedBox(height: 12),
          NeonCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('LIVE THROUGHPUT', style: Cyber.label(11, weight: FontWeight.w700).copyWith(letterSpacing: 1.6)),
                const Spacer(),
                _legend(Cyber.cyan, 'Download'),
                const SizedBox(width: 10),
                _legend(Cyber.purple, 'Upload'),
              ]),
              const SizedBox(height: 10),
              LiveChart(down: p?.downChart ?? const [], up: p?.upChart ?? const []),
            ]),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          _errorBox(_error!),
        ],
        const SizedBox(height: 14),
        _controls(),
        if (r != null && !_running) ...[
          const SizedBox(height: 18),
          _qualityCard(r),
          const SizedBox(height: 12),
          _detailsCard(r),
        ],
        const SizedBox(height: 14),
        _privacyNote(),
      ],
    );
  }

  Widget _legend(Color c, String t) => Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(t, style: Cyber.label(11)),
      ]);

  Widget _connectionStrip() {
    final m = _meta;
    final d = _device;
    return NeonCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Column(children: [
        Row(children: [
          _roundIcon(Icons.person_outline_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m?.isp ?? (_metaError != null ? 'Provider unknown' : 'Finding your provider…'),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(color: Cyber.text, fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(m == null ? '—' : (_hideIp ? _maskIp(m.ip) : m.ip),
                  style: Cyber.digits(12.5, color: Cyber.dim, weight: FontWeight.w500)),
            ]),
          ),
          if (m != null)
            IconButton(
              tooltip: _hideIp ? 'Show IP' : 'Hide IP',
              onPressed: () => setState(() => _hideIp = !_hideIp),
              icon: Icon(_hideIp ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18, color: Cyber.dim),
            ),
        ]),
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: Cyber.line)),
        Row(children: [
          _roundIcon(Icons.dns_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m == null ? (_metaError ?? 'Finding the nearest server…') : 'NOVA Speed Server · ${m.serverName}',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(color: Cyber.text, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                [
                  if (d != null) d.connectionLabel,
                  if (d?.wifiBand != null) d!.wifiBand!,
                  if (d?.carrier != null) d!.carrier!,
                  _light ? 'Light test' : 'Multi-connection',
                ].join(' · '),
                style: Cyber.label(12),
              ),
            ]),
          ),
          if (d?.signalLevel != null) SignalBars(level: d!.signalLevel!),
        ]),
      ]),
    );
  }

  static String _maskIp(String ip) {
    if (ip.isEmpty) return '—';
    if (ip.contains(':')) {
      final parts = ip.split(':');
      return '${parts.take(2).join(':')}:••••:••••';
    }
    final parts = ip.split('.');
    return parts.length == 4 ? '${parts[0]}.${parts[1]}.•••.•••' : '•••';
  }

  Widget _roundIcon(IconData icon) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Cyber.cyan.withValues(alpha: 0.35)),
          color: Cyber.cyan.withValues(alpha: 0.06),
        ),
        child: Icon(icon, color: Cyber.cyan, size: 20),
      );

  Widget _gaugeCenter(SpeedPhase phase, double live, SpeedTestResult? r) {
    if (!_running && r == null) {
      // GO button with pulsing rings.
      return AnimatedBuilder(
        animation: _pulse,
        builder: (_, __) {
          final t = _pulse.value;
          return GestureDetector(
            onTap: () => _start(),
            child: Stack(alignment: Alignment.center, children: [
              Container(
                width: 120 + 40 * t,
                height: 120 + 40 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Cyber.cyan.withValues(alpha: 0.5 * (1 - t)), width: 2),
                ),
              ),
              Container(
                width: 124,
                height: 124,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF050B17),
                  border: Border.all(color: Cyber.cyan, width: 2.5),
                  boxShadow: [BoxShadow(color: Cyber.cyan.withValues(alpha: 0.35), blurRadius: 30)],
                ),
                alignment: Alignment.center,
                child: Text('GO', style: GoogleFonts.getFont('Orbitron', color: Colors.white, fontSize: 38, fontWeight: FontWeight.w600)),
              ),
            ]),
          );
        },
      );
    }
    if (_running) {
      final p = _progress;
      final label = switch (phase) {
        SpeedPhase.connecting => 'CONNECTING',
        SpeedPhase.latency => 'PING',
        SpeedPhase.download => 'DOWNLOAD',
        SpeedPhase.upload => 'UPLOAD',
        _ => 'TESTING',
      };
      final value = phase == SpeedPhase.latency ? (p?.pingMs?.round().toString() ?? '—') : SpeedMath.speedText(live);
      final unit = phase == SpeedPhase.latency ? 'ms' : 'Mbps';
      return Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 40),
        Text(label, style: Cyber.label(12, color: phase == SpeedPhase.upload ? Cyber.purple : Cyber.cyan, weight: FontWeight.w700).copyWith(letterSpacing: 2.5)),
        const SizedBox(height: 4),
        if (phase == SpeedPhase.connecting)
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: Cyber.cyan))
        else
          Text(value, style: Cyber.digits(40, weight: FontWeight.w500)),
        Text(unit, style: Cyber.label(13)),
      ]);
    }
    return GestureDetector(
      onTap: () => _start(),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 40),
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.arrow_circle_down_rounded, color: Cyber.cyan, size: 16),
          const SizedBox(width: 6),
          Text('DOWNLOAD', style: Cyber.label(12, color: Cyber.cyan, weight: FontWeight.w700).copyWith(letterSpacing: 2.5)),
        ]),
        const SizedBox(height: 4),
        Text(SpeedMath.speedText(r!.downloadMbps), style: Cyber.digits(40, weight: FontWeight.w500)),
        Text('Mbps', style: Cyber.label(13)),
      ]),
    );
  }

  Widget _phaseSteps(SpeedPhase phase) {
    final order = [SpeedPhase.latency, SpeedPhase.download, SpeedPhase.upload];
    final names = ['Ping', 'Download', 'Upload'];
    final idx = switch (phase) {
      SpeedPhase.connecting || SpeedPhase.latency => 0,
      SpeedPhase.download => 1,
      SpeedPhase.upload => 2,
      SpeedPhase.done => 3,
      _ => _result != null ? 3 : -1,
    };
    return Column(children: [
      if (_running)
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 0, 30, 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: _progress?.progress ?? 0.0,
              minHeight: 4,
              backgroundColor: const Color(0xFF16233A),
              valueColor: AlwaysStoppedAnimation(phase == SpeedPhase.upload ? Cyber.purple : Cyber.cyan),
            ),
          ),
        ),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < order.length; i++) ...[
          Icon(
            idx > i ? Icons.check_circle_rounded : (idx == i ? Icons.radio_button_checked_rounded : Icons.circle_outlined),
            size: 15,
            color: idx > i ? Cyber.green : (idx == i ? Cyber.cyan : Cyber.dim),
          ),
          const SizedBox(width: 5),
          Text(names[i], style: Cyber.label(12, color: idx >= i ? Cyber.text : Cyber.dim)),
          if (i < order.length - 1)
            Container(width: 22, height: 1, margin: const EdgeInsets.symmetric(horizontal: 8), color: Cyber.line),
        ],
      ]),
    ]);
  }

  Widget _statTiles(SpeedProgress? p, SpeedTestResult? r) {
    final ping = r?.pingMs ?? p?.pingMs;
    final jitter = r?.jitterMs ?? p?.jitterMs;
    final down = r?.downloadMbps ?? p?.downloadMbps ?? (p?.phase == SpeedPhase.download ? p!.liveMbps : null);
    final up = r?.uploadMbps ?? (p?.phase == SpeedPhase.upload ? p!.liveMbps : null);
    final loadedDown = r?.loadedDownMs ?? (p?.phase == SpeedPhase.download ? p?.loadedMs : null);
    final loadedUp = r?.loadedUpMs ?? (p?.phase == SpeedPhase.upload ? p?.loadedMs : null);
    Widget tile(String title, IconData icon, Color color, String value, String unit, String? foot) => Expanded(
          child: NeonCard(
            accent: color,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 5),
                Flexible(child: Text(title, overflow: TextOverflow.ellipsis, style: Cyber.label(11, weight: FontWeight.w700).copyWith(letterSpacing: 1.2))),
              ]),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: Cyber.digits(20, weight: FontWeight.w600)),
              ),
              Text(unit, style: Cyber.label(11)),
              if (foot != null) ...[
                const SizedBox(height: 6),
                Text(foot, maxLines: 1, overflow: TextOverflow.ellipsis, style: Cyber.label(10.5, color: color.withValues(alpha: 0.9))),
              ],
            ]),
          ),
        );
    return Row(children: [
      tile('PING', Icons.bolt_rounded, Cyber.amber, ping == null ? '—' : '${ping.round()}', 'ms',
          jitter == null ? null : 'Jitter ${jitter.round()} ms'),
      const SizedBox(width: 10),
      tile('DOWNLOAD', Icons.arrow_circle_down_rounded, Cyber.cyan, down == null ? '—' : SpeedMath.speedText(down), 'Mbps',
          loadedDown == null || loadedDown == 0 ? null : 'Loaded ${loadedDown.round()} ms'),
      const SizedBox(width: 10),
      tile('UPLOAD', Icons.arrow_circle_up_rounded, Cyber.purple, up == null ? '—' : SpeedMath.speedText(up), 'Mbps',
          loadedUp == null || loadedUp == 0 ? null : 'Loaded ${loadedUp.round()} ms'),
    ]);
  }

  Widget _controls() {
    if (_running) {
      return Center(
        child: OutlinedButton.icon(
          onPressed: _stop,
          icon: const Icon(Icons.stop_rounded, size: 18),
          label: Text('Stop test', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(
            foregroundColor: Cyber.red,
            side: BorderSide(color: Cyber.red.withValues(alpha: 0.6)),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
        ),
      );
    }
    return Column(children: [
      if (_result != null || _error != null)
        SizedBox(
          width: 220,
          height: 46,
          child: OutlinedButton(
            onPressed: () => _start(),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Cyber.cyan, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            child: Text('Test again', style: GoogleFonts.spaceGrotesk(color: Cyber.text, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _modeChip('Full test', !_light, () => setState(() => _light = false)),
        const SizedBox(width: 8),
        _modeChip('Light · ≈50 MB', _light, () => setState(() => _light = true)),
      ]),
    ]);
  }

  Widget _modeChip(String label, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: on ? Cyber.cyan.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: on ? Cyber.cyan : Cyber.line),
          ),
          child: Text(label, style: Cyber.label(12.5, color: on ? Cyber.cyan : Cyber.dim, weight: FontWeight.w600)),
        ),
      );

  Widget _errorBox(String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Cyber.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Cyber.red.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded, color: Cyber.red, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Cyber.label(13, color: Cyber.red))),
        ]),
      );

  Widget _qualityCard(SpeedTestResult r) {
    final loaded = math.max(r.loadedDownMs, r.pingMs);
    final rows = <(IconData, String, int, String)>[
      (Icons.live_tv_rounded, 'Video streaming', SpeedMath.streaming(r.downloadMbps, r.pingMs),
          SpeedMath.streamingLabel(SpeedMath.streaming(r.downloadMbps, r.pingMs))),
      (Icons.sports_esports_rounded, 'Online gaming', SpeedMath.gaming(r.pingMs, r.jitterMs, loaded, r.downloadMbps), ''),
      (Icons.video_call_rounded, 'Video calls', SpeedMath.videoCalls(r.downloadMbps, r.uploadMbps, r.pingMs, r.jitterMs), ''),
      (Icons.public_rounded, 'Browsing & social', SpeedMath.browsing(r.downloadMbps, r.pingMs), ''),
    ];
    final grade = SpeedMath.bufferbloatGrade(r.pingMs, r.loadedDownMs, r.loadedUpMs);
    return NeonCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CyberHeading('Network quality'),
        for (final (icon, name, level, extra) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Icon(icon, size: 18, color: Cyber.forLevel(level)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: GoogleFonts.inter(color: Cyber.text, fontSize: 13.5, fontWeight: FontWeight.w600)),
                  if (extra.isNotEmpty) Text(extra, style: Cyber.label(11.5)),
                ]),
              ),
              GradeBadge(SpeedMath.levelLabel(level), Cyber.forLevel(level)),
            ]),
          ),
        const Divider(color: Cyber.line, height: 20),
        Row(children: [
          Icon(Icons.waves_rounded, size: 18, color: Cyber.forGrade(grade)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Bufferbloat', style: GoogleFonts.inter(color: Cyber.text, fontSize: 13.5, fontWeight: FontWeight.w600)),
              Text(
                grade == '—'
                    ? 'Not measured'
                    : 'Latency rises to ${math.max(r.loadedDownMs, r.loadedUpMs).round()} ms when the line is busy '
                        '(${r.pingMs.round()} ms when idle)',
                style: Cyber.label(11.5),
              ),
            ]),
          ),
          GradeBadge(grade, Cyber.forGrade(grade)),
        ]),
      ]),
    );
  }

  Widget _detailsCard(SpeedTestResult r) => NeonCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CyberHeading('Test details', trailing: GestureDetector(
            onTap: () => _copyResult(r),
            child: Row(children: [
              const Icon(Icons.copy_rounded, size: 15, color: Cyber.cyan),
              const SizedBox(width: 4),
              Text('Copy', style: Cyber.label(12, color: Cyber.cyan, weight: FontWeight.w600)),
            ]),
          )),
          InfoRow('Peak download', '${SpeedMath.speedText(r.peakDownMbps)} Mbps', icon: Icons.trending_up_rounded),
          InfoRow('Peak upload', '${SpeedMath.speedText(r.peakUpMbps)} Mbps', icon: Icons.trending_up_rounded),
          InfoRow('Data used', SpeedMath.bytesText(r.bytesUsed), icon: Icons.data_usage_rounded),
          InfoRow('Connections', '${r.connections} parallel', icon: Icons.call_split_rounded),
          if (r.server != null) InfoRow('Server', 'NOVA Speed Server · ${r.server}', icon: Icons.dns_outlined),
          if (_meta?.httpProtocol != null)
            InfoRow('Protocol', [_meta!.httpProtocol!, if (_meta!.tlsVersion != null) _meta!.tlsVersion!].join(' · '),
                icon: Icons.lock_outline_rounded),
          InfoRow('Tested', _dateTime(r.time), icon: Icons.schedule_rounded),
        ]),
      );

  Widget _privacyNote() => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.shield_outlined, size: 15, color: Cyber.dim),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Tests send random data to the nearest NOVA speed server and nothing is stored there. '
            'Results stay on this phone. Location is approximate, from your IP address — no GPS is used.',
            style: Cyber.label(11.5).copyWith(height: 1.5),
          ),
        ),
      ]);

  // ── Device tab ─────────────────────────────────────────────────────────────

  Widget _deviceTab() {
    final d = _device;
    final m = _meta;
    if (d == null) return const Center(child: CircularProgressIndicator(color: Cyber.cyan));
    final battery = d.batteryPercent;
    return RefreshIndicator(
      color: Cyber.cyan,
      backgroundColor: Cyber.panel,
      onRefresh: () async {
        await _loadInfo();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        children: [
          NeonCard(
            child: Row(children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(gradient: AppTheme.primaryGradient, borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.smartphone_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.deviceName.isEmpty ? 'This phone' : d.deviceName,
                      style: GoogleFonts.spaceGrotesk(color: Cyber.text, fontSize: 19, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                    [if (d.model != null) d.model!, if (d.androidVersion != null) 'Android ${d.androidVersion}'].join(' · '),
                    style: Cyber.label(12.5),
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          NeonCard(
            accent: _batteryColor(battery),
            child: Row(children: [
              SizedBox(
                width: 84,
                height: 84,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: (battery ?? 0) / 100,
                      strokeWidth: 7,
                      backgroundColor: const Color(0xFF16233A),
                      valueColor: AlwaysStoppedAnimation(_batteryColor(battery)),
                    ),
                  ),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(battery == null ? '—' : '$battery', style: Cyber.digits(20)),
                    Text('%', style: Cyber.label(10)),
                  ]),
                ]),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(d.charging ? Icons.bolt_rounded : Icons.battery_std_rounded, size: 18, color: _batteryColor(battery)),
                    const SizedBox(width: 6),
                    Text(d.charging ? 'Charging${d.chargeSource != null ? ' · ${d.chargeSource}' : ''}' : 'On battery',
                        style: GoogleFonts.inter(color: Cyber.text, fontSize: 14, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 6),
                  if (d.batteryTempC != null) Text('Temperature ${d.batteryTempC!.toStringAsFixed(1)} °C', style: Cyber.label(12.5)),
                  if (d.batteryHealth != null) Text('Health: ${d.batteryHealth}', style: Cyber.label(12.5)),
                  if (d.powerSave) Text('Battery saver is on', style: Cyber.label(12.5, color: Cyber.amber)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          NeonCard(
            child: Column(children: [
              CyberHeading('Connection', trailing: d.signalLevel == null ? null : SignalBars(level: d.signalLevel!)),
              InfoRow('Type', d.connectionLabel, icon: _transportIcon(d.transport)),
              InfoRow('Internet', d.validated ? 'Working' : (d.connected ? 'Not confirmed (login page?)' : 'Offline'),
                  icon: Icons.verified_outlined, valueColor: d.validated ? Cyber.green : Cyber.amber),
              if (d.wifiBand != null) InfoRow('Wi-Fi band', d.wifiBand!, icon: Icons.wifi_rounded),
              if (d.wifiStandard != null) InfoRow('Wi-Fi standard', d.wifiStandard!, icon: Icons.router_outlined),
              if (d.wifiLinkMbps != null) InfoRow('Link speed', '${d.wifiLinkMbps} Mbps (phone ↔ router)', icon: Icons.link_rounded),
              if (d.carrier != null) InfoRow('Mobile network', d.carrier!, icon: Icons.cell_tower_rounded),
              if (d.signalDbm != null) InfoRow('Signal', '${d.signalDbm} dBm', icon: Icons.network_check_rounded),
              InfoRow('Metered', d.metered ? 'Yes (data may cost money)' : 'No', icon: Icons.data_usage_rounded),
              InfoRow('VPN', d.vpn ? 'On' : 'Off', icon: Icons.vpn_lock_outlined),
            ]),
          ),
          const SizedBox(height: 12),
          NeonCard(
            accent: Cyber.purple,
            child: Column(children: [
              CyberHeading('Internet identity', trailing: m == null ? null : GestureDetector(
                onTap: () => setState(() => _hideIp = !_hideIp),
                child: Icon(_hideIp ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 17, color: Cyber.dim),
              )),
              if (m == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(_metaError ?? 'Loading…', style: Cyber.label(13)),
                )
              else ...[
                InfoRow('Public IP', _hideIp ? _maskIp(m.ip) : m.ip, icon: Icons.language_rounded,
                    trailing: GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: m.ip));
                        _toast('IP address copied');
                      },
                      child: const Icon(Icons.copy_rounded, size: 15, color: Cyber.cyan),
                    )),
                InfoRow('IP version', 'IPv${m.ipVersion}', icon: Icons.numbers_rounded),
                if (m.isp != null) InfoRow('Provider (ISP)', m.isp!, icon: Icons.business_rounded),
                if (m.asn != null) InfoRow('Network (ASN)', 'AS${m.asn}', icon: Icons.hub_outlined),
                InfoRow('Location', [m.place, if (m.region != null && m.region != m.city) m.region!].join(' · '),
                    icon: Icons.location_on_outlined),
                if (m.timezone != null) InfoRow('Time zone', m.timezone!, icon: Icons.public_rounded),
                InfoRow('Nearest server', 'NOVA Speed Server · ${m.serverName}', icon: Icons.dns_outlined),
                if (m.rttMs != null) InfoRow('Round trip', '${m.rttMs!.round()} ms', icon: Icons.timer_outlined),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          NeonCard(
            child: Column(children: [
              const CyberHeading('Local network'),
              InfoRow('Local IP', d.localIps.isEmpty ? '—' : d.localIps.join('\n'), icon: Icons.lan_outlined),
              InfoRow('DNS servers', d.dnsServers.isEmpty ? '—' : d.dnsServers.take(3).join('\n'), icon: Icons.dns_rounded),
              InfoRow('Private DNS', d.privateDns ? (d.privateDnsServer ?? 'On (automatic)') : 'Off', icon: Icons.security_rounded),
              InfoRow('IPv6', d.hasIpv6 ? 'Available' : 'Not available', icon: Icons.numbers_rounded),
              if (d.mtu != null) InfoRow('MTU', '${d.mtu} bytes', icon: Icons.straighten_rounded),
              if (d.downKbpsEstimate != null && d.downKbpsEstimate! > 0)
                InfoRow('Android estimate', '↓ ${(d.downKbpsEstimate! / 1000).round()} · ↑ ${((d.upKbpsEstimate ?? 0) / 1000).round()} Mbps',
                    icon: Icons.insights_rounded),
            ]),
          ),
          const SizedBox(height: 12),
          NeonCard(
            accent: Cyber.purple,
            child: Column(children: [
              const CyberHeading('System'),
              if (d.ramTotalMb != null)
                _usageRow('Memory (RAM)', d.ramTotalMb! - (d.ramFreeMb ?? 0), d.ramTotalMb!, Icons.memory_rounded),
              if (d.storageTotalMb != null)
                _usageRow('Storage', d.storageTotalMb! - (d.storageFreeMb ?? 0), d.storageTotalMb!, Icons.sd_storage_outlined),
              if (d.cpuCores != null)
                InfoRow('Processor', '${d.cpuCores} cores${d.cpuAbi != null ? ' · ${d.cpuAbi}' : ''}', icon: Icons.developer_board_rounded),
              if (d.screen != null)
                InfoRow('Screen', '${d.screen}${d.refreshRate != null ? ' · ${d.refreshRate} Hz' : ''}', icon: Icons.fit_screen_rounded),
            ]),
          ),
          const SizedBox(height: 14),
          _privacyNote(),
        ],
      ),
    );
  }

  Widget _usageRow(String label, int used, int total, IconData icon) {
    final f = total <= 0 ? 0.0 : (used / total).clamp(0.0, 1.0);
    String gb(int mb) => mb >= 1024 ? '${(mb / 1024).toStringAsFixed(1)} GB' : '$mb MB';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: Cyber.cyan.withValues(alpha: 0.8)),
          const SizedBox(width: 10),
          Text(label, style: Cyber.label(13)),
          const Spacer(),
          Text('${gb(used)} / ${gb(total)}', style: GoogleFonts.inter(color: Cyber.text, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: f,
            minHeight: 5,
            backgroundColor: const Color(0xFF16233A),
            valueColor: AlwaysStoppedAnimation(f > 0.9 ? Cyber.red : (f > 0.75 ? Cyber.amber : Cyber.cyan)),
          ),
        ),
      ]),
    );
  }

  static Color _batteryColor(int? level) {
    if (level == null) return Cyber.dim;
    if (level <= 15) return Cyber.red;
    if (level <= 35) return Cyber.amber;
    return Cyber.green;
  }

  static IconData _transportIcon(String t) => switch (t) {
        'wifi' => Icons.wifi_rounded,
        'cellular' => Icons.signal_cellular_alt_rounded,
        'ethernet' => Icons.settings_ethernet_rounded,
        'vpn' => Icons.vpn_key_outlined,
        'none' => Icons.wifi_off_rounded,
        _ => Icons.public_rounded,
      };

  // ── Tools tab ──────────────────────────────────────────────────────────────

  Widget _toolsTab() {
    final stats = NetworkTools.summarize(_latency);
    final latencyRunning = _latencySub != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        NeonCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CyberHeading('Latency monitor', trailing: _toolButton(latencyRunning ? 'Stop' : 'Start 30 s', _toggleLatency, active: latencyRunning)),
            Text('Pings the nearest server every second to spot lag spikes and drop-outs.', style: Cyber.label(12)),
            const SizedBox(height: 12),
            LiveChart(down: [for (final s in _latency) s.ms ?? 0.0], up: const [], height: 64),
            const SizedBox(height: 10),
            Row(children: [
              _miniStat('AVG', _latency.isEmpty ? '—' : '${stats.avg.round()}'),
              _miniStat('MIN', _latency.isEmpty ? '—' : '${stats.min.round()}'),
              _miniStat('MAX', _latency.isEmpty ? '—' : '${stats.max.round()}'),
              _miniStat('JITTER', _latency.isEmpty ? '—' : '${stats.jitter.round()}'),
              _miniStat('LOSS', _latency.isEmpty ? '—' : '${stats.loss.round()}%'),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        NeonCard(
          accent: Cyber.purple,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CyberHeading('DNS lookup speed', trailing: _toolButton(_dnsRunning ? 'Running…' : 'Run', _dnsRunning ? null : _runDns)),
            Text('How fast your phone finds websites by name (cached names are quicker).', style: Cyber.label(12)),
            const SizedBox(height: 6),
            for (final c in _dns)
              _resultRow(c.host, c.ms == null ? (c.error ?? 'Failed') : '${c.ms!.toStringAsFixed(c.ms! < 10 ? 1 : 0)} ms',
                  c.ms == null ? Cyber.red : _msColor(c.ms!, good: 30, ok: 100)),
          ]),
        ),
        const SizedBox(height: 12),
        NeonCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CyberHeading('Service check', trailing: _toolButton(_sitesRunning ? 'Running…' : 'Run', _sitesRunning ? null : _runSites)),
            Text('Can you reach popular services, and how fast do they answer?', style: Cyber.label(12)),
            const SizedBox(height: 6),
            for (final c in _sites)
              _resultRow(c.name, c.reachable ? '${c.ms!.round()} ms' : (c.error ?? 'Unreachable'),
                  c.reachable ? _msColor(c.ms!, good: 250, ok: 700) : Cyber.red),
          ]),
        ),
      ],
    );
  }

  static Color _msColor(double ms, {required double good, required double ok}) =>
      ms <= good ? Cyber.green : (ms <= ok ? Cyber.amber : Cyber.red);

  Widget _toolButton(String label, VoidCallback? onTap, {bool active = false}) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            gradient: onTap == null || active ? null : AppTheme.primaryGradient,
            color: active ? Cyber.red.withValues(alpha: 0.15) : (onTap == null ? Cyber.panel : null),
            borderRadius: BorderRadius.circular(20),
            border: active ? Border.all(color: Cyber.red.withValues(alpha: 0.5)) : null,
          ),
          child: Text(label,
              style: GoogleFonts.spaceGrotesk(
                  color: active ? Cyber.red : (onTap == null ? Cyber.dim : Colors.white),
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ),
      );

  Widget _miniStat(String label, String value) => Expanded(
        child: Column(children: [
          Text(value, style: Cyber.digits(14)),
          const SizedBox(height: 2),
          Text(label, style: Cyber.label(9.5, weight: FontWeight.w700).copyWith(letterSpacing: 1)),
        ]),
      );

  Widget _resultRow(String name, String value, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)])),
          const SizedBox(width: 10),
          Expanded(child: Text(name, style: GoogleFonts.inter(color: Cyber.text, fontSize: 13.5))),
          Text(value, style: Cyber.digits(12.5, color: color)),
        ]),
      );

  // ── History tab ────────────────────────────────────────────────────────────

  Widget _historyTab() {
    final h = _history;
    if (h.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.history_rounded, size: 46, color: Cyber.dim),
            const SizedBox(height: 12),
            Text('No tests yet', style: GoogleFonts.spaceGrotesk(color: Cyber.text, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Run a speed test, or ask “Hey NOVA, what\'s my internet speed?”',
                textAlign: TextAlign.center, style: Cyber.label(13)),
          ]),
        ),
      );
    }
    double avg(double Function(SpeedTestResult) f) => h.map(f).fold<double>(0, (a, b) => a + b) / h.length;
    final best = h.map((r) => r.downloadMbps).reduce(math.max);
    final recent = h.take(20).toList().reversed.map((r) => r.downloadMbps).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        NeonCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CyberHeading('${h.length} test${h.length == 1 ? '' : 's'}', trailing: GestureDetector(
              onTap: _confirmClear,
              child: Text('Clear', style: Cyber.label(12, color: Cyber.red, weight: FontWeight.w600)),
            )),
            Row(children: [
              _miniStat('AVG ↓', SpeedMath.shortSpeed(avg((r) => r.downloadMbps))),
              _miniStat('AVG ↑', SpeedMath.shortSpeed(avg((r) => r.uploadMbps))),
              _miniStat('AVG PING', '${avg((r) => r.pingMs).round()}'),
              _miniStat('BEST ↓', SpeedMath.shortSpeed(best)),
            ]),
            const SizedBox(height: 14),
            HistoryBars(values: recent),
            const SizedBox(height: 4),
            Text('Download, last ${recent.length} tests (Mbps)', style: Cyber.label(11)),
          ]),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < h.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Dismissible(
              key: ValueKey('${h[i].time.millisecondsSinceEpoch}_$i'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(color: Cyber.red.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(18)),
                child: const Icon(Icons.delete_outline_rounded, color: Cyber.red),
              ),
              onDismissed: (_) async {
                final next = await SpeedHistory.removeAt(i);
                if (mounted) setState(() => _history = next);
              },
              child: GestureDetector(
                onLongPress: () => _copyResult(h[i]),
                child: _historyItem(h[i]),
              ),
            ),
          ),
        Text('Swipe left to delete · long-press to copy', textAlign: TextAlign.center, style: Cyber.label(11)),
      ],
    );
  }

  Widget _historyItem(SpeedTestResult r) => NeonCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(r.connection == 'Mobile data' ? Icons.signal_cellular_alt_rounded : Icons.wifi_rounded, size: 15, color: Cyber.dim),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                [_dateTime(r.time), if (r.connection.isNotEmpty) r.connection, if (r.isp != null) r.isp!].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Cyber.label(11.5),
              ),
            ),
            if (r.mode != 'full') GradeBadge(r.mode == 'quick' ? 'NOVA' : 'Light', Cyber.purple),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _historyValue(Icons.arrow_circle_down_rounded, Cyber.cyan, SpeedMath.speedText(r.downloadMbps), 'Mbps'),
            _historyValue(Icons.arrow_circle_up_rounded, Cyber.purple, SpeedMath.speedText(r.uploadMbps), 'Mbps'),
            _historyValue(Icons.bolt_rounded, Cyber.amber, '${r.pingMs.round()}', 'ms'),
          ]),
        ]),
      );

  Widget _historyValue(IconData icon, Color c, String v, String unit) => Expanded(
        child: Row(children: [
          Icon(icon, size: 15, color: c),
          const SizedBox(width: 5),
          Flexible(child: Text(v, overflow: TextOverflow.ellipsis, style: Cyber.digits(15))),
          const SizedBox(width: 3),
          Text(unit, style: Cyber.label(10.5)),
        ]),
      );

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Cyber.panel,
        title: Text('Clear history?', style: GoogleFonts.spaceGrotesk(color: Cyber.text, fontWeight: FontWeight.w700)),
        content: Text('All saved speed tests on this phone will be deleted.', style: Cyber.label(14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear', style: TextStyle(color: Cyber.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await SpeedHistory.clear();
    if (mounted) setState(() => _history = const []);
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String _dateTime(DateTime t) =>
      '${t.day} ${_months[t.month - 1]} ${t.year}, ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
