// lib/features/support/screens/new_ticket_screen.dart
//
// 3.9.0 — write to the NOVA X team. Pops with the new ticket id.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/app_info.dart';
import '../../../core/services/device_clock.dart';
import '../../../core/services/platform_api.dart';
import '../../../core/theme/app_theme.dart';
import '../support_data.dart';
import '../widgets/support_widgets.dart';

class NewTicketScreen extends StatefulWidget {
  const NewTicketScreen({super.key, this.subject, this.message, this.category});
  final String? subject;
  final String? message;
  final String? category;

  @override
  State<NewTicketScreen> createState() => _NewTicketScreenState();
}

class _NewTicketScreenState extends State<NewTicketScreen> {
  late final _subject = TextEditingController(text: widget.subject ?? '');
  late final _message = TextEditingController(text: widget.message ?? '');
  late String _category = supportCategories.any((c) => c.key == widget.category) ? widget.category! : '';
  bool _diagnostics = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    AppInfo.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  bool get _valid =>
      _category.isNotEmpty && _subject.text.trim().length >= 3 && _message.text.trim().length >= 10;

  String get _deviceInfo =>
      '${AppInfo.label} · ${DeviceClock.timeZoneId ?? 'UTC${DeviceClock.offsetLabel()}'}';

  Future<void> _send() async {
    if (!_valid || _sending) return;
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    try {
      final r = await PlatformApi.createTicket(
        category: _category,
        subject: _subject.text.trim(),
        message: _message.text.trim(),
        appVersion: _diagnostics ? AppInfo.version : null,
        deviceInfo: _diagnostics ? _deviceInfo : null,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _SentDialog(ticketNo: r.ticketNo),
      );
      if (mounted) Navigator.of(context).pop(r.id);
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
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Contact support', style: GoogleFonts.spaceGrotesk(
            color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Text('Tell us what you need and the NOVA X team will reply here — you will also get a notification.',
                style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.45)),
            const SizedBox(height: 18),
            const SupportSectionLabel('TOPIC'),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in supportCategories) _categoryChip(c),
            ]),
            const SizedBox(height: 20),
            const SupportSectionLabel('SUBJECT'),
            const SizedBox(height: 8),
            _field(_subject, 'Short summary, e.g. "Premium not active after payment"', maxLength: 160),
            const SizedBox(height: 14),
            const SupportSectionLabel('MESSAGE'),
            const SizedBox(height: 8),
            _field(_message,
                'Describe what happened, what you expected, and anything you already tried. '
                'For payments include the payment reference.',
                maxLength: 4000, lines: 7),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.divider),
              ),
              child: SwitchListTile(
                value: _diagnostics,
                onChanged: (v) => setState(() => _diagnostics = v),
                activeColor: AppTheme.accentCyan,
                title: Text('Include app details', style: GoogleFonts.inter(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text(_deviceInfo, style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11)),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.lock_outline_rounded, color: AppTheme.textHint, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Only the NOVA X support team can read your ticket. Never share passwords.',
                    style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11)),
              ),
            ]),
            const SizedBox(height: 20),
            SupportPrimaryButton(
              icon: Icons.send_rounded,
              label: 'Send to support',
              busy: _sending,
              onTap: _valid ? _send : null,
            ),
            if (!_valid)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _category.isEmpty
                      ? 'Choose a topic to continue.'
                      : 'Add a subject and a message of at least 10 characters.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11.5),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _categoryChip(SupportCategory c) {
    final on = _category == c.key;
    return GestureDetector(
      onTap: () => setState(() => _category = c.key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: on ? AppTheme.accentCyan.withOpacity(0.14) : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? AppTheme.accentCyan : AppTheme.divider),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(c.icon, size: 16, color: on ? AppTheme.accentCyan : AppTheme.textHint),
          const SizedBox(width: 6),
          Text(c.label, style: GoogleFonts.inter(
              color: on ? Colors.white : AppTheme.textSecondary, fontSize: 12.5,
              fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
        ]),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, {int maxLength = 160, int lines = 1}) => TextField(
        controller: c,
        maxLength: maxLength,
        minLines: lines,
        maxLines: lines == 1 ? 1 : 14,
        onChanged: (_) => setState(() {}),
        style: GoogleFonts.inter(color: Colors.white, fontSize: 13.5, height: 1.45),
        decoration: InputDecoration(
          hintText: hint,
          hintMaxLines: 3,
          hintStyle: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12.5),
          filled: true,
          fillColor: AppTheme.bgCard,
          counterStyle: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 10.5),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppTheme.accentCyan),
          ),
        ),
      );
}

class _SentDialog extends StatelessWidget {
  const _SentDialog({required this.ticketNo});
  final String ticketNo;

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
              child: const Icon(Icons.mark_email_read_rounded, color: AppTheme.success, size: 30),
            ),
            const SizedBox(height: 16),
            Text('Ticket sent', style: GoogleFonts.spaceGrotesk(
                color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(ticketNo, style: GoogleFonts.robotoMono(color: AppTheme.accentCyan, fontSize: 14)),
            const SizedBox(height: 10),
            Text("We'll reply within 24 hours. You'll get a notification, and the reply will be in Support → Inbox.",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.45)),
            const SizedBox(height: 18),
            SupportPrimaryButton(icon: Icons.check_rounded, label: 'Done', onTap: () => Navigator.pop(context)),
          ]),
        ),
      );
}
