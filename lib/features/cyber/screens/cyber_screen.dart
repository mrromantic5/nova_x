// lib/features/cyber/screens/cyber_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/services/cyber_service.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import '../models/security_report.dart';

class CyberScreen extends StatefulWidget {
  final String initialUrl;
  const CyberScreen({super.key, this.initialUrl = ''});
  @override State<CyberScreen> createState() => _CyberScreenState();
}

class _CyberScreenState extends State<CyberScreen>
    with TickerProviderStateMixin {

  final _urlCtrl    = TextEditingController();
  final _logScroll  = ScrollController();
  SecurityReport? _report;
  bool   _scanning  = false;
  bool   _showLog   = false;
  String? _error;
  CheckCategory? _catFilter;
  Severity?      _sevFilter;

  late AnimationController _scoreAnim;
  late AnimationController _pulseAnim;
  late AnimationController _shimmerAnim;
  late Animation<double>   _scoreVal;

  @override
  void initState() {
    super.initState();
    _scoreAnim   = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1600));
    _pulseAnim   = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 2000))..repeat(reverse: true);
    _shimmerAnim = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1200))..repeat();
    _scoreVal    = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _scoreAnim, curve: Curves.easeOutCubic));

    if (widget.initialUrl.isNotEmpty) {
      _urlCtrl.text = widget.initialUrl;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
    }
  }

  @override
  void dispose() {
    _scoreAnim.dispose(); _pulseAnim.dispose();
    _shimmerAnim.dispose(); _urlCtrl.dispose();
    _logScroll.dispose(); super.dispose();
  }

  final _logLines = <String>[];

  Future<void> _scan() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _scanning = true; _report = null;
      _error = null; _logLines.clear(); _showLog = true;
    });
    _scoreAnim.reset();
    try {
      final report = await CyberService.analyze(url, onLog: (line) {
        if (mounted) setState(() {
          _logLines.add(line);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_logScroll.hasClients) {
              _logScroll.animateTo(_logScroll.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut);
            }
          });
        });
      });
      if (!mounted) return;
      setState(() { _report = report; _scanning = false; });
      _scoreAnim.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _scanning = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Stack(children: [
        Positioned(top: -60, right: -80,
            child: _glow(AppTheme.accentCyan.withOpacity(0.07), 300)),
        Positioned(bottom: 200, left: -100,
            child: _glow(AppTheme.accentPurple.withOpacity(0.05), 260)),

        CustomScrollView(slivers: [
          _appBar(),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
            sliver: SliverList(delegate: SliverChildListDelegate([
              _urlBar(),
              const SizedBox(height: 16),
              if (_scanning || _logLines.isNotEmpty) _terminalLog(),
              if (_error != null) _errorCard(),
              if (_report != null) ...[
                const SizedBox(height: 8),
                _scoreCard(),
                const SizedBox(height: 12),
                _riskBanner(),
                const SizedBox(height: 16),
                _techStackCard(),
                const SizedBox(height: 16),
                _statsRow(),
                const SizedBox(height: 20),
                _owaspSummary(),
                const SizedBox(height: 20),
                _filterBar(),
                const SizedBox(height: 12),
                ..._checkList(),
                if (_report!.exposedPaths.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _exposedPathsCard(),
                ],
                const SizedBox(height: 20),
                if (_report!.recommendations.isNotEmpty) _recsCard(),
                const SizedBox(height: 20),
                _rawHeadersCard(),
                const SizedBox(height: 20),
                _dnsCard(),
                const SizedBox(height: 12),
                _footerCard(),
              ],
            ])),
          ),
        ]),
      ]),
    );
  }

  // ── App Bar ──────────────────────────────────────────────────────────────────
  Widget _appBar() => SliverAppBar(
    pinned: true, expandedHeight: 130,
    backgroundColor: AppTheme.bgDark, elevation: 0,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios_new_rounded,
          color: Colors.white, size: 18),
      onPressed: () => Navigator.pop(context),
    ),
    actions: [
      if (_report != null)
        IconButton(icon: const Icon(Icons.share_outlined,
            color: AppTheme.accentCyan, size: 20),
            onPressed: _share),
    ],
    flexibleSpace: FlexibleSpaceBar(
      background: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF040D18), AppTheme.bgDark]),
        ),
        child: SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(72, 24, 24, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end, children: [
            _tag('PENETRATION TESTING  •  40+ CHECKS', AppTheme.accentCyan),
            const SizedBox(height: 6),
            ShaderMask(
              shaderCallback: (r) => const LinearGradient(
                colors: [AppTheme.accentCyan, AppTheme.accentPurple],
              ).createShader(r),
              child: Text('NOVA Cyber', style: GoogleFonts.spaceGrotesk(
                  color: Colors.white, fontSize: 28,
                  fontWeight: FontWeight.w900)),
            ),
            Text('Security Analysis Engine  •  OWASP Top 10',
                style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11)),
          ]),
        )),
      ),
    ),
  );

  // ── URL input bar ────────────────────────────────────────────────────────────
  Widget _urlBar() => Container(
    decoration: BoxDecoration(color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider)),
    padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
    child: Row(children: [
      const Icon(Icons.radar_rounded, color: AppTheme.accentCyan, size: 20),
      const SizedBox(width: 10),
      Expanded(child: TextField(
        controller: _urlCtrl,
        style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
        keyboardType: TextInputType.url, autocorrect: false,
        onSubmitted: (_) => _scan(),
        decoration: InputDecoration(
          hintText: 'Domain or URL to scan (e.g. example.com)',
          hintStyle: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 13),
          border: InputBorder.none, isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
      )),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: _scanning ? null : _scan,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: _scanning ? null : AppTheme.primaryGradient,
            color: _scanning ? AppTheme.bgElevated : null,
            borderRadius: BorderRadius.circular(11),
            boxShadow: _scanning ? null : AppTheme.glowShadow,
          ),
          child: _scanning
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.accentCyan))
              : Text('SCAN', style: GoogleFonts.spaceGrotesk(
                  color: Colors.white, fontSize: 12,
                  fontWeight: FontWeight.w800, letterSpacing: 1)),
        ),
      ),
    ]),
  );

  // ── Terminal log ─────────────────────────────────────────────────────────────
  Widget _terminalLog() => Container(
    margin: const EdgeInsets.only(bottom: 12),
    height: 160,
    decoration: BoxDecoration(
      color: const Color(0xFF020A12),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppTheme.accentCyan.withOpacity(0.25)),
    ),
    padding: const EdgeInsets.all(12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 8, height: 8,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _scanning ? AppTheme.success : AppTheme.textHint)),
        const SizedBox(width: 6),
        Text(_scanning ? 'SCANNING…' : 'SCAN COMPLETE',
            style: GoogleFonts.inter(color: AppTheme.accentCyan,
                fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
        const Spacer(),
        Text('NOVA Cyber v2.0',
            style: GoogleFonts.inter(color: AppTheme.divider, fontSize: 9)),
      ]),
      const Divider(color: Color(0xFF0A2030), height: 8),
      Expanded(child: ListView.builder(
        controller: _logScroll,
        itemCount: _logLines.length + (_scanning ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == _logLines.length) {
            return AnimatedBuilder(
              animation: _shimmerAnim,
              builder: (_, __) => Text('▋',
                  style: TextStyle(
                      color: _shimmerAnim.value > 0.5
                          ? AppTheme.accentCyan : Colors.transparent,
                      fontSize: 12)),
            );
          }
          final line = _logLines[i];
          Color c = AppTheme.textHint;
          if (line.startsWith('✅') || line.startsWith('🟢')) c = AppTheme.success;
          else if (line.startsWith('🚨') || line.startsWith('❌')) c = AppTheme.danger;
          else if (line.startsWith('⚠️')) c = AppTheme.warning;
          else if (line.startsWith('🔐') || line.startsWith('💉') ||
                   line.startsWith('⚡')) c = AppTheme.accentCyan;
          return Text(line, style: GoogleFonts.inter(
              color: c, fontSize: 11, height: 1.6));
        },
      )),
    ]),
  );

  // ── Score card ───────────────────────────────────────────────────────────────
  Widget _scoreCard() {
    final r  = _report!;
    final gc = _gradeColor(r.grade);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: gc.withOpacity(0.35)),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [AppTheme.bgCard, gc.withOpacity(0.06)]),
      ),
      child: Row(children: [
        AnimatedBuilder(
          animation: _scoreVal,
          builder: (_, __) => CustomPaint(
            size: const Size(108, 108),
            painter: _GaugePainter(
                progress: _scoreVal.value, score: r.score, color: gc)),
        ),
        const SizedBox(width: 20),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          _tag('SECURITY SCORE', gc),
          const SizedBox(height: 6),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: gc.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: gc.withOpacity(0.4)),
              ),
              child: Text('Grade  ${r.grade}', style: GoogleFonts.spaceGrotesk(
                  color: gc, fontSize: 20, fontWeight: FontWeight.w900)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(r.domain, style: GoogleFonts.inter(color: AppTheme.textPrimary,
              fontSize: 13, fontWeight: FontWeight.w700),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text('HTTP ${r.httpStatus}  •  ${r.durationMs}ms  •  ${r.totalChecks} checks',
              style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 10)),
          const SizedBox(height: 6),
          Row(children: [
            Icon(r.isHttps ? Icons.lock_rounded : Icons.lock_open_rounded,
                size: 12,
                color: r.isHttps ? AppTheme.success : AppTheme.danger),
            const SizedBox(width: 4),
            Text(r.isHttps ? 'HTTPS' : 'HTTP — UNENCRYPTED',
                style: GoogleFonts.inter(
                    color: r.isHttps ? AppTheme.success : AppTheme.danger,
                    fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
        ])),
      ]),
    );
  }

  // ── Risk banner ──────────────────────────────────────────────────────────────
  Widget _riskBanner() {
    final (c, ic, label, desc) = _riskInfo(_report!.overallSeverity);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.withOpacity(0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withOpacity(0.35)),
      ),
      child: Row(children: [
        Container(width: 36, height: 36,
          decoration: BoxDecoration(color: c.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(ic, color: c, size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$label Risk  |  ${_report!.criticalCount} critical, '
              '${_report!.highCount} high findings',
              style: GoogleFonts.spaceGrotesk(color: c, fontSize: 13,
                  fontWeight: FontWeight.w800)),
          Text(desc, style: GoogleFonts.inter(
              color: AppTheme.textSecondary, fontSize: 11, height: 1.4)),
        ])),
      ]),
    );
  }

  // ── Tech stack card ──────────────────────────────────────────────────────────
  Widget _techStackCard() {
    final t = _report!.techStack;
    final items = <(String, String, Color)>[];
    if (t.server   != null) items.add(('Server',    t.server!,    AppTheme.accentCyan));
    if (t.language != null) items.add(('Language',  t.language!,  AppTheme.accentPurple));
    if (t.cms      != null) items.add(('CMS',       t.cms!,       AppTheme.warning));
    if (t.cdn      != null) items.add(('CDN/WAF',   t.cdn!,       AppTheme.success));
    if (t.libraries.isNotEmpty) items.add(('JS Libs', t.libraries.join(', '), AppTheme.textHint));
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.layers_rounded, color: AppTheme.accentCyan, size: 16),
          const SizedBox(width: 8),
          Text('Technology Stack', style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textPrimary, fontSize: 13,
              fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: items.map((item) =>
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: item.$3.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: item.$3.withOpacity(0.25)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('${item.$1}: ', style: GoogleFonts.inter(
                  color: item.$3.withOpacity(0.7), fontSize: 10,
                  fontWeight: FontWeight.w700)),
              Text(item.$2, style: GoogleFonts.inter(
                  color: item.$3, fontSize: 10, fontWeight: FontWeight.w700)),
            ]),
          ),
        ).toList()),
      ]),
    );
  }

  // ── Stats row ────────────────────────────────────────────────────────────────
  Widget _statsRow() {
    final r = _report!;
    return Row(children: [
      _statBox('${r.passCount}',     'Passed',   AppTheme.success),
      const SizedBox(width: 8),
      _statBox('${r.warnCount}',     'Warnings', AppTheme.warning),
      const SizedBox(width: 8),
      _statBox('${r.failCount}',     'Failed',   AppTheme.danger),
      const SizedBox(width: 8),
      _statBox('${r.criticalCount}', 'Critical', const Color(0xFFFF1744)),
    ]);
  }

  Widget _statBox(String v, String l, Color c) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(color: c.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withOpacity(0.2))),
    child: Column(children: [
      Text(v, style: GoogleFonts.spaceGrotesk(
          color: c, fontSize: 22, fontWeight: FontWeight.w900)),
      Text(l, style: GoogleFonts.inter(
          color: c.withOpacity(0.7), fontSize: 9,
          fontWeight: FontWeight.w700)),
    ]),
  ));

  // ── OWASP Top 10 summary ─────────────────────────────────────────────────────
  Widget _owaspSummary() {
    final refs = _report!.checks
        .where((c) => c.owaspRef != null && c.status == CheckStatus.fail)
        .map((c) => c.owaspRef!)
        .toSet().toList()..sort();
    if (refs.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.danger.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.danger.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.crisis_alert_rounded, color: AppTheme.danger, size: 16),
          const SizedBox(width: 8),
          Text('OWASP Top 10 — Issues Found',
              style: GoogleFonts.spaceGrotesk(color: AppTheme.danger,
                  fontSize: 13, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: refs.map((ref) =>
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.danger.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.danger.withOpacity(0.3)),
            ),
            child: Text(ref.split('–').first.trim(),
                style: GoogleFonts.inter(color: AppTheme.danger,
                    fontSize: 9, fontWeight: FontWeight.w800)),
          ),
        ).toList()),
      ]),
    );
  }

  // ── Category / severity filter bar ──────────────────────────────────────────
  Widget _filterBar() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Filter by Category', style: GoogleFonts.inter(
          color: AppTheme.textHint, fontSize: 10, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      SizedBox(height: 34, child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _filterChip('All', null == _catFilter && null == _sevFilter,
              () => setState(() { _catFilter = null; _sevFilter = null; }),
              AppTheme.accentCyan),
          for (final cat in CheckCategory.values)
            _filterChip(_catLabel(cat),
                _catFilter == cat,
                () => setState(() { _catFilter = cat; _sevFilter = null; }),
                AppTheme.accentCyan),
          _filterChip('🔴 Critical', _sevFilter == Severity.critical,
              () => setState(() { _catFilter = null; _sevFilter = Severity.critical; }),
              AppTheme.danger),
          _filterChip('🟠 High', _sevFilter == Severity.high,
              () => setState(() { _catFilter = null; _sevFilter = Severity.high; }),
              Colors.orange),
        ],
      )),
    ],
  );

  Widget _filterChip(String label, bool sel, VoidCallback onTap, Color c) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            gradient: sel ? AppTheme.primaryGradient : null,
            color: sel ? null : AppTheme.bgCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: sel ? Colors.transparent : AppTheme.divider),
          ),
          child: Text(label, style: GoogleFonts.inter(
              color: sel ? Colors.white : AppTheme.textHint,
              fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      );

  // ── Check list ───────────────────────────────────────────────────────────────
  List<Widget> _checkList() {
    final all = _report!.checks;
    Iterable<SecurityCheck> filtered = all;
    if (_catFilter != null) filtered = all.where((c) => c.category == _catFilter);
    if (_sevFilter != null) filtered = all.where((c) => c.severity == _sevFilter);

    final byCategory = <CheckCategory, List<SecurityCheck>>{};
    for (final c in filtered) {
      byCategory.putIfAbsent(c.category, () => <SecurityCheck>[]).add(c);
    }

    final widgets = <Widget>[];
    for (final cat in CheckCategory.values) {
      final list = byCategory[cat];
      if (list == null || list.isEmpty) continue;
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Row(children: [
          Icon(_catIcon(cat), color: AppTheme.textHint, size: 13),
          const SizedBox(width: 6),
          Text(_catLabel(cat), style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textHint, fontSize: 11,
              fontWeight: FontWeight.w800, letterSpacing: .3)),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: AppTheme.divider, height: 1)),
        ]),
      ));
      for (final check in list) {
        widgets.add(_checkTile(check));
        widgets.add(const SizedBox(height: 6));
      }
    }
    return widgets;
  }

  Widget _checkTile(SecurityCheck c) {
    final sc = _statusColor(c.status);
    final si = _statusIcon(c.status);
    final sevc = _severityColor(c.severity);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: c.status == CheckStatus.fail
                  ? sevc.withOpacity(0.35) : AppTheme.divider),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Container(width: 32, height: 32,
            decoration: BoxDecoration(
                color: sc.withOpacity(0.12), borderRadius: BorderRadius.circular(9)),
            child: Icon(si, color: sc, size: 16)),
          title: Row(children: [
            Expanded(child: Text(c.name, style: GoogleFonts.inter(
                color: AppTheme.textPrimary, fontSize: 12,
                fontWeight: FontWeight.w700))),
            const SizedBox(width: 6),
            if (c.severity != Severity.info)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: sevc.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sevc.withOpacity(0.3)),
                ),
                child: Text(_severityLabel(c.severity),
                    style: GoogleFonts.inter(
                        color: sevc, fontSize: 8, fontWeight: FontWeight.w800)),
              ),
          ]),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: sc.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sc.withOpacity(0.3)),
                ),
                child: Text(_statusLabel(c.status), style: GoogleFonts.inter(
                    color: sc, fontSize: 8, fontWeight: FontWeight.w800)),
              ),
              if (c.owaspRef != null) ...[
                const SizedBox(width: 6),
                Flexible(child: Text(c.owaspRef!.split('–').first.trim(),
                    style: GoogleFonts.inter(
                        color: AppTheme.textHint, fontSize: 8),
                    overflow: TextOverflow.ellipsis)),
              ],
              const Spacer(),
              if (c.maxScore > 0)
                Text('${c.score}/${c.maxScore}',
                    style: GoogleFonts.inter(
                        color: AppTheme.textHint, fontSize: 9)),
            ]),
          ),
          children: [
            const Divider(color: Color(0x22FFFFFF), height: 1),
            const SizedBox(height: 10),
            _row(Icons.info_outline_rounded, 'Description', c.description,
                AppTheme.textHint),
            const SizedBox(height: 8),
            _row(si, 'Finding', c.detail, sc),
            if (c.evidence != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: const Color(0xFF020A12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.divider)),
                child: GestureDetector(
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: c.evidence!));
                    _snack('Evidence copied');
                  },
                  child: Text(c.evidence!, style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 10,
                      color: Color(0xFF00D4FF)), softWrap: true),
                ),
              ),
            ],
            if (c.cweId != null || c.owaspRef != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                if (c.cweId != null) _metaBadge(c.cweId!, AppTheme.accentPurple),
                if (c.cweId != null && c.owaspRef != null) const SizedBox(width: 6),
                if (c.owaspRef != null)
                  Flexible(child: _metaBadge(c.owaspRef!, AppTheme.warning)),
              ]),
            ],
            if (c.recommendation.isNotEmpty) ...[
              const SizedBox(height: 8),
              _row(Icons.build_outlined, 'Fix', c.recommendation, AppTheme.success),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String text, Color c) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: c, size: 13),
        const SizedBox(width: 7),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.inter(
              color: c.withOpacity(0.7), fontSize: 9,
              fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(text, style: GoogleFonts.inter(
              color: AppTheme.textSecondary, fontSize: 11, height: 1.5)),
        ])),
      ]);

  Widget _metaBadge(String text, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
        color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withOpacity(0.3))),
    child: Text(text, style: GoogleFonts.inter(
        color: c, fontSize: 9, fontWeight: FontWeight.w700)),
  );

  // ── Exposed paths card ───────────────────────────────────────────────────────
  Widget _exposedPathsCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTheme.danger.withOpacity(0.07),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.danger.withOpacity(0.3)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.folder_open_rounded, color: AppTheme.danger, size: 16),
        const SizedBox(width: 8),
        Text('Exposed Sensitive Paths (${_report!.exposedPaths.length})',
            style: GoogleFonts.spaceGrotesk(color: AppTheme.danger,
                fontSize: 13, fontWeight: FontWeight.w800)),
      ]),
      const SizedBox(height: 12),
      ..._report!.exposedPaths.map((p) => GestureDetector(
        onLongPress: () { Clipboard.setData(ClipboardData(text: p)); _snack('URL copied'); },
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
              color: const Color(0xFF020A12), borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.danger.withOpacity(0.2))),
          child: Text(p, style: const TextStyle(
              fontFamily: 'monospace', fontSize: 10, color: AppTheme.danger)),
        ),
      )),
    ]),
  );

  // ── Recommendations card ─────────────────────────────────────────────────────
  Widget _recsCard() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppTheme.warning.withOpacity(0.06),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.warning.withOpacity(0.25)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.lightbulb_outline_rounded, color: AppTheme.warning),
        const SizedBox(width: 8),
        Text('Recommendations (${_report!.recommendations.length})',
            style: GoogleFonts.spaceGrotesk(color: AppTheme.warning,
                fontSize: 14, fontWeight: FontWeight.w800)),
      ]),
      const SizedBox(height: 12),
      ..._report!.recommendations.take(10).map((r) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 5, height: 5, margin: const EdgeInsets.only(top: 5, right: 9),
              decoration: const BoxDecoration(shape: BoxShape.circle,
                  color: AppTheme.warning)),
          Expanded(child: Text(r, style: GoogleFonts.inter(
              color: AppTheme.textSecondary, fontSize: 11, height: 1.55))),
        ]),
      )),
    ]),
  );

  // ── Raw headers card ─────────────────────────────────────────────────────────
  Widget _rawHeadersCard() => Container(
    decoration: BoxDecoration(color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider)),
    child: Theme(data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        leading: const Icon(Icons.code_rounded, color: AppTheme.accentCyan, size: 18),
        title: Text('Raw HTTP Response Headers '
            '(${_report!.responseHeaders.length})',
            style: GoogleFonts.spaceGrotesk(color: AppTheme.textPrimary,
                fontSize: 13, fontWeight: FontWeight.w700)),
        children: [
          const Divider(color: Color(0x22FFFFFF)),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: _report!.responseHeaders.entries.map((e) =>
              GestureDetector(
                onLongPress: () {
                  Clipboard.setData(ClipboardData(text: '${e.key}: ${e.value}'));
                  _snack('Header copied');
                },
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 150, child: Text(e.key,
                        style: TextStyle(color: AppTheme.accentCyan,
                            fontSize: 10, fontWeight: FontWeight.w700,
                            fontFamily: 'monospace'))),
                    Expanded(child: Text(e.value,
                        style: TextStyle(color: AppTheme.textSecondary,
                            fontSize: 10, fontFamily: 'monospace'))),
                  ]),
                ),
              ),
            ).toList()),
          ),
        ],
      ),
    ),
  );

  // ── DNS card ─────────────────────────────────────────────────────────────────
  Widget _dnsCard() {
    if (_report!.dnsRecords.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.divider)),
      child: Theme(data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          leading: const Icon(Icons.dns_outlined, color: AppTheme.accentCyan, size: 18),
          title: Text('DNS Records (${_report!.dnsRecords.length})',
              style: GoogleFonts.spaceGrotesk(color: AppTheme.textPrimary,
                  fontSize: 13, fontWeight: FontWeight.w700)),
          children: [
            const Divider(color: Color(0x22FFFFFF)),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: _report!.dnsRecords.map((rec) =>
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Container(
                      width: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      margin: const EdgeInsets.only(right: 10, top: 1),
                      decoration: BoxDecoration(
                          color: AppTheme.accentCyan.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4)),
                      child: Center(child: Text(rec.type, style: GoogleFonts.inter(
                          color: AppTheme.accentCyan, fontSize: 9,
                          fontWeight: FontWeight.w800))),
                    ),
                    Expanded(child: Text(rec.value, style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 10,
                        fontFamily: 'monospace'))),
                  ]),
                ),
              ).toList()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footerCard() => Center(child: Column(children: [
    Text('NOVA Cyber — Professional Security Analysis',
        style: GoogleFonts.spaceGrotesk(color: AppTheme.textHint, fontSize: 10)),
    Text('Scanned: ${_report!.domain}  •  ${_report!.durationMs}ms  '
        '•  ${_report!.totalChecks} checks performed',
        style: GoogleFonts.inter(color: AppTheme.divider, fontSize: 9)),
    const SizedBox(height: 4),
    Text('Results are indicative. For production use, consult a professional pentest.',
        style: GoogleFonts.inter(color: AppTheme.divider, fontSize: 8)),
  ]));

  Widget _errorCard() => Container(
    margin: const EdgeInsets.only(top: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppTheme.danger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.danger.withOpacity(0.3))),
    child: Row(children: [
      const Icon(Icons.error_outline_rounded, color: AppTheme.danger),
      const SizedBox(width: 10),
      Expanded(child: Text(_error ?? '', style: GoogleFonts.inter(
          color: AppTheme.textSecondary, fontSize: 12))),
    ]),
  );

  void _share() {
    final r = _report!;
    final buf = StringBuffer()
      ..writeln('NOVA Cyber Security Report')
      ..writeln('═' * 40)
      ..writeln('Domain  : ${r.domain}')
      ..writeln('Grade   : ${r.grade}  (${r.score}/100)')
      ..writeln('Risk    : ${_severityLabel(r.overallSeverity)}')
      ..writeln('Checks  : ${r.totalChecks} (✅${r.passCount} ⚠️${r.warnCount} ❌${r.failCount})')
      ..writeln('─' * 40);
    for (final c in r.checks.where((x) => x.status == CheckStatus.fail)) {
      buf.writeln('[FAIL] ${c.name} — ${c.detail}');
    }
    buf..writeln('─' * 40)
       ..writeln('Scanned by NOVA X  |  NOVA Cyber v2.0');
    Clipboard.setData(ClipboardData(text: buf.toString()));
    _snack('Full report copied to clipboard');
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
    backgroundColor: AppTheme.bgElevated, behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 2),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));

  // Helpers
  Widget _glow(Color c, double s) => Container(width: s, height: s,
      decoration: BoxDecoration(shape: BoxShape.circle,
          gradient: RadialGradient(colors: [c, Colors.transparent])));

  Widget _tag(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withOpacity(0.3))),
    child: Text(t, style: GoogleFonts.inter(
        color: c, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1)),
  );

  Color _gradeColor(String g) {
    switch (g) {
      case 'A+': case 'A': return AppTheme.success;
      case 'B':  return const Color(0xFF00BFA5);
      case 'C':  return AppTheme.warning;
      case 'D':  return Colors.orange;
      default:   return AppTheme.danger;
    }
  }

  Color _statusColor(CheckStatus s) => switch (s) {
    CheckStatus.pass => AppTheme.success,
    CheckStatus.warn => AppTheme.warning,
    CheckStatus.fail => AppTheme.danger,
    CheckStatus.info => AppTheme.accentCyan,
  };

  IconData _statusIcon(CheckStatus s) => switch (s) {
    CheckStatus.pass => Icons.check_circle_outline_rounded,
    CheckStatus.warn => Icons.warning_amber_rounded,
    CheckStatus.fail => Icons.cancel_outlined,
    CheckStatus.info => Icons.info_outline_rounded,
  };

  String _statusLabel(CheckStatus s) => switch (s) {
    CheckStatus.pass => 'PASS',
    CheckStatus.warn => 'WARN',
    CheckStatus.fail => 'FAIL',
    CheckStatus.info => 'INFO',
  };

  Color _severityColor(Severity s) => switch (s) {
    Severity.critical => const Color(0xFFFF1744),
    Severity.high     => AppTheme.danger,
    Severity.medium   => Colors.orange,
    Severity.low      => AppTheme.warning,
    Severity.info     => AppTheme.textHint,
  };

  String _severityLabel(Severity s) => switch (s) {
    Severity.critical => 'CRITICAL',
    Severity.high     => 'HIGH',
    Severity.medium   => 'MEDIUM',
    Severity.low      => 'LOW',
    Severity.info     => 'INFO',
  };

  String _catLabel(CheckCategory c) => switch (c) {
    CheckCategory.reconnaissance => 'Recon',
    CheckCategory.tls            => 'TLS',
    CheckCategory.headers        => 'Headers',
    CheckCategory.injection      => 'Injection',
    CheckCategory.authentication => 'Auth',
    CheckCategory.disclosure     => 'Disclosure',
    CheckCategory.dns            => 'DNS',
    CheckCategory.cookies        => 'Cookies',
    CheckCategory.content        => 'Content',
    CheckCategory.waf            => 'WAF',
  };

  IconData _catIcon(CheckCategory c) => switch (c) {
    CheckCategory.reconnaissance => Icons.search_rounded,
    CheckCategory.tls            => Icons.lock_outline_rounded,
    CheckCategory.headers        => Icons.security_rounded,
    CheckCategory.injection      => Icons.bug_report_outlined,
    CheckCategory.authentication => Icons.person_outline_rounded,
    CheckCategory.disclosure     => Icons.visibility_off_outlined,
    CheckCategory.dns            => Icons.dns_outlined,
    CheckCategory.cookies        => Icons.cookie_outlined,
    CheckCategory.content        => Icons.web_rounded,
    CheckCategory.waf            => Icons.shield_outlined,
  };

  (Color, IconData, String, String) _riskInfo(Severity s) => switch (s) {
    Severity.critical => (const Color(0xFFFF1744), Icons.dangerous_rounded,
        'CRITICAL', 'Immediate action required — active exploitation risk.'),
    Severity.high     => (AppTheme.danger, Icons.warning_rounded,
        'HIGH', 'Significant vulnerabilities — prioritise remediation.'),
    Severity.medium   => (Colors.orange, Icons.shield_outlined,
        'MEDIUM', 'Security gaps present — address in next sprint.'),
    Severity.low      => (AppTheme.success, Icons.verified_user_rounded,
        'LOW', 'Good overall posture — minor improvements recommended.'),
    _                 => (AppTheme.textHint, Icons.info_outline_rounded,
        'UNKNOWN', ''),
  };
}

// ── Animated score gauge ──────────────────────────────────────────────────────
class _GaugePainter extends CustomPainter {
  final double progress; final int score; final Color color;
  _GaugePainter({required this.progress, required this.score, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.41;
    final sw = 7.0;
    final start = -math.pi * 0.75;
    final sweep = math.pi * 1.5;

    canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, sweep, false,
        Paint()..color = color.withOpacity(0.1)..style = PaintingStyle.stroke
               ..strokeWidth = sw..strokeCap = StrokeCap.round);

    canvas.drawArc(Rect.fromCircle(center: c, radius: r),
        start, sweep * progress, false,
        Paint()..shader = SweepGradient(startAngle: start, endAngle: start + sweep,
              colors: [color.withOpacity(0.4), color])
            .createShader(Rect.fromCircle(center: c, radius: r))
          ..style = PaintingStyle.stroke..strokeWidth = sw..strokeCap = StrokeCap.round);

    final tp = TextPainter(
      text: TextSpan(text: '${(score * progress).round()}',
          style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.w900)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - tp.height / 2 - 5));

    final tp2 = TextPainter(
      text: TextSpan(text: '/100',
          style: TextStyle(color: color.withOpacity(0.55), fontSize: 9,
              fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp2.paint(canvas, Offset(c.dx - tp2.width / 2, c.dy + tp.height / 2 - 3));
  }

  @override
  bool shouldRepaint(_GaugePainter o) =>
      o.progress != progress || o.score != score;
}
