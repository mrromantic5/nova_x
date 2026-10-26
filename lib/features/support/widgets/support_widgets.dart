// lib/features/support/widgets/support_widgets.dart
//
// 3.9.0 — shared building blocks of the Support and Issue report pages.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/platform_api.dart';
import '../../../core/theme/app_theme.dart';
import '../support_data.dart';

/// "just now", "5 min ago", "Yesterday 14:05", "12 Oct, 09:30" (local time).
String supportWhen(DateTime? t, {DateTime? now}) {
  if (t == null) return '';
  final n = now ?? DateTime.now();
  final d = n.difference(t);
  String hm(DateTime x) => '${x.hour.toString().padLeft(2, '0')}:${x.minute.toString().padLeft(2, '0')}';
  if (d.inSeconds < 60 && !d.isNegative) return 'just now';
  if (d.inMinutes < 60 && !d.isNegative) return '${d.inMinutes} min ago';
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(t.year, t.month, t.day);
  final days = today.difference(day).inDays;
  if (days == 0) return 'Today ${hm(t)}';
  if (days == 1) return 'Yesterday ${hm(t)}';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final y = t.year == n.year ? '' : ' ${t.year}';
  return '${t.day} ${months[t.month - 1]}$y, ${hm(t)}';
}

SnackBar supportSnack(String text, {bool error = false}) => SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
            color: error ? AppTheme.warning : AppTheme.success, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: GoogleFonts.inter(color: Colors.white, fontSize: 13))),
      ]),
      backgroundColor: AppTheme.bgElevated,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      duration: const Duration(seconds: 3),
    );

class SupportHeader extends StatelessWidget {
  const SupportHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.first.withOpacity(0.38), colors.last.withOpacity(0.18), AppTheme.bgDark],
        ),
      ),
      padding: EdgeInsets.fromLTRB(20, top + 50, 20, 70),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: colors),
            boxShadow: [BoxShadow(color: colors.first.withOpacity(0.45), blurRadius: 18)],
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.spaceGrotesk(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12, height: 1.4)),
          ]),
        ),
      ]),
    );
  }
}

class SupportSegmentItem {
  const SupportSegmentItem(this.icon, this.label, {this.badge = 0, this.count});
  final IconData icon;
  final String label;

  /// Unread (shown as a red dot with the number).
  final int badge;

  /// Total (shown greyed).
  final int? count;
}

class SupportSegments extends StatelessWidget {
  const SupportSegments({super.key, required this.index, required this.items, required this.onChanged});
  final int index;
  final List<SupportSegmentItem> items;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Row(children: [
        for (var i = 0; i < items.length; i++)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  gradient: i == index ? AppTheme.primaryGradient : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(items[i].icon, size: 16, color: i == index ? Colors.white : AppTheme.textHint),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(items[i].label,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            color: i == index ? Colors.white : AppTheme.textSecondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                  ),
                  if (items[i].badge > 0) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: AppTheme.danger, borderRadius: BorderRadius.circular(10)),
                      child: Text('${items[i].badge}', style: GoogleFonts.inter(
                          color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                  ] else if ((items[i].count ?? 0) > 0) ...[
                    const SizedBox(width: 5),
                    Text('${items[i].count}', style: GoogleFonts.inter(
                        color: i == index ? Colors.white70 : AppTheme.textHint,
                        fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

class SupportSectionLabel extends StatelessWidget {
  const SupportSectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: GoogleFonts.inter(
          color: AppTheme.textHint, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2));
}

class SupportSearchField extends StatelessWidget {
  const SupportSearchField({super.key, required this.controller, required this.hint, required this.onChanged});
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        style: GoogleFonts.inter(color: Colors.white, fontSize: 13.5),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textHint, size: 20),
          hintText: hint,
          hintStyle: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 13),
          filled: true,
          fillColor: AppTheme.bgCard,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppTheme.accentCyan),
          ),
        ),
      );
}

class SupportChipButton extends StatelessWidget {
  const SupportChipButton({super.key, required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: color, size: 15),
              const SizedBox(width: 6),
              Text(label, style: GoogleFonts.inter(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}

class SupportPrimaryButton extends StatelessWidget {
  const SupportPrimaryButton({super.key, required this.icon, required this.label, required this.onTap, this.busy = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: onTap == null ? null : AppTheme.primaryGradient,
            color: onTap == null ? AppTheme.bgElevated : null,
            borderRadius: BorderRadius.circular(14),
          ),
          child: ElevatedButton.icon(
            onPressed: busy ? null : onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white54,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(icon, size: 19),
            label: Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
        ),
      );
}

class SupportStat extends StatelessWidget {
  const SupportStat({super.key, required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Column(children: [
          Icon(icon, color: AppTheme.accentCyan, size: 18),
          const SizedBox(height: 6),
          Text(value, style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w800)),
          Text(label, style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 10.5)),
        ]),
      );
}

class SupportEmptyState extends StatelessWidget {
  const SupportEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(32, 60, 32, 40),
        children: [
          Center(
            child: Container(
              width: 76, height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.accentCyan.withOpacity(0.08),
                border: Border.all(color: AppTheme.accentCyan.withOpacity(0.25)),
              ),
              child: Icon(icon, color: AppTheme.accentCyan, size: 34),
            ),
          ),
          const SizedBox(height: 18),
          Text(title, textAlign: TextAlign.center, style: GoogleFonts.spaceGrotesk(
              color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: GoogleFonts.inter(
              color: AppTheme.textSecondary, fontSize: 12.5, height: 1.5)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            Center(
              child: OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accentCyan,
                  side: const BorderSide(color: AppTheme.accentCyan),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(actionLabel!, style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ],
      );
}

/// open / answered / pending / closed, or an issue report status.
class SupportStatusPill extends StatelessWidget {
  const SupportStatusPill(this.status, {super.key});
  final String status;

  static (String, Color) look(String s) => switch (s) {
        'open' => ('Awaiting reply', AppTheme.warning),
        'pending' => ('In progress', AppTheme.accentPurple),
        'answered' => ('Answered', AppTheme.success),
        'closed' => ('Closed', AppTheme.textHint),
        'new' => ('Received', AppTheme.accentCyan),
        'reviewing' => ('Reviewing', AppTheme.accentPurple),
        'resolved' => ('Fixed', AppTheme.success),
        'wont_fix' => ('Closed', AppTheme.textHint),
        _ => (s, AppTheme.textHint),
      };

  @override
  Widget build(BuildContext context) {
    final (label, color) = look(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(label, style: GoogleFonts.inter(color: color, fontSize: 10.5, fontWeight: FontWeight.w800)),
    );
  }
}

class SupportTicketCard extends StatelessWidget {
  const SupportTicketCard({super.key, required this.ticket, required this.inbox, required this.onTap});
  final SupportTicket ticket;
  final bool inbox;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    final unread = t.userUnread > 0;
    final cat = supportCategories.firstWhere((c) => c.key == t.category, orElse: () => supportCategories.last);
    final preview = (t.lastMessage ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final who = switch (t.lastSender) { 'admin' => 'NOVA Support: ', 'user' => 'You: ', _ => '' };
    return Material(
      color: AppTheme.bgCard,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: unread ? AppTheme.accentCyan.withOpacity(0.55) : AppTheme.divider),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: (unread ? AppTheme.accentCyan : AppTheme.primaryBlue).withOpacity(0.13),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(cat.icon, color: unread ? AppTheme.accentCyan : AppTheme.primaryBlue, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(t.subject, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            color: Colors.white, fontSize: 13.5,
                            fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
                  ),
                  const SizedBox(width: 6),
                  Text(supportWhen(t.lastMessageAt),
                      style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 10.5)),
                ]),
                const SizedBox(height: 4),
                if (preview.isNotEmpty)
                  Text('$who$preview', maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          color: unread ? AppTheme.textPrimary : AppTheme.textSecondary,
                          fontSize: 12, height: 1.35)),
                const SizedBox(height: 8),
                Row(children: [
                  SupportStatusPill(t.status),
                  const SizedBox(width: 8),
                  Text(t.ticketNo, style: GoogleFonts.robotoMono(color: AppTheme.textHint, fontSize: 10.5)),
                  const Spacer(),
                  if (unread)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: AppTheme.danger, borderRadius: BorderRadius.circular(10)),
                      child: Text('${t.userUnread} new', style: GoogleFonts.inter(
                          color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
