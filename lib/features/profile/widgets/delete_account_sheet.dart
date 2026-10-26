// lib/features/profile/widgets/delete_account_sheet.dart
//
// 3.9.0 — "Why are you leaving?" before an account is deleted: ready-made
// reasons plus an optional message. The answer is kept with the security
// archive of the deleted account (admin dashboard → Deleted accounts).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';

class DeleteReason {
  const DeleteReason(this.code, this.text);
  final String code;
  final String text;
}

class _Reason {
  const _Reason(this.code, this.label, this.icon);
  final String code;
  final String label;
  final IconData icon;
}

const _reasons = [
  _Reason('not_useful', "I don't find NOVA X useful", Icons.sentiment_dissatisfied_rounded),
  _Reason('found_alternative', 'I found another browser / app', Icons.swap_horiz_rounded),
  _Reason('privacy', 'Privacy or data concerns', Icons.privacy_tip_outlined),
  _Reason('too_many_notifications', 'Too many notifications', Icons.notifications_off_outlined),
  _Reason('bugs', 'Bugs or the app is slow', Icons.bug_report_outlined),
  _Reason('hard_to_use', 'It is hard to use', Icons.help_outline_rounded),
  _Reason('new_account', "I'm creating a new account", Icons.person_add_alt_1_outlined),
  _Reason('temporary', 'Taking a break', Icons.pause_circle_outline_rounded),
  _Reason('other', 'Something else', Icons.more_horiz_rounded),
];

/// Returns the reason, or null when the user kept the account.
Future<DeleteReason?> showDeleteAccountSheet(BuildContext context) {
  return showModalBottomSheet<DeleteReason>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _DeleteAccountSheet(),
  );
}

class _DeleteAccountSheet extends StatefulWidget {
  const _DeleteAccountSheet();
  @override
  State<_DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<_DeleteAccountSheet> {
  String? _code;
  final _text = TextEditingController();
  bool _ack = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _valid =>
      _code != null && _ack && (_code != 'other' || _text.text.trim().length >= 3);

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
        decoration: const BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 10, 20, bottom + 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: AppTheme.divider, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.danger.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_remove_alt_1_rounded, color: AppTheme.danger, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text("We're sorry to see you go",
                      style: GoogleFonts.spaceGrotesk(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('Tell us why you are deleting your NOVA X account.',
                      style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12.5)),
                ]),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: AppTheme.textHint),
              ),
            ]),
            const SizedBox(height: 16),
            for (final r in _reasons) _reasonTile(r),
            const SizedBox(height: 10),
            TextField(
              controller: _text,
              maxLines: 4,
              minLines: 3,
              maxLength: 1000,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.inter(color: Colors.white, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: _code == 'other'
                    ? 'Please tell us the reason (required)'
                    : 'Anything else you would like to tell us? (optional)',
                hintStyle: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 13),
                filled: true,
                fillColor: AppTheme.bgInput,
                counterStyle: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 10.5),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppTheme.accentCyan),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.danger.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.danger.withOpacity(0.25)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('What will be deleted',
                    style: GoogleFonts.inter(
                        color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  'Your profile and login, business listings, synced bookmarks, NOVA AI chat history, '
                  'reward coins, streaks and unlocks, support tickets and notifications. A premium '
                  'subscription is not refunded. For security, a record of the deletion (name, email, '
                  'date, reason and recent activity) is kept by NOVA X for up to 12 months.',
                  style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 11.5, height: 1.45),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _ack = !_ack),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Checkbox(
                    value: _ack,
                    onChanged: (v) => setState(() => _ack = v ?? false),
                    activeColor: AppTheme.danger,
                    side: const BorderSide(color: AppTheme.textHint),
                  ),
                  Expanded(
                    child: Text('I understand this cannot be undone.',
                        style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12.5)),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: AppTheme.glassBorder),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Keep account', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _valid
                      ? () => Navigator.of(context).pop(DeleteReason(_code!, _text.text.trim()))
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.danger,
                    disabledBackgroundColor: AppTheme.danger.withOpacity(0.25),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white54,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Continue', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _reasonTile(_Reason r) {
    final selected = _code == r.code;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _code = r.code),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppTheme.danger.withOpacity(0.08) : AppTheme.bgElevated.withOpacity(0.5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? AppTheme.danger.withOpacity(0.6) : AppTheme.glassBorder),
          ),
          child: Row(children: [
            Icon(r.icon, color: selected ? AppTheme.danger : AppTheme.textHint, size: 19),
            const SizedBox(width: 12),
            Expanded(
              child: Text(r.label,
                  style: GoogleFonts.inter(
                      color: selected ? Colors.white : AppTheme.textSecondary,
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
            ),
            Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: selected ? AppTheme.danger : AppTheme.textHint, size: 19),
          ]),
        ),
      ),
    );
  }
}
