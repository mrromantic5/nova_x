// lib/features/cyber/screens/cyber_screen.dart
//
// NOVA Cyber (3.13.0) — website and code security scanner, ported from NOVA X
// for PC. The old Android Cyber (which sent attack-style requests to any
// address typed) is gone.
//
//   Website scan   Quick (read-only, any site) or Full (verified owners only:
//                  the NOVA X server checks ownership and signs a 2-hour pass
//                  before every full scan)
//   Verified sites ownership verification (DNS TXT, file, or HTML tag)
//   Monitoring     24/7 checks of verified sites by the NOVA X server (3.14.0)
//   Code scan      a project .zip or picked files, read on the phone
//   History        earlier reports on this phone
//
// 3.14.0 (ported from NOVA X for Windows): CVSS 3.1 scores, attack chains,
// triage (open / confirmed / false positive / accepted risk / fixed) with a
// "reopened" tag, SARIF 2.1.0 and JSON export, code scans saved as reports,
// and the PC-only tools shown with a "Get it on Windows" card.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/rewards_entitlements.dart';
import '../../../core/services/rewards_service.dart';
import '../../../core/widgets/feature_lock.dart';
import '../../../core/widgets/windows_download_card.dart';
import '../../ai/screens/ai_assistant_screen.dart';
import '../../guide/guide_screen.dart';
import '../engine/checks_full.dart';
import '../engine/cyber_api.dart';
import '../engine/cyber_audit.dart';
import '../engine/cyber_storage.dart';
import '../engine/cyber_code_scan.dart';
import '../engine/cyber_engine.dart';
import '../engine/cyber_models.dart';
import '../engine/cyber_pipeline.dart';
import '../engine/zip_reader.dart';
import '../ui/cyber_palette.dart';
import '../ui/cyber_verify.dart';
import '../ui/cyber_widgets.dart';
import 'cyber_audit_screen.dart';

enum _View { scan, sites, monitor, code, history }

class CyberScreen extends StatefulWidget {
  const CyberScreen({super.key, this.initialUrl = '', this.openMonitoring = false});

  /// 3.14.0: open on the Monitoring tab (from a Notifications alert).
  final bool openMonitoring;

  /// Opened from the browser: the site's address is filled in (not scanned
  /// until the user taps Run).
  final String initialUrl;

  @override
  State<CyberScreen> createState() => _CyberScreenState();
}

class _CyberScreenState extends State<CyberScreen> with WidgetsBindingObserver {
  static const _screen = MethodChannel('com.tlyfe.nova_x/default_browser');

  late _View _view = widget.openMonitoring ? _View.monitor : _View.scan;
  final TextEditingController _target = TextEditingController();
  ScanLevel _level = ScanLevel.quick;
  bool _ports = true, _subdomains = true, _loginTest = false;

  bool _running = false;
  String _phase = '';
  double _progress = 0;
  final List<String> _log = [];
  final ScrollController _logScroll = ScrollController();
  ScanReport? _report;
  final List<Finding> _live = [];
  String? _error;
  int? _scansLeft;

  // Findings filter
  Severity? _sev;
  CheckArea? _area;
  String _query = '';

  // Code scan
  String? _codeLabel;
  List<CodeFile>? _codeFiles;
  CodeScanResult? _code;
  ScanReport? _codeReport;
  bool _codeRunning = false;
  String? _codeError;

  // Triage (3.14.0)
  bool _showDismissed = false;

  // 24/7 Monitoring (3.14.0)
  MonitorOverview? _mon;
  bool _monLoading = false;
  String? _monError;
  final Set<String> _monBusy = {};
  String? _addHost;
  int _addInterval = 15;
  List<MonitorEvent> _events = const [];
  int _unread = 0;
  int? _lastEventId;
  Timer? _alertTimer;
  bool _appActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final u = normalizeTarget(widget.initialUrl);
    if (u != null && (u.scheme == 'https' || u.scheme == 'http')) _target.text = u.host;
    CyberTriage.init().then((_) {
      if (mounted) setState(() {});
    });
    CyberStorage.init(); // audit log + rule packs (3.14.0)
    // Monitoring status + unread alerts (only while this screen is open;
    // e-mail alerts reach the user when the app is closed).
    _loadMonitoring(quiet: true);
    _alertTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (_appActive) _pollAlerts();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alertTimer?.cancel();
    _target.dispose();
    _logScroll.dispose();
    if (_running) CyberEngine.instance.stop();
    _keepAwake(false);
    super.dispose();
  }

  // Leaving the app stops the scan cleanly; the partial report is kept.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.paused && _running) {
      _addLog('— NOVA X went to the background: the scan was stopped. Partial results are below.');
      CyberEngine.instance.stop();
    }
  }

  void _keepAwake(bool on) {
    _screen.invokeMethod<bool>('keepScreenOn', on).catchError((_) => false);
  }

  void _addLog(String line) {
    if (!mounted) return;
    setState(() {
      _log.add(line);
      if (_log.length > 1500) _log.removeRange(0, _log.length - 1500);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
    });
  }

  void _snack(String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

  // ── Scan ───────────────────────────────────────────────────────────────────

  Future<void> _scan() async {
    FocusScope.of(context).unfocus();
    final target = normalizeTarget(_target.text);
    if (target == null) {
      setState(() => _error = 'Enter a website address, for example example.com');
      return;
    }
    setState(() {
      _error = null;
      _view = _View.scan;
    });
    ScanPass? pass;
    if (_level == ScanLevel.full) {
      final own = isOwnMachine(target.host);
      final lan = isPrivateNetwork(target.host);
      if (!await _confirmFull(target.host, local: own || lan)) return;
      if (!own && !lan) {
        try {
          setState(() => _phase = 'Checking ownership with the NOVA X server…');
          pass = await CyberApi.authorize(target.host);
          _scansLeft = pass.scansLeft;
        } on CyberApiError catch (e) {
          setState(() => _phase = '');
          if (e.status == 403 && mounted) {
            final verify = await _askVerify(target.host, e.message);
            if (verify && mounted && await showVerifyWizard(context, host: target.host)) {
              return _scan();
            }
          } else {
            setState(() => _error = e.message);
          }
          return;
        } catch (e) {
          setState(() {
            _phase = '';
            _error = 'Couldn\'t reach the NOVA X server. Check your connection and try again.';
          });
          return;
        }
      }
    }
    setState(() {
      _running = true;
      _report = null;
      _log.clear();
      _progress = 0;
      _phase = 'Starting';
      _sev = null;
      _area = null;
      _live.clear();
    });
    _keepAwake(true);
    _addLog('${_level == ScanLevel.full ? 'FULL SCAN (ownership verified)' : 'QUICK SCAN (read-only)'} — ${target.host}');
    final scope = _level != ScanLevel.full
        ? 'read-only'
        : (pass == null ? 'own device / network' : 'verified owner');
    unawaited(CyberAudit.log('scan.start', target.host, scope: scope, detail: _level.name));
    try {
      final r = await CyberEngine.instance.scan(
        target,
        level: _level,
        pass: pass,
        options: FullOptions(ports: _ports, subdomains: _subdomains, loginRateLimit: _loginTest),
        onLog: _addLog,
        onFinding: (f) {
          if (mounted) setState(() => _live.add(f));
        },
        onPhase: (ph, v) {
          if (mounted) {
            setState(() {
              _phase = ph;
              _progress = v;
            });
          }
        },
      );
      unawaited(CyberAudit.log('scan.done', target.host, scope: scope, detail: '${_level.name} score=${r.score} findings=${r.issues.length}'));
      if (mounted) setState(() => _report = r);
    } catch (e) {
      unawaited(CyberAudit.log('scan.failed', target.host, scope: scope, detail: '$e'));
      if (mounted) setState(() => _error = '$e');
    } finally {
      _keepAwake(false);
      if (mounted) setState(() => _running = false);
    }
  }

  Future<bool> _confirmFull(String host, {required bool local}) async {
    var agree = false;
    var ports = _ports, subs = _subdomains, login = _loginTest;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => NovaThemed(
        child: StatefulBuilder(builder: (ctx, set) {
          final p = NovaThemeScope.of(ctx);
          Widget opt(String title, String sub, bool v, void Function(bool) on) => CheckboxListTile(
                value: v,
                onChanged: (x) => set(() => on(x ?? false)),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(title, style: p.ui(size: 13.5, weight: FontWeight.w600)),
                subtitle: Text(sub, style: p.ui(size: 12, color: p.textMuted)),
              );
          return AlertDialog(
            backgroundColor: p.surface,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            title: Text('Full scan of $host', style: p.title(size: 17)),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(
                  'The full scan sends active tests — sensitive-file checks, injection tests with harmless markers, configuration tests. '
                  'Requests are rate-limited and the scan stops by itself if your firewall pushes back. Nothing is changed or deleted.',
                  style: p.ui(size: 13, color: p.textMuted, height: 1.45),
                ),
                const SizedBox(height: 12),
                opt('Network service ports', 'Connect-only check for exposed databases, RDP, Redis, Docker…', ports, (v) => ports = v),
                opt('Subdomains from certificate logs', 'Find forgotten subdomains and dangling DNS (takeover risk).', subs, (v) => subs = v),
                opt('Login rate limiting', 'Sends 6 failed sign-ins with a made-up account to see whether attempts are limited.', login, (v) => login = v),
                const Divider(height: 22),
                CheckboxListTile(
                  value: agree,
                  onChanged: (x) => set(() => agree = x ?? false),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(local ? 'This is my own device / network' : 'I own $host or have written permission to test it',
                      style: p.ui(size: 13.5, weight: FontWeight.w700)),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: agree ? () => Navigator.pop(ctx, true) : null, child: const Text('Start full scan')),
            ],
          );
        }),
      ),
    );
    if (ok == true) {
      _ports = ports;
      _subdomains = subs;
      _loginTest = login;
    }
    return ok == true;
  }

  Future<bool> _askVerify(String host, String message) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => NovaThemed(
        child: Builder(builder: (ctx) {
          final p = NovaThemeScope.of(ctx);
          return AlertDialog(
            backgroundColor: p.surface,
            title: Text('Verify $host first', style: p.title(size: 17)),
            content: Text('$message\n\nThe quick scan works without verification.', style: p.ui(size: 13.5, color: p.textMuted, height: 1.45)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Verify ownership')),
            ],
          );
        }),
      ),
    );
    return r == true;
  }

  void _askAi(Finding f) {
    final prompt = StringBuffer()
      ..writeln('You are a senior application-security engineer. Help me fix this issue in my own website.')
      ..writeln()
      ..writeln('Issue: ${f.title} (${f.severity.label})')
      ..writeln('Area: ${f.area.label}')
      ..writeln('Where: ${f.location}')
      ..writeln('Evidence:\n${f.evidence}')
      ..writeln()
      ..writeln('My stack: ${_report?.tech.stack.join(', ') ?? 'unknown'}')
      ..writeln('Explain the risk briefly, give the exact secure code/config change, and how to test it. '
          'I will paste the relevant code below.');
    Navigator.push(context, MaterialPageRoute(builder: (_) => AiAssistantScreen(initialText: prompt.toString().trim())));
  }

  Future<void> _export(String kind) async {
    final r = _report;
    if (r == null) return;
    final name = r.displayName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final stamp = r.started.toIso8601String().substring(0, 10);
    final ext = switch (kind) { 'html' => 'html', 'sarif' => 'sarif', 'json' => 'json', _ => 'md' };
    final text = switch (kind) {
      'html' => CyberReportWriter.html(r),
      'sarif' => toSarif(r),
      'json' => const JsonEncoder.withIndent('  ').convert(r.toJson()),
      _ => CyberReportWriter.markdown(r),
    };
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save security report',
        fileName: 'nova-cyber-$name-$stamp.$ext',
        bytes: Uint8List.fromList(utf8.encode(text)),
      );
      if (path == null) return;
      unawaited(CyberAudit.log('export', r.displayName, detail: kind));
      _snack('Report saved');
    } catch (e) {
      _snack('Couldn\'t save the report: $e');
    }
  }

  // ── Code scan (Android: a .zip or picked files, read in memory) ───────────

  static const int _maxZipBytes = 60 * 1024 * 1024;

  Future<void> _pickZip() async {
    setState(() => _codeError = null);
    try {
      final res = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choose a project .zip',
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        withData: true,
      );
      final f = res?.files.single;
      if (f == null) return;
      final bytes = f.bytes;
      if (bytes == null) throw ZipReadException('Couldn\'t read the file.');
      if (bytes.length > _maxZipBytes) {
        throw ZipReadException('This .zip is over 60 MB. Zip only your source code (without node_modules, vendor or build folders).');
      }
      final files = ZipReader.read(bytes);
      if (files.isEmpty) throw ZipReadException('No readable files were found in this .zip.');
      setState(() {
        _codeFiles = files;
        _codeLabel = '${f.name} · ${files.length} files';
        _code = null;
      });
    } catch (e) {
      setState(() => _codeError = '$e');
    }
  }

  Future<void> _pickFiles() async {
    setState(() => _codeError = null);
    try {
      final res = await FilePicker.platform.pickFiles(dialogTitle: 'Choose project files', allowMultiple: true, withData: true);
      if (res == null || res.files.isEmpty) return;
      final files = <CodeFile>[
        for (final f in res.files)
          if (f.bytes != null && f.bytes!.length <= ZipReader.maxEntryBytes) CodeFile(f.name, f.bytes!),
      ];
      if (files.isEmpty) throw ZipReadException('Those files couldn\'t be read (files over 1 MB are skipped).');
      setState(() {
        _codeFiles = files;
        _codeLabel = files.length == 1 ? files.first.path : '${files.length} files';
        _code = null;
      });
    } catch (e) {
      setState(() => _codeError = '$e');
    }
  }

  Future<void> _runCode() async {
    final files = _codeFiles;
    if (files == null) return;
    setState(() {
      _codeRunning = true;
      _codeError = null;
      _log.clear();
    });
    _keepAwake(true);
    try {
      final started = DateTime.now();
      final label = _codeLabel ?? 'project';
      final res = await CodeScanner.scanFiles(files, label: label, onLog: _addLog);
      // 3.14.0: CVSS + dedupe + chains, and a history report so triage and
      // export work on code scans too.
      final processed = CyberPipeline.process(res.findings, level: ScanLevel.code);
      res.findings
        ..clear()
        ..addAll(processed);
      final name = label.split(' · ').first;
      final rep = ScanReport(target: 'code://${name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_').toLowerCase()}', level: ScanLevel.code, started: started)
        ..finished = DateTime.now();
      rep.facts.addAll({
        'Project': name,
        'Files read': '${res.files}',
        'Dependencies': '${res.packages}',
        if (res.manifests.isNotEmpty) 'Manifests': res.manifests.take(6).join(', '),
      });
      rep.findings.addAll(processed);
      await CyberHistory.add(rep);
      unawaited(CyberAudit.log('scan.done', name, scope: 'local project files', detail: 'code score=${rep.score} findings=${rep.issues.length}'));
      _code = res;
      _codeReport = rep;
    } catch (e) {
      _addLog('Error: $e');
      _codeError = 'The code scan stopped: $e';
    }
    _keepAwake(false);
    if (mounted) setState(() => _codeRunning = false);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!RewardsEntitlements.isUnlocked(RewardFeature.cyber)) {
      return FeatureLockScreen(
        featureKey: RewardFeature.cyber,
        onUnlocked: () => setState(() {}),
      );
    }
    return NovaThemed(
      child: Builder(builder: (context) {
        final p = NovaThemeScope.of(context);
        return Scaffold(
          backgroundColor: p.bg,
          appBar: AppBar(
            backgroundColor: p.bg,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            titleSpacing: 0,
            title: Row(children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: p.text, borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.shield_rounded, size: 17, color: p.surface),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('NOVA Cyber', style: p.ui(size: 16, weight: FontWeight.w800)),
                Text('Website & code security', style: p.ui(size: 11, color: p.textFaint)),
              ]),
            ]),
            actions: [
              const Center(child: ReadMoreLink('cyber', compact: true)),
              PopupMenuButton<int>(
                tooltip: 'More',
                color: p.surface,
                icon: Icon(Icons.more_vert_rounded, color: p.textMuted),
                onSelected: (i) => i < 0
                    ? Navigator.push(context, MaterialPageRoute(builder: (_) => const CyberAuditScreen()))
                    : WindowsOnly.show(context, title: _pcTools[i].$1, reason: _pcTools[i].$2),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: -1,
                    child: Row(children: [
                      Icon(Icons.fact_check_outlined, size: 18, color: p.textMuted),
                      const SizedBox(width: 10),
                      Text('Audit & rules', style: p.ui(size: 13.5)),
                    ]),
                  ),
                  const PopupMenuDivider(),
                  for (var i = 0; i < _pcTools.length; i++)
                    PopupMenuItem(
                      value: i,
                      child: Row(children: [
                        Expanded(child: Text(_pcTools[i].$1, style: p.ui(size: 13.5))),
                        const SizedBox(width: 10),
                        const WindowsBadge(),
                      ]),
                    ),
                ],
              ),
            ],
          ),
          body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_view == _View.scan && (_running || _report == null || _report!.level.isWeb)) _scanBar(p),
            Expanded(child: _content(p)),
          ]),
          bottomNavigationBar: NavigationBar(
            backgroundColor: p.surface,
            indicatorColor: p.accentSoft,
            selectedIndex: _view.index,
            height: 64,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (i) {
              setState(() {
                _view = _View.values[i];
                // Back to an empty website scan after viewing a code report.
                if (_view == _View.scan && _report != null && !_report!.level.isWeb && !_running) _report = null;
              });
              if (_view == _View.monitor && !_monLoading) _loadMonitoring();
            },
            destinations: [
              NavigationDestination(icon: Icon(Icons.radar_rounded, color: p.textMuted), selectedIcon: Icon(Icons.radar_rounded, color: p.accent), label: 'Website'),
              NavigationDestination(icon: Icon(Icons.verified_user_outlined, color: p.textMuted), selectedIcon: Icon(Icons.verified_user_rounded, color: p.accent), label: 'Verified'),
              NavigationDestination(
                icon: Badge(isLabelVisible: _unread > 0, label: Text('$_unread'), child: Icon(Icons.monitor_heart_outlined, color: p.textMuted)),
                selectedIcon: Badge(isLabelVisible: _unread > 0, label: Text('$_unread'), child: Icon(Icons.monitor_heart_rounded, color: p.accent)),
                label: 'Monitor',
              ),
              NavigationDestination(icon: Icon(Icons.data_object_rounded, color: p.textMuted), selectedIcon: Icon(Icons.data_object_rounded, color: p.accent), label: 'Code'),
              NavigationDestination(icon: Icon(Icons.history_rounded, color: p.textMuted), selectedIcon: Icon(Icons.history_rounded, color: p.accent), label: 'History'),
            ],
          ),
        );
      }),
    );
  }

  Widget _scanBar(NovaPalette p) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      decoration: BoxDecoration(color: p.bg, border: Border(bottom: BorderSide(color: p.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _target,
          enabled: !_running,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          autocorrect: false,
          onSubmitted: (_) => _scan(),
          style: p.ui(size: 14.5),
          decoration: InputDecoration(
            hintText: 'Website to scan — e.g. example.com',
            hintStyle: p.ui(size: 14.5, color: p.textFaint),
            prefixIcon: Icon(Icons.language_rounded, color: p.textFaint, size: 20),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 13),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: SegmentedButton<ScanLevel>(
              segments: const [
                ButtonSegment(value: ScanLevel.quick, label: Text('Quick'), icon: Icon(Icons.visibility_outlined, size: 16)),
                ButtonSegment(value: ScanLevel.full, label: Text('Full'), icon: Icon(Icons.verified_user_outlined, size: 16)),
              ],
              selected: {_level},
              onSelectionChanged: _running ? null : (s) => setState(() => _level = s.first),
              showSelectedIcon: false,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 44,
            child: _running
                ? OutlinedButton.icon(
                    onPressed: () => CyberEngine.instance.stop(),
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Stop'),
                  )
                : FilledButton.icon(
                    onPressed: _scan,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Run'),
                  ),
          ),
        ]),
      ]),
    );
  }

  Widget _content(NovaPalette p) {
    switch (_view) {
      case _View.sites:
        return VerifiedSitesView(onScan: (h) {
          setState(() {
            _target.text = h;
            _level = ScanLevel.full;
            _view = _View.scan;
          });
          _scan();
        });
      case _View.monitor:
        return _monitorView(p);
      case _View.code:
        return _codeView(p);
      case _View.history:
        return _historyView(p);
      case _View.scan:
        if (_running) return _runningView(p);
        if (_report != null) return _reportView(p, _report!);
        return _emptyView(p);
    }
  }

  // ── Views ──────────────────────────────────────────────────────────────────

  Widget _emptyView(NovaPalette p) {
    Widget card(IconData icon, String title, String body, List<String> items) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, color: p.accent),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: p.ui(size: 15, weight: FontWeight.w700))),
              ]),
              const SizedBox(height: 6),
              Text(body, style: p.ui(size: 13, color: p.textMuted, height: 1.45)),
              const SizedBox(height: 12),
              for (final i in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.check_rounded, size: 15, color: p.success),
                    const SizedBox(width: 8),
                    Expanded(child: Text(i, style: p.ui(size: 12.5, color: p.text))),
                  ]),
                ),
            ]),
          ),
        );
    return ListView(padding: const EdgeInsets.fromLTRB(16, 18, 16, 32), children: [
      if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: _errorBox(p, _error!)),
      if (_phase.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_phase, style: p.ui(size: 13, color: p.textMuted))),
      if (_mon != null && _mon!.monitors.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 16), child: _statusCard(p, _mon!)),
      Text('Find what attackers would find — before they do.', style: p.title(size: 20)),
      const SizedBox(height: 6),
      Text('Enter a site above. Every finding comes with evidence, the risk in plain words, and the exact fix for your server.',
          style: p.ui(size: 13.5, color: p.textMuted, height: 1.4)),
      const SizedBox(height: 18),
      card(Icons.visibility_outlined, 'Quick scan — any site', 'Read-only. Looks only at what a normal visit and public DNS reveal.', const [
        'TLS certificate, HTTPS redirect, HSTS',
        'Security headers with CSP quality analysis',
        'Cookie flags, mixed content, insecure forms',
        'Exposed API keys in page source',
        'JavaScript libraries with known CVEs (OSV.dev)',
        'SPF, DMARC, CAA, DNSSEC, subdomain takeover',
      ]),
      card(Icons.verified_user_outlined, 'Full scan — verified owners', 'Active tests with harmless markers, rate-limited, only after the server confirms you own the site.', const [
        '45+ sensitive files: .env, .git, backups, dumps, logs, debug tools',
        'XSS, SQL injection, template injection, path traversal',
        'Open redirects, CORS, Host header, TRACE, HTTP methods',
        'Exposed databases, Redis, Docker API, RDP (ports)',
        'GraphQL introspection, API docs, source maps',
        'WordPress users, XML-RPC, plugins; login rate limits',
      ]),
      card(Icons.data_object_rounded, 'Code scan — your project', 'Reads a project .zip or files on this phone. Only package names and versions leave it.', const [
        'Hard-coded keys, tokens, private keys, DB URLs',
        'SQL / command injection, eval, unsafe deserialization',
        'Disabled TLS checks, weak password hashing, JWT none',
        'Vulnerable npm / Composer / PyPI / Pub packages',
      ]),
      const SizedBox(height: 4),
      Text('Full scans run only on sites you verify. Reports stay on this phone.', style: p.ui(size: 11.5, color: p.textFaint, height: 1.4)),
      const SizedBox(height: 18),
      Text('MORE ON WINDOWS', style: p.ui(size: 10.5, weight: FontWeight.w700, color: p.textFaint, letterSpacing: 0.9)),
      const SizedBox(height: 8),
      for (final t in _pcTools)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: p.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => WindowsOnly.show(context, title: t.$1, reason: t.$2),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  Icon(t.$3, color: p.textMuted, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text(t.$1, style: p.ui(size: 13.5, weight: FontWeight.w600))),
                  const WindowsBadge(),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _counts(NovaPalette p, int Function(Severity) n, int passed) => Wrap(spacing: 22, runSpacing: 12, children: [
        for (final s in Severity.values.where((s) => s != Severity.info)) Metric(value: '${n(s)}', label: s.label, color: n(s) == 0 ? p.textFaint : sevColor(s, p)),
        Metric(value: '$passed', label: 'Passed', color: p.success),
      ]);

  Widget _runningView(NovaPalette p) {
    int n(Severity s) => _live.where((f) => !f.passed && f.severity == s).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: p.accent)),
          const SizedBox(width: 12),
          Expanded(child: Text(_phase, maxLines: 2, overflow: TextOverflow.ellipsis, style: p.ui(size: 14.5, weight: FontWeight.w700))),
          const SizedBox(width: 8),
          Text('${(_progress * 100).round()}%', style: p.ui(size: 13, color: p.textMuted, weight: FontWeight.w600)),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: _progress == 0 ? null : _progress, minHeight: 6, backgroundColor: p.border, color: p.accent),
        ),
        const SizedBox(height: 16),
        _counts(p, n, _live.where((f) => f.passed).length),
        const SizedBox(height: 16),
        Expanded(child: _console(p)),
        const SizedBox(height: 8),
        Text('Keep NOVA X open — leaving the app stops the scan.', textAlign: TextAlign.center, style: p.ui(size: 11.5, color: p.textFaint)),
      ]),
    );
  }

  Widget _console(NovaPalette p) {
    const bg = Color(0xFF0B0F14);
    return Container(
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF1F2933)))),
          child: Row(children: [
            const Text('ACTIVITY', style: TextStyle(color: Color(0xFF7D8590), fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1)),
            const Spacer(),
            Text('${_log.length} lines', style: const TextStyle(color: Color(0xFF7D8590), fontSize: 11)),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            controller: _logScroll,
            padding: const EdgeInsets.all(12),
            itemCount: _log.length,
            itemBuilder: (_, i) {
              final l = _log[i];
              final color = l.startsWith('—')
                  ? const Color(0xFF79C0FF)
                  : l.contains('→  2')
                      ? const Color(0xFF7EE787)
                      : l.contains('→  4') || l.contains('→  5') || l.contains('error')
                          ? const Color(0xFFFFA657)
                          : const Color(0xFFC9D1D9);
              return Text(l, style: kMono.copyWith(color: color, fontSize: 11.5));
            },
          ),
        ),
      ]),
    );
  }

  Widget _errorBox(NovaPalette p, String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.danger.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(10), border: Border.all(color: p.danger.withValues(alpha: 0.35))),
        child: Row(children: [
          Icon(Icons.error_outline_rounded, color: p.danger, size: 18),
          const SizedBox(width: 10),
          Expanded(child: SelectableText(text, style: p.ui(size: 13, color: p.text))),
        ]),
      );

  Widget _reportView(NovaPalette p, ScanReport r) {
    bool dismissed(Finding f) {
      final t = CyberTriage.get(r, f)?.status;
      return t == TriageStatus.falsePositive || t == TriageStatus.acceptedRisk;
    }

    final chains = r.issues.where((f) => f.area == CheckArea.chain).toList();
    final dismissedCount = r.issues.where(dismissed).length;
    final issues = r.issues.where((f) {
      if (f.area == CheckArea.chain) return false;
      if (!_showDismissed && dismissed(f)) return false;
      if (_sev != null && f.severity != _sev) return false;
      if (_area != null && f.area != _area) return false;
      if (_query.isNotEmpty && !('${f.title} ${f.evidence} ${f.location}'.toLowerCase().contains(_query.toLowerCase()))) return false;
      return true;
    }).toList();
    final lost = r.lostByArea.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final host = r.displayName;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), children: [
      if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 14), child: _errorBox(p, _error!)),
      // Summary
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ScoreRing(score: r.score, grade: r.grade, size: 104),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(host, style: p.title(size: 18), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Tag(
                    switch (r.level) {
                      ScanLevel.full => 'Full scan · verified',
                      ScanLevel.quick => 'Quick scan · read-only',
                      ScanLevel.code => 'Code scan',
                      _ => r.level.label,
                    },
                    icon: switch (r.level) {
                      ScanLevel.full || ScanLevel.apk => Icons.verified_user_rounded,
                      ScanLevel.quick => Icons.visibility_outlined,
                      ScanLevel.code => Icons.data_object_rounded,
                      ScanLevel.binary => Icons.memory_rounded,
                    },
                    color: r.level == ScanLevel.full ? p.success : p.textMuted),
                const SizedBox(height: 6),
                Text(
                  '${r.started.toLocal().toString().substring(0, 16)}  ·  ${r.requests} requests'
                  '${r.finished == null ? '' : '  ·  ${r.finished!.difference(r.started).inSeconds}s'}'
                  '${r.tech.stack.isEmpty ? '' : '\n${r.tech.stack.join(', ')}'}',
                  style: p.ui(size: 12, color: p.textFaint, height: 1.4),
                ),
              ]),
            ),
          ]),
          if (r.stoppedEarly) ...[
            const SizedBox(height: 10),
            Text('Stopped early: ${r.stopReason}', style: p.ui(size: 12.5, color: p.warning, weight: FontWeight.w600)),
          ],
          if (r.facts.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 16, runSpacing: 4, children: [
              for (final e in r.facts.entries)
                Text.rich(TextSpan(children: [
                  TextSpan(text: '${e.key}  ', style: p.ui(size: 12, color: p.textFaint)),
                  TextSpan(text: e.value, style: p.ui(size: 12, color: p.text, weight: FontWeight.w600)),
                ])),
            ]),
          ],
          const SizedBox(height: 16),
          _counts(p, r.count, r.passes.length),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: () => _export('html'), icon: const Icon(Icons.description_outlined, size: 16), label: const Text('Export report')),
            OutlinedButton.icon(onPressed: () => _export('md'), icon: const Icon(Icons.notes_rounded, size: 16), label: const Text('Markdown')),
            OutlinedButton.icon(onPressed: () => _export('sarif'), icon: const Icon(Icons.integration_instructions_outlined, size: 16), label: const Text('SARIF')),
            OutlinedButton.icon(onPressed: () => _export('json'), icon: const Icon(Icons.data_object_rounded, size: 16), label: const Text('JSON')),
            if (r.level.isWeb)
              OutlinedButton.icon(onPressed: _running ? null : _scan, icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('Scan again')),
            if (r.level == ScanLevel.quick)
              FilledButton.tonalIcon(
                onPressed: () {
                  setState(() => _level = ScanLevel.full);
                  _scan();
                },
                icon: const Icon(Icons.verified_user_outlined, size: 16),
                label: const Text('Run full scan'),
              ),
          ]),
          if (_scansLeft != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('$_scansLeft full scans left today', style: p.ui(size: 11.5, color: p.textFaint))),
          if (lost.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('WHERE POINTS WERE LOST', style: p.ui(size: 10.5, weight: FontWeight.w700, color: p.textFaint, letterSpacing: 0.9)),
            const SizedBox(height: 10),
            for (final e in lost.take(7))
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: InkWell(
                  onTap: () => setState(() => _area = _area == e.key ? null : e.key),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(child: Text(e.key.label, style: p.ui(size: 12.5, weight: _area == e.key ? FontWeight.w700 : FontWeight.w500))),
                      Text('−${e.value}', style: p.ui(size: 12, color: p.textMuted, weight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(value: (e.value / 60).clamp(0.04, 1.0), minHeight: 5, backgroundColor: p.border, color: p.text.withValues(alpha: 0.75)),
                    ),
                  ]),
                ),
              ),
          ],
        ]),
      ),
      if (chains.isNotEmpty) ...[
        const SizedBox(height: 18),
        Panel(
          title: 'Attack chains  ${chains.length}',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Findings that combine into a bigger risk', style: p.ui(size: 12, color: p.textFaint)),
            const SizedBox(height: 8),
            for (final c in chains) _triaged(p, r, c, FindingCard(key: ValueKey('chain-${c.id}'), f: c, tech: r.tech, onAskAi: _askAi)),
          ]),
        ),
      ],
      const SizedBox(height: 18),
      // Filters
      Row(children: [
        Text('Findings', style: p.ui(size: 15, weight: FontWeight.w700)),
        const SizedBox(width: 6),
        Text('${issues.length}', style: p.ui(size: 15, color: p.textFaint, weight: FontWeight.w700)),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final s in Severity.values.where((s) => s != Severity.info && r.count(s) > 0))
          FilterChip(
            label: Text('${s.label} ${r.count(s)}', style: p.ui(size: 12, weight: FontWeight.w600)),
            selected: _sev == s,
            onSelected: (v) => setState(() => _sev = v ? s : null),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            selectedColor: sevColor(s, p).withValues(alpha: 0.14),
            side: BorderSide(color: _sev == s ? sevColor(s, p) : p.border),
          ),
        if (_area != null)
          InputChip(label: Text(_area!.label, style: p.ui(size: 12)), onDeleted: () => setState(() => _area = null), visualDensity: VisualDensity.compact),
        if (dismissedCount > 0)
          FilterChip(
            label: Text('Show dismissed $dismissedCount', style: p.ui(size: 12, weight: FontWeight.w600)),
            selected: _showDismissed,
            onSelected: (v) => setState(() => _showDismissed = v),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
          ),
      ]),
      const SizedBox(height: 8),
      TextField(
        onChanged: (v) => setState(() => _query = v),
        style: p.ui(size: 13),
        decoration: InputDecoration(
          hintText: 'Filter findings',
          isDense: true,
          prefixIcon: Icon(Icons.search_rounded, size: 18, color: p.textFaint),
        ),
      ),
      const SizedBox(height: 12),
      if (issues.isEmpty)
        Panel(
          child: Row(children: [
            Icon(Icons.verified_rounded, color: p.success),
            const SizedBox(width: 10),
            Expanded(child: Text(r.issues.isEmpty ? 'No weaknesses found in this scan.' : 'Nothing matches the filter.', style: p.ui(size: 14, weight: FontWeight.w600))),
          ]),
        ),
      for (var i = 0; i < issues.length; i++)
        _triaged(p, r, issues[i],
            FindingCard(key: ValueKey('${issues[i].id}-${issues[i].location}-$i'), f: issues[i], tech: r.tech, onAskAi: _askAi, initiallyOpen: i == 0 && issues[i].severity.index <= 1)),
      if (r.notes.isNotEmpty) ...[
        const SizedBox(height: 18),
        Text('Recommendations', style: p.ui(size: 15, weight: FontWeight.w700)),
        const SizedBox(height: 10),
        for (final f in r.notes) FindingCard(f: f, tech: r.tech, onAskAi: _askAi),
      ],
      if (r.passes.isNotEmpty) ...[
        const SizedBox(height: 18),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Passed checks  ${r.passes.length}', style: p.ui(size: 15, weight: FontWeight.w700)),
            children: [
              for (final f in r.passes)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.check_circle_rounded, color: p.success, size: 18),
                  title: Text(f.title, style: p.ui(size: 13)),
                  subtitle: f.evidence.isEmpty ? null : Text(f.evidence, maxLines: 1, overflow: TextOverflow.ellipsis, style: p.ui(size: 11.5, color: p.textFaint)),
                ),
            ],
          ),
        ),
      ],
      if (_log.isNotEmpty) ...[
        const SizedBox(height: 18),
        SizedBox(height: 240, child: _console(p)),
      ],
    ]);
  }

  Widget _codeView(NovaPalette p) {
    final res = _code;
    final list = res == null ? const <Finding>[] : (res.findings.toList()..sort((a, b) => a.severity.index.compareTo(b.severity.index)));
    return ListView(padding: const EdgeInsets.fromLTRB(16, 18, 16, 40), children: [
      Text('Code scan', style: p.title(size: 20)),
      const SizedBox(height: 4),
      Text(
        _codeLabel ??
            'Choose a .zip of your project, or pick files. Files are read on this phone; only package names and versions are checked online.',
        style: p.ui(size: 13, color: p.textMuted, height: 1.4),
      ),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          onPressed: _codeRunning ? null : _pickZip,
          icon: const Icon(Icons.folder_zip_outlined, size: 18),
          label: const Text('Choose .zip'),
        ),
        OutlinedButton.icon(
          onPressed: _codeRunning ? null : _pickFiles,
          icon: const Icon(Icons.file_open_outlined, size: 18),
          label: const Text('Pick files'),
        ),
        FilledButton.icon(
          onPressed: _codeFiles == null || _codeRunning ? null : _runCode,
          icon: _codeRunning
              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.onAccent))
              : const Icon(Icons.play_arrow_rounded),
          label: const Text('Scan code'),
        ),
      ]),
      const SizedBox(height: 8),
      Text('Tip: zip only your source code — node_modules, vendor, .git and build folders are skipped anyway.',
          style: p.ui(size: 11.5, color: p.textFaint)),
      // 3.13.1: on PC NOVA Cyber scans a whole project folder directly.
      if (_codeFiles == null)
        const WindowsDownloadCard(
          reason: 'On Windows, NOVA Cyber scans a whole project folder directly.',
          margin: EdgeInsets.fromLTRB(0, 14, 0, 0),
        ),
      const SizedBox(height: 14),
      if (_codeError != null) Padding(padding: const EdgeInsets.only(bottom: 14), child: _errorBox(p, _codeError!)),
      if (_codeRunning) SizedBox(height: 300, child: _console(p)),
      if (res != null && !_codeRunning) ...[
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 22, runSpacing: 12, children: [
              Metric(value: '${res.files}', label: 'Files read'),
              Metric(value: '${res.packages}', label: 'Dependencies'),
              for (final s in Severity.values.where((s) => s != Severity.info))
                Metric(value: '${list.where((f) => f.severity == s).length}', label: s.label, color: sevColor(s, p)),
            ]),
            if (_codeReport != null) ...[
              const SizedBox(height: 14),
              FilledButton.tonalIcon(
                onPressed: () => setState(() {
                  _report = _codeReport;
                  _view = _View.scan;
                }),
                icon: const Icon(Icons.open_in_full_rounded, size: 16),
                label: const Text('Open report · triage · export'),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 14),
        if (list.isEmpty) Panel(child: Text('No issues found.', style: p.ui(size: 14, weight: FontWeight.w600))),
        for (final f in list) FindingCard(f: f, tech: TechProfile(), onAskAi: _askAi),
      ],
    ]);
  }

  // ── PC-only tools (shown with a Windows card) ──────────────────────────────

  static const List<(String, String, IconData)> _pcTools = [
    (
      'Mobile app (APK) check',
      'On Windows, NOVA Cyber deep-tests your own Android app: manifest, signing, libraries, secrets and backend exposure.',
      Icons.android_rounded
    ),
    ('Native binary check', 'On Windows, NOVA Cyber checks EXE, DLL and Linux binaries for missing protections and weak signing.', Icons.memory_rounded),
    ('Jobs', 'On Windows, long scans run as background jobs you can retry and track.', Icons.playlist_play_rounded),
  ];

  // ── Cyber status card (3.14.0) ─────────────────────────────────────────────

  Widget _statusCard(NovaPalette p, MonitorOverview o) {
    final active = o.monitors.where((m) => m.enabled).toList();
    final up = active.where((m) => m.status == 'up').length;
    final down = active.where((m) => m.status == 'down').length;
    final certs = active.where((m) => (m.certDaysLeft ?? 999) <= 14).toList()
      ..sort((a, b) => (a.certDaysLeft ?? 0).compareTo(b.certDaysLeft ?? 0));
    final parts = <String>[
      '$up site${up == 1 ? '' : 's'} up',
      if (down > 0) '$down down',
      if (certs.isNotEmpty)
        '${certs.length} certificate${certs.length == 1 ? '' : 's'} expire${certs.length == 1 ? 's' : ''} in ${certs.first.certDaysLeft} day${certs.first.certDaysLeft == 1 ? '' : 's'}',
      if (_unread > 0) '$_unread new alert${_unread == 1 ? '' : 's'}',
    ];
    final color = down > 0 ? p.danger : (certs.isNotEmpty || _unread > 0 ? p.warning : p.success);
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _view = _View.monitor),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.45))),
          child: Row(children: [
            Icon(Icons.monitor_heart_rounded, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Monitoring', style: p.ui(size: 12, color: p.textFaint, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(parts.join(' · '), style: p.ui(size: 13.5, weight: FontWeight.w700)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: p.textFaint),
          ]),
        ),
      ),
    );
  }

  // ── 24/7 Monitoring (3.14.0) ───────────────────────────────────────────────

  Future<void> _pollAlerts({bool notify = true}) async {
    if (!await ApiService.isLoggedIn()) return;
    try {
      final (events, unread) = await CyberMonitoring.events(limit: 100);
      if (!mounted) return;
      final newest = events.isEmpty ? 0 : events.first.id;
      final fresh = _lastEventId == null ? <MonitorEvent>[] : events.where((e) => e.id > _lastEventId! && !e.read).toList();
      setState(() {
        _events = events;
        _unread = unread;
        _lastEventId = newest;
      });
      final urgent = fresh.where((e) => e.severity == 'critical' || e.severity == 'high' || e.kind == 'down').toList();
      if (notify && urgent.isNotEmpty) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          duration: const Duration(seconds: 8),
          content: Text('NOVA Cyber: ${urgent.first.title}${urgent.length > 1 ? ' (+${urgent.length - 1} more)' : ''}'),
          action: SnackBarAction(label: 'View', onPressed: () => setState(() => _view = _View.monitor)),
        ));
      }
    } catch (_) {
      // Best effort; the Monitoring tab shows errors when opened.
    }
  }

  Future<void> _loadMonitoring({bool quiet = false}) async {
    if (!await ApiService.isLoggedIn()) {
      if (mounted && !quiet) setState(() => _monError = 'Sign in to NOVA X to monitor your verified sites.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _monLoading = true;
      if (!quiet) _monError = null;
    });
    try {
      final o = await CyberMonitoring.overview();
      await _pollAlerts(notify: false);
      if (!mounted) return;
      setState(() {
        _mon = o;
        _monError = null;
        final free = o.verifiedHosts.where((h) => !o.monitors.any((m) => m.host == h)).toList();
        if (_addHost == null || !free.contains(_addHost)) _addHost = free.isEmpty ? null : free.first;
        if (!o.intervals.contains(_addInterval) && o.intervals.isNotEmpty) _addInterval = o.intervals.contains(15) ? 15 : o.intervals.first;
      });
    } on CyberApiError catch (e) {
      if (mounted && !quiet) setState(() => _monError = e.message);
    } catch (_) {
      if (mounted && !quiet) setState(() => _monError = 'Couldn\'t reach the NOVA X server. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _monLoading = false);
    }
  }

  Future<void> _monAction(String host, Future<void> Function() action) async {
    setState(() => _monBusy.add(host));
    try {
      await action();
      await _loadMonitoring();
    } on CyberApiError catch (e) {
      if (mounted) _snack(e.status == 403 ? '${e.message} Verify the site in the Verified tab first.' : e.message);
    } catch (_) {
      if (mounted) _snack('Couldn\'t reach the NOVA X server. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _monBusy.remove(host));
    }
  }

  Color _monColor(NovaPalette p, String status) => switch (status) {
        'up' => p.success,
        'down' => p.danger,
        'warn' => p.warning,
        'paused' => p.textFaint,
        _ => p.accent,
      };

  String _monLabel(String status) => switch (status) {
        'up' => 'Up',
        'down' => 'Down',
        'warn' => 'Blocked / warning',
        'paused' => 'Paused',
        _ => 'Waiting for first check',
      };

  Color _evColor(NovaPalette p, String sev) => switch (sev) {
        'critical' => p.danger,
        'high' => const Color(0xFFE16F24),
        'medium' => p.warning,
        'low' => p.accent,
        _ => p.success,
      };

  String _when(DateTime? t) {
    if (t == null) return '—';
    final d = DateTime.now().difference(t);
    if (d.isNegative) {
      final f = -d.inMinutes;
      return f < 1 ? 'in a moment' : 'in $f min';
    }
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  String _held(DateTime? t) {
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return 'for ${d.inMinutes} min';
    if (d.inDays < 1) return 'for ${d.inHours} h';
    return 'for ${d.inDays} d';
  }

  String _every(int i) => i == 60 ? '1 h' : '$i min';

  Widget _monitorView(NovaPalette p) {
    final o = _mon;
    final free = o == null ? <String>[] : o.verifiedHosts.where((h) => !o.monitors.any((m) => m.host == h)).toList();
    final wide = MediaQuery.of(context).size.width > 840;
    final cards = o == null ? <Widget>[] : [for (final m in o.monitors) _monitorCard(p, m, o.intervals)];
    return RefreshIndicator(
      onRefresh: _loadMonitoring,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 18, 16, 40), children: [
        Row(children: [
          Expanded(child: Text('Monitoring · 24/7', style: p.title(size: 20))),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _monLoading ? null : _loadMonitoring,
            icon: _monLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.refresh_rounded, color: p.textMuted),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          'The NOVA X server checks your verified sites around the clock — even when your phone is off — and e-mails you when something changes: '
          'downtime, certificate expiry, removed security headers, new scripts, exposed files and DNS changes.',
          style: p.ui(size: 13, color: p.textMuted, height: 1.45),
        ),
        const SizedBox(height: 14),
        if (_monError != null) Padding(padding: const EdgeInsets.only(bottom: 14), child: _errorBox(p, _monError!)),
        if (o == null && _monLoading) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
        if (o != null && o.verifiedHosts.isEmpty && o.monitors.isEmpty)
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.verified_user_outlined, color: p.accent),
                const SizedBox(width: 10),
                Expanded(child: Text('Monitoring works for sites you have verified.', style: p.ui(size: 14, weight: FontWeight.w700))),
              ]),
              const SizedBox(height: 6),
              Text('Verify a site first — it takes a minute with a DNS record, a file or a meta tag.', style: p.ui(size: 13, color: p.textMuted)),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => setState(() => _view = _View.sites), child: const Text('Verify a site')),
            ]),
          ),
        if (o != null && free.isNotEmpty)
          Panel(
            title: 'Add a verified site',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButton<String>(
                value: free.contains(_addHost) ? _addHost : null,
                isExpanded: true,
                dropdownColor: p.surface,
                hint: Text('Choose a verified site', style: p.ui(color: p.textFaint)),
                items: [for (final h in free) DropdownMenuItem(value: h, child: Text(h, style: p.ui(size: 14)))],
                onChanged: (v) => setState(() => _addHost = v),
              ),
              const SizedBox(height: 10),
              Text('Check every', style: p.ui(size: 12.5, color: p.textMuted)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                for (final i in o.intervals)
                  ChoiceChip(
                    label: Text(_every(i), style: p.ui(size: 12.5, weight: FontWeight.w600)),
                    selected: _addInterval == i,
                    onSelected: (_) => setState(() => _addInterval = i),
                    showCheckmark: false,
                  ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Text('${o.monitors.length} of ${o.limit} sites', style: p.ui(size: 12, color: p.textFaint))),
                FilledButton.icon(
                  onPressed: _addHost == null || _monBusy.contains(_addHost) || o.monitors.length >= o.limit
                      ? null
                      : () {
                          final h = _addHost!;
                          unawaited(CyberAudit.log('monitor.add', h, scope: 'verified site', detail: 'every $_addInterval min'));
                          _monAction(h, () async => CyberMonitoring.save(h, enabled: true, intervalMin: _addInterval, emailAlerts: true));
                        },
                  icon: const Icon(Icons.monitor_heart_outlined, size: 18),
                  label: const Text('Start monitoring'),
                ),
              ]),
            ]),
          ),
        if (o != null) ...[
          const SizedBox(height: 14),
          if (wide)
            Wrap(spacing: 12, children: [
              for (final c in cards) SizedBox(width: (MediaQuery.of(context).size.width - 44) / 2, child: c),
            ])
          else
            ...cards,
          if (o.monitors.isEmpty && o.verifiedHosts.isNotEmpty)
            Panel(child: Text('No sites monitored yet. Pick a verified site above.', style: p.ui(color: p.textMuted))),
        ],
        const SizedBox(height: 18),
        Panel(
          title: 'Alerts${_unread > 0 ? '  ($_unread new)' : ''}',
          trailing: _unread > 0
              ? TextButton(
                  onPressed: () async {
                    try {
                      await CyberMonitoring.markRead();
                    } catch (_) {}
                    await _pollAlerts(notify: false);
                  },
                  child: const Text('Mark all read'))
              : null,
          child: _events.isEmpty
              ? Text('Nothing yet. Alerts appear here and in your e-mail as soon as the monitor sees a change.', style: p.ui(size: 13, color: p.textMuted))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final e in _events.take(100))
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        onExpansionChanged: (open) async {
                          if (!open || e.read) return;
                          try {
                            await CyberMonitoring.markRead([e.id]);
                          } catch (_) {}
                          await _pollAlerts(notify: false);
                        },
                        leading: Container(width: 9, height: 9, decoration: BoxDecoration(color: _evColor(p, e.severity), shape: BoxShape.circle)),
                        title: Text(e.title, style: p.ui(size: 13.5, weight: e.read ? FontWeight.w500 : FontWeight.w700)),
                        subtitle: Text('${e.host} · ${e.severity.toUpperCase()} · ${_when(e.createdAt)}${e.emailed ? ' · e-mailed' : ''}',
                            style: p.ui(size: 11.5, color: p.textFaint)),
                        childrenPadding: const EdgeInsets.fromLTRB(22, 0, 0, 12),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(e.detail, style: p.ui(size: 12.5, color: p.text, height: 1.5)),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () => setState(() {
                              _target.text = e.host;
                              _level = ScanLevel.full;
                              _report = null;
                              _view = _View.scan;
                            }),
                            icon: const Icon(Icons.radar_rounded, size: 16),
                            label: const Text('Run a full scan'),
                          ),
                        ],
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }

  Widget _monitorCard(NovaPalette p, SiteMonitor m, List<int> intervals) {
    final busy = _monBusy.contains(m.host);
    final c = _monColor(p, m.enabled ? m.status : 'paused');
    final cert = m.certDaysLeft;
    Widget stat(String label, String value, {Color? color}) => SizedBox(
          width: 96,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: p.ui(size: 15, weight: FontWeight.w700, color: color ?? p.text)),
            Text(label, style: p.ui(size: 11, color: p.textFaint)),
          ]),
        );
    String pct(double? v) => v == null ? '—' : '${v.toStringAsFixed(v == 100 ? 0 : 2)}%';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: m.status == 'down' && m.enabled ? p.danger : p.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text(m.host, maxLines: 1, overflow: TextOverflow.ellipsis, style: p.ui(size: 15, weight: FontWeight.w700))),
          if (busy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Tag(m.enabled ? _monLabel(m.status) : 'Paused', color: c),
          if (m.statusSince != null && m.enabled && m.status != 'pending')
            Text('${_monLabel(m.status)} ${_held(m.statusSince)}', style: p.ui(size: 11.5, color: p.textFaint)),
        ]),
        if (m.pausedReason != null && m.status == 'paused')
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(m.pausedReason!, style: p.ui(size: 12.5, color: p.warning))),
        const SizedBox(height: 12),
        Wrap(runSpacing: 10, spacing: 8, children: [
          stat('Response', m.lastMs == null ? '—' : '${m.lastMs} ms'),
          stat('Code', m.lastCode == null ? '—' : '${m.lastCode}'),
          stat('Certificate', cert == null ? '—' : '$cert days', color: cert == null ? null : (cert <= 7 ? p.danger : cert <= 14 ? p.warning : p.success)),
          stat('Headers', '${m.securityHeaders.length}/6'),
          stat('Ext. scripts', '${m.externalScripts.length}'),
          stat('Exposed files', '${m.exposed.length}', color: m.exposed.isEmpty ? p.success : p.danger),
          stat('Uptime 24 h', pct(m.day.uptime),
              color: m.day.uptime == null ? null : (m.day.uptime! >= 99.5 ? p.success : m.day.uptime! >= 95 ? p.warning : p.danger)),
          stat('Uptime 7 d', pct(m.week.uptime)),
          stat('Avg 24 h', m.day.avgMs == null ? '—' : '${m.day.avgMs} ms'),
        ]),
        const SizedBox(height: 10),
        Text('Last check ${_when(m.lastCheckAt)} · next ${_when(m.nextCheckAt)}', style: p.ui(size: 11.5, color: p.textFaint)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final i in intervals)
            ChoiceChip(
              label: Text(_every(i), style: p.ui(size: 12)),
              selected: m.intervalMin == i,
              visualDensity: VisualDensity.compact,
              showCheckmark: false,
              onSelected: busy ? null : (_) => _monAction(m.host, () async => CyberMonitoring.save(m.host, intervalMin: i)),
            ),
        ]),
        Row(children: [
          Text('E-mail alerts', style: p.ui(size: 12.5, color: p.textMuted)),
          Switch(value: m.emailAlerts, onChanged: busy ? null : (v) => _monAction(m.host, () async => CyberMonitoring.save(m.host, emailAlerts: v))),
        ]),
        Wrap(spacing: 8, runSpacing: 6, children: [
          OutlinedButton.icon(
            onPressed: busy || !m.enabled
                ? null
                : () => _monAction(m.host, () async {
                      final (_, n) = await CyberMonitoring.checkNow(m.host);
                      if (mounted) _snack(n == 0 ? '${m.host}: checked — no changes.' : '${m.host}: $n new alert${n == 1 ? '' : 's'}.');
                    }),
            icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
            label: const Text('Check now'),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : () => _monAction(m.host, () async => CyberMonitoring.save(m.host, enabled: !m.enabled)),
            icon: Icon(m.enabled ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 18),
            label: Text(m.enabled ? 'Pause' : 'Resume'),
          ),
          TextButton.icon(
            onPressed: busy
                ? null
                : () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: p.surface,
                        title: Text('Stop monitoring ${m.host}?', style: p.title(size: 17)),
                        content: Text('Checks and history for this site are removed. Alerts already sent stay in your list.', style: p.ui(color: p.textMuted)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      unawaited(CyberAudit.log('monitor.remove', m.host));
                      await _monAction(m.host, () => CyberMonitoring.remove(m.host));
                    }
                  },
            icon: Icon(Icons.delete_outline_rounded, size: 18, color: p.textFaint),
            label: Text('Remove', style: p.ui(size: 13, color: p.textFaint)),
          ),
        ]),
      ]),
    );
  }

  // ── Triage (3.14.0) ────────────────────────────────────────────────────────

  Widget _triaged(NovaPalette p, ScanReport r, Finding f, Widget card) {
    final t = CyberTriage.get(r, f);
    final regression = CyberTriage.isRegression(r, f);
    final status = t?.status ?? TriageStatus.open;
    final color = switch (status) {
      TriageStatus.confirmed => p.danger,
      TriageStatus.falsePositive || TriageStatus.acceptedRisk => p.textFaint,
      TriageStatus.fixed => p.success,
      TriageStatus.open => p.textMuted,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Row(children: [
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              if (f.cvss.isNotEmpty) Tag('CVSS ${cvssScore(f.cvss).toStringAsFixed(1)} ${cvssRating(cvssScore(f.cvss))}', icon: Icons.speed_rounded),
              if (regression) Tag('Regression', icon: Icons.replay_rounded, color: p.danger),
            ]),
          ),
          PopupMenuButton<TriageStatus>(
            tooltip: 'Triage this finding',
            initialValue: status,
            color: p.surface,
            onSelected: (s) {
              CyberTriage.set(r, f, s);
              unawaited(CyberAudit.log('triage', r.displayName, detail: '${f.id} → ${s.name}'));
              setState(() {});
            },
            itemBuilder: (_) => [for (final s in TriageStatus.values) PopupMenuItem(value: s, child: Text(s.label, style: p.ui(size: 13.5)))],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.flag_outlined, size: 14, color: color),
                const SizedBox(width: 4),
                Text(status.label, style: p.ui(size: 11.5, color: color, weight: FontWeight.w600)),
                Icon(Icons.arrow_drop_down_rounded, size: 16, color: color),
              ]),
            ),
          ),
        ]),
      ),
      Opacity(opacity: status == TriageStatus.falsePositive || status == TriageStatus.acceptedRisk ? 0.55 : 1, child: card),
    ]);
  }

  Widget _historyView(NovaPalette p) {
    return FutureBuilder<List<ScanReport>>(
      future: CyberHistory.all(),
      builder: (context, snap) {
        final list = snap.data ?? const <ScanReport>[];
        return ListView(padding: const EdgeInsets.fromLTRB(16, 18, 16, 40), children: [
          Row(children: [
            Expanded(child: Text('History', style: p.title(size: 20))),
            if (list.isNotEmpty)
              TextButton(
                onPressed: () async {
                  await CyberHistory.clear();
                  setState(() {});
                },
                child: const Text('Clear history'),
              ),
          ]),
          const SizedBox(height: 14),
          if (snap.connectionState != ConnectionState.done)
            const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
          else if (list.isEmpty)
            Panel(child: Text('Scans you run appear here.', style: p.ui(color: p.textMuted))),
          for (var i = 0; i < list.length; i++) _historyRow(p, list, i),
        ]);
      },
    );
  }

  Widget _historyRow(NovaPalette p, List<ScanReport> list, int i) {
    final r = list[i];
    final host = r.displayName;
    final prev = list.skip(i + 1).firstWhere((x) => x.displayName == host && x.level == r.level, orElse: () => r);
    final delta = identical(prev, r) ? null : r.score - prev.score;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
      child: ListTile(
        onTap: () => setState(() {
          _report = r;
          _view = _View.scan;
          if (r.level.isWeb) _target.text = host;
        }),
        leading: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: gradeColor(r.score, p), width: 2.5)),
          child: Text('${r.score}', style: p.ui(size: 14, weight: FontWeight.w800)),
        ),
        title: Text(host, maxLines: 1, overflow: TextOverflow.ellipsis, style: p.ui(size: 14, weight: FontWeight.w600)),
        subtitle: Text(
          '${r.level.label} · ${r.started.toLocal().toString().substring(0, 16)}'
          '${Severity.values.any((s) => s != Severity.info && r.count(s) > 0) ? '\n' : ''}'
          '${Severity.values.where((s) => s != Severity.info && r.count(s) > 0).map((s) => '${r.count(s)} ${s.label.toLowerCase()}').join(', ')}',
          style: p.ui(size: 12, color: p.textFaint),
        ),
        trailing: delta == null
            ? null
            : Text('${delta >= 0 ? '+' : ''}$delta', style: p.ui(size: 13, weight: FontWeight.w700, color: delta >= 0 ? p.success : p.danger)),
      ),
    );
  }
}
