// lib/features/support/screens/issue_report_screen.dart
//
// 3.9.0 — Report an issue. Reports go straight to the NOVA X team (admin
// dashboard → Issue reports). No replies: the Outbox shows what you sent and
// its status (Received → Reviewing → Fixed).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/app_info.dart';
import '../../../core/services/device_clock.dart';
import '../../../core/services/platform_api.dart';
import '../../../core/theme/app_theme.dart';
import '../support_data.dart';
import '../widgets/support_widgets.dart';

class IssueReportScreen extends StatefulWidget {
  const IssueReportScreen({super.key});
  @override
  State<IssueReportScreen> createState() => _IssueReportScreenState();
}

class _IssueReportScreenState extends State<IssueReportScreen> {
  int _tab = 0; // 0 = new report, 1 = outbox

  final _title = TextEditingController();
  final _description = TextEditingController();
  final _steps = TextEditingController();
  String _category = '';
  String _severity = 'medium';
  bool _diagnostics = true;
  bool _sending = false;

  bool _loggedIn = false;
  bool _loadingOutbox = true;
  String? _outboxError;
  List<IssueReport> _reports = const [];

  static const _severities = [
    ('low', 'Low', 'Small or cosmetic', AppTheme.success),
    ('medium', 'Medium', 'Annoying, has a workaround', AppTheme.accentCyan),
    ('high', 'High', 'A feature does not work', AppTheme.warning),
    ('critical', 'Critical', 'Crash or data loss', AppTheme.danger),
  ];

  @override
  void initState() {
    super.initState();
    AppInfo.load().then((_) {
      if (mounted) setState(() {});
    });
    _init();
  }

  Future<void> _init() async {
    _loggedIn = await ApiService.isLoggedIn();
    await _loadOutbox();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _steps.dispose();
    super.dispose();
  }

  Future<void> _loadOutbox() async {
    if (!_loggedIn) {
      if (mounted) setState(() => _loadingOutbox = false);
      return;
    }
    try {
      final r = await PlatformApi.issues();
      if (mounted) {
        setState(() {
          _reports = r;
          _outboxError = null;
          _loadingOutbox = false;
        });
      }
    } on NovaServiceError catch (e) {
      if (mounted) {
        setState(() {
          _outboxError = e.message;
          _loadingOutbox = false;
        });
      }
    }
  }

  bool get _valid =>
      _category.isNotEmpty && _title.text.trim().length >= 3 && _description.text.trim().length >= 10;

  String get _deviceInfo =>
      '${AppInfo.label} · ${DeviceClock.timeZoneId ?? 'UTC${DeviceClock.offsetLabel()}'}';

  Future<void> _submit() async {
    if (!_valid || _sending) return;
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    try {
      final r = await PlatformApi.reportIssue(
        category: _category,
        severity: _severity,
        title: _title.text.trim(),
        description: _description.text.trim(),
        steps: _steps.text,
        appVersion: _diagnostics ? AppInfo.version : null,
        deviceInfo: _diagnostics ? _deviceInfo : null,
      );
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (_) => _ReportedDialog(reportNo: r.reportNo));
      if (!mounted) return;
      _title.clear();
      _description.clear();
      _steps.clear();
      setState(() {
        _category = '';
        _severity = 'medium';
        if (_loggedIn) _tab = 1;
      });
      _loadOutbox();
    } on NovaServiceError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(supportSnack(e.message, error: true));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            pinned: true,
            expandedHeight: 168,
            backgroundColor: AppTheme.bgDark,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: const FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: SupportHeader(
                icon: Icons.bug_report_rounded,
                title: 'Report an Issue',
                subtitle: 'Found a bug? Tell the NOVA X team so we can fix it in the next update.',
                colors: [AppTheme.warning, AppTheme.danger],
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(58),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: SupportSegments(
                  index: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                  items: [
                    const SupportSegmentItem(Icons.add_circle_outline_rounded, 'New report'),
                    SupportSegmentItem(Icons.outbox_rounded, 'Outbox', count: _reports.length),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _tab == 0 ? _form() : _outbox(),
        ),
      ),
    );
  }

  Widget _form() => ListView(
        key: const ValueKey('form'),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        children: [
          const SupportSectionLabel('WHAT IS AFFECTED?'),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.35,
            children: [for (final c in issueCategories) _categoryTile(c)],
          ),
          const SizedBox(height: 20),
          const SupportSectionLabel('HOW SERIOUS IS IT?'),
          const SizedBox(height: 10),
          for (final s in _severities) _severityTile(s.$1, s.$2, s.$3, s.$4),
          const SizedBox(height: 16),
          const SupportSectionLabel('TITLE'),
          const SizedBox(height: 8),
          _field(_title, 'e.g. "Music stops when the screen turns off"', maxLength: 160),
          const SizedBox(height: 10),
          const SupportSectionLabel('WHAT HAPPENED?'),
          const SizedBox(height: 8),
          _field(_description, 'Describe the problem and what you expected to happen.', maxLength: 5000, lines: 5),
          const SizedBox(height: 10),
          const SupportSectionLabel('STEPS TO REPRODUCE (OPTIONAL)'),
          const SizedBox(height: 8),
          _field(_steps, '1. Open …\n2. Tap …\n3. …', maxLength: 3000, lines: 4),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.divider),
            ),
            child: SwitchListTile(
              value: _diagnostics,
              onChanged: (v) => setState(() => _diagnostics = v),
              activeColor: AppTheme.warning,
              title: Text('Include app details', style: GoogleFonts.inter(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text(_deviceInfo, style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11)),
            ),
          ),
          const SizedBox(height: 18),
          SupportPrimaryButton(
            icon: Icons.send_rounded,
            label: 'Submit report',
            busy: _sending,
            onTap: _valid ? _submit : null,
          ),
          if (!_valid)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _category.isEmpty
                    ? 'Choose what is affected to continue.'
                    : 'Add a title and a description of at least 10 characters.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11.5),
              ),
            ),
          const SizedBox(height: 14),
          Row(children: [
            const Icon(Icons.info_outline_rounded, color: AppTheme.textHint, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Issue reports are not answered one by one. For a reply, use Contact Support.',
                  style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11)),
            ),
          ]),
        ],
      );

  Widget _categoryTile(SupportCategory c) {
    final on = _category == c.key;
    return GestureDetector(
      onTap: () => setState(() => _category = c.key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: on ? AppTheme.warning.withOpacity(0.13) : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? AppTheme.warning : AppTheme.divider, width: on ? 1.4 : 1),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(c.icon, color: on ? AppTheme.warning : AppTheme.textHint, size: 22),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(c.label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    color: on ? Colors.white : AppTheme.textSecondary, fontSize: 11,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
          ),
        ]),
      ),
    );
  }

  Widget _severityTile(String key, String label, String hint, Color color) {
    final on = _severity == key;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _severity = key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: on ? color.withOpacity(0.10) : AppTheme.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: on ? color : AppTheme.divider),
          ),
          child: Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 12),
            Text(label, style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Expanded(child: Text(hint, style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11.5))),
            Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: on ? color : AppTheme.textHint, size: 18),
          ]),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, {int maxLength = 160, int lines = 1}) => TextField(
        controller: c,
        maxLength: maxLength,
        minLines: lines,
        maxLines: lines == 1 ? 1 : 12,
        onChanged: (_) => setState(() {}),
        style: GoogleFonts.inter(color: Colors.white, fontSize: 13.5, height: 1.45),
        decoration: InputDecoration(
          hintText: hint,
          hintMaxLines: 4,
          hintStyle: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12.5),
          filled: true,
          fillColor: AppTheme.bgCard,
          counterStyle: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 10.5),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppTheme.warning),
          ),
        ),
      );

  Widget _outbox() {
    if (!_loggedIn) {
      return const SupportEmptyState(
        key: ValueKey('guest'),
        icon: Icons.lock_person_rounded,
        title: 'Sign in to see your reports',
        message: 'You can send reports without an account, but only signed-in reports are listed here.',
      );
    }
    if (_loadingOutbox) {
      return const Center(key: ValueKey('loading'), child: CircularProgressIndicator(color: AppTheme.warning));
    }
    if (_outboxError != null && _reports.isEmpty) {
      return SupportEmptyState(
        key: const ValueKey('error'),
        icon: Icons.wifi_off_rounded,
        title: "Couldn't load your reports",
        message: _outboxError!,
        actionLabel: 'Try again',
        onAction: () {
          setState(() => _loadingOutbox = true);
          _loadOutbox();
        },
      );
    }
    if (_reports.isEmpty) {
      return SupportEmptyState(
        key: const ValueKey('empty'),
        icon: Icons.outbox_rounded,
        title: 'No reports yet',
        message: 'Issues you report appear here with their status.',
        actionLabel: 'Report an issue',
        onAction: () => setState(() => _tab = 0),
      );
    }
    return RefreshIndicator(
      key: const ValueKey('list'),
      color: AppTheme.warning,
      backgroundColor: AppTheme.bgCard,
      onRefresh: _loadOutbox,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        itemCount: _reports.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _reportCard(_reports[i]),
      ),
    );
  }

  Widget _reportCard(IssueReport r) {
    final cat = issueCategories.firstWhere((c) => c.key == r.category, orElse: () => issueCategories.last);
    final sev = _severities.firstWhere((s) => s.$1 == r.severity, orElse: () => _severities[1]);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: sev.$4.withOpacity(0.13),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(cat.icon, color: sev.$4, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('${cat.label} · ${sev.$2} · ${supportWhen(r.createdAt)}',
                style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11)),
            const SizedBox(height: 8),
            Row(children: [
              SupportStatusPill(r.status),
              const SizedBox(width: 8),
              Text(r.reportNo, style: GoogleFonts.robotoMono(color: AppTheme.textHint, fontSize: 10.5)),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _ReportedDialog extends StatelessWidget {
  const _ReportedDialog({required this.reportNo});
  final String reportNo;

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.success.withOpacity(0.14),
                border: Border.all(color: AppTheme.success.withOpacity(0.4)),
              ),
              child: const Icon(Icons.task_alt_rounded, color: AppTheme.success, size: 30),
            ),
            const SizedBox(height: 16),
            Text('Report received', style: GoogleFonts.spaceGrotesk(
                color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(reportNo, style: GoogleFonts.robotoMono(color: AppTheme.warning, fontSize: 14)),
            const SizedBox(height: 10),
            Text('Thank you! The NOVA X team reviews every report. Fixes arrive in app updates.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.45)),
            const SizedBox(height: 18),
            SupportPrimaryButton(icon: Icons.check_rounded, label: 'Done', onTap: () => Navigator.pop(context)),
          ]),
        ),
      );
}
