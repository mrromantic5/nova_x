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
//   Code scan      a project .zip or picked files, read on the phone
//   History        earlier reports on this phone

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/rewards_entitlements.dart';
import '../../../core/services/rewards_service.dart';
import '../../../core/widgets/feature_lock.dart';
import '../../ai/screens/ai_assistant_screen.dart';
import '../../guide/guide_screen.dart';
import '../engine/checks_full.dart';
import '../engine/cyber_api.dart';
import '../engine/cyber_code_scan.dart';
import '../engine/cyber_engine.dart';
import '../engine/cyber_models.dart';
import '../engine/zip_reader.dart';
import '../ui/cyber_palette.dart';
import '../ui/cyber_verify.dart';
import '../ui/cyber_widgets.dart';

enum _View { scan, sites, code, history }

class CyberScreen extends StatefulWidget {
  const CyberScreen({super.key, this.initialUrl = ''});

  /// Opened from the browser: the site's address is filled in (not scanned
  /// until the user taps Run).
  final String initialUrl;

  @override
  State<CyberScreen> createState() => _CyberScreenState();
}

class _CyberScreenState extends State<CyberScreen> with WidgetsBindingObserver {
  static const _screen = MethodChannel('com.tlyfe.nova_x/default_browser');

  _View _view = _View.scan;
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
  bool _codeRunning = false;
  String? _codeError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final u = normalizeTarget(widget.initialUrl);
    if (u != null && (u.scheme == 'https' || u.scheme == 'http')) _target.text = u.host;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _target.dispose();
    _logScroll.dispose();
    if (_running) CyberEngine.instance.stop();
    _keepAwake(false);
    super.dispose();
  }

  // Leaving the app stops the scan cleanly; the partial report is kept.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
      if (mounted) setState(() => _report = r);
    } catch (e) {
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
    final host = Uri.tryParse(r.target)?.host ?? 'site';
    final stamp = r.started.toIso8601String().substring(0, 10);
    final text = kind == 'html' ? CyberReportWriter.html(r) : CyberReportWriter.markdown(r);
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save security report',
        fileName: 'nova-cyber-$host-$stamp.${kind == 'html' ? 'html' : 'md'}',
        bytes: Uint8List.fromList(utf8.encode(text)),
      );
      if (path == null) return;
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
      _code = await CodeScanner.scanFiles(files, label: _codeLabel ?? 'project', onLog: _addLog);
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
            actions: const [
              Padding(padding: EdgeInsets.only(right: 12), child: Center(child: ReadMoreLink('cyber', compact: true))),
            ],
          ),
          body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_view == _View.scan) _scanBar(p),
            Expanded(child: _content(p)),
          ]),
          bottomNavigationBar: NavigationBar(
            backgroundColor: p.surface,
            indicatorColor: p.accentSoft,
            selectedIndex: _view.index,
            height: 64,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (i) => setState(() => _view = _View.values[i]),
            destinations: [
              NavigationDestination(icon: Icon(Icons.radar_rounded, color: p.textMuted), selectedIcon: Icon(Icons.radar_rounded, color: p.accent), label: 'Website'),
              NavigationDestination(icon: Icon(Icons.verified_user_outlined, color: p.textMuted), selectedIcon: Icon(Icons.verified_user_rounded, color: p.accent), label: 'Verified'),
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
    final issues = r.issues.where((f) {
      if (_sev != null && f.severity != _sev) return false;
      if (_area != null && f.area != _area) return false;
      if (_query.isNotEmpty && !('${f.title} ${f.evidence} ${f.location}'.toLowerCase().contains(_query.toLowerCase()))) return false;
      return true;
    }).toList();
    final lost = r.lostByArea.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final host = Uri.tryParse(r.target)?.host ?? r.target;
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
                Tag(r.level == ScanLevel.full ? 'Full scan · verified' : 'Quick scan · read-only',
                    icon: r.level == ScanLevel.full ? Icons.verified_user_rounded : Icons.visibility_outlined,
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
          const SizedBox(height: 16),
          _counts(p, r.count, r.passes.length),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: () => _export('html'), icon: const Icon(Icons.description_outlined, size: 16), label: const Text('Export report')),
            OutlinedButton.icon(onPressed: () => _export('md'), icon: const Icon(Icons.notes_rounded, size: 16), label: const Text('Markdown')),
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
        FindingCard(key: ValueKey('${issues[i].id}-${issues[i].location}-$i'), f: issues[i], tech: r.tech, onAskAi: _askAi, initiallyOpen: i == 0 && issues[i].severity.index <= 1),
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
      const SizedBox(height: 14),
      if (_codeError != null) Padding(padding: const EdgeInsets.only(bottom: 14), child: _errorBox(p, _codeError!)),
      if (_codeRunning) SizedBox(height: 300, child: _console(p)),
      if (res != null && !_codeRunning) ...[
        Panel(
          child: Wrap(spacing: 22, runSpacing: 12, children: [
            Metric(value: '${res.files}', label: 'Files read'),
            Metric(value: '${res.packages}', label: 'Dependencies'),
            for (final s in Severity.values.where((s) => s != Severity.info))
              Metric(value: '${list.where((f) => f.severity == s).length}', label: s.label, color: sevColor(s, p)),
          ]),
        ),
        const SizedBox(height: 14),
        if (list.isEmpty) Panel(child: Text('No issues found.', style: p.ui(size: 14, weight: FontWeight.w600))),
        for (final f in list) FindingCard(f: f, tech: TechProfile(), onAskAi: _askAi),
      ],
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
    final host = Uri.tryParse(r.target)?.host ?? r.target;
    final prev = list.skip(i + 1).firstWhere((x) => (Uri.tryParse(x.target)?.host ?? '') == host && x.level == r.level, orElse: () => r);
    final delta = identical(prev, r) ? null : r.score - prev.score;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
      child: ListTile(
        onTap: () => setState(() {
          _report = r;
          _view = _View.scan;
          _target.text = host;
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
          '${r.level == ScanLevel.full ? 'Full' : 'Quick'} · ${r.started.toLocal().toString().substring(0, 16)}'
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
