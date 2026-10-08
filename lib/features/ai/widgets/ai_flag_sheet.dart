// lib/features/ai/widgets/ai_flag_sheet.dart
//
// NOVA X — AI Content Report Bottom Sheet
// SaaS-grade professional design with Font Awesome icons.
// Google Play AI-Generated Content Policy compliance.
// v2.0.0 — Font Awesome, no emojis, verified clean

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/services/ai_flag_service.dart';
import 'package:nova_x/core/theme/app_theme.dart';

/// Show the AI content report sheet.
/// [contentType] — 'text' | 'image' | 'video'
/// [contentRef]  — URL for images/videos, or a text snippet (<=500 chars)
Future<void> showAiFlagSheet(
  BuildContext context, {
  required String contentType,
  String?         contentRef,
}) {
  return showModalBottomSheet<void>(
    context:            context,
    isScrollControlled: true,
    backgroundColor:    Colors.transparent,
    useSafeArea:        true,
    builder: (_) => _AiFlagSheet(
      contentType: contentType,
      contentRef:  contentRef,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
class _AiFlagSheet extends StatefulWidget {
  final String  contentType;
  final String? contentRef;
  const _AiFlagSheet({required this.contentType, this.contentRef});

  @override
  State<_AiFlagSheet> createState() => _AiFlagSheetState();
}

class _AiFlagSheetState extends State<_AiFlagSheet> {
  int             _step       = 0; // 0=select 1=detail 2=result
  bool            _submitting = false;
  bool            _success    = false;
  AiFlagCategory? _selected;
  final TextEditingController _detailCtrl = TextEditingController();

  @override
  void dispose() {
    _detailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selected == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _submitting = true);
    final detail = _detailCtrl.text.trim();
    final ok = await AiFlagService.submitReport(
      contentType: widget.contentType,
      reasonKey:   _selected!.key,
      reasonLabel: _selected!.label,
      contentRef:  widget.contentRef,
      description: detail.isEmpty ? null : detail,
    );
    if (!mounted) return;
    setState(() { _submitting = false; _success = ok; _step = 2; });
    HapticFeedback.lightImpact();
  }

  void _next() { if (_selected != null) setState(() => _step++); }
  void _back() { if (_step > 0) setState(() => _step--); }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color:        AppTheme.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity:  anim,
          child:    SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end:   Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        child: _buildStep(),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:  return _StepSelect(
        key:      const ValueKey<int>(0),
        selected: _selected,
        onSelect: (c) => setState(() => _selected = c),
        onNext:   _next,
        onClose:  () => Navigator.pop(context),
      );
      case 1:  return _StepDetail(
        key:        const ValueKey<int>(1),
        category:   _selected!,
        controller: _detailCtrl,
        submitting: _submitting,
        onBack:     _back,
        onSubmit:   _submit,
      );
      default: return _StepResult(
        key:     const ValueKey<int>(2),
        success: _success,
        onClose: () => Navigator.pop(context),
      );
    }
  }
}

// ─── Step 0 — Select Reason ───────────────────────────────────────────────
class _StepSelect extends StatelessWidget {
  final AiFlagCategory?             selected;
  final ValueChanged<AiFlagCategory> onSelect;
  final VoidCallback                onNext;
  final VoidCallback                onClose;

  const _StepSelect({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onNext,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [

        // ── Handle bar ──────────────────────────────────────────────────
        Center(
          child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color:        AppTheme.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // ── Header ──────────────────────────────────────────────────────
        Row(children: [
          // Flag icon container — Font Awesome
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color:        const Color(0xFF1A0A0A),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                  color: AppTheme.danger.withOpacity(0.35), width: 1.2),
            ),
            child: const Center(
              child: FaIcon(
                FontAwesomeIcons.flag,
                color: AppTheme.danger,
                size:  18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Report AI Content',
                  style: GoogleFonts.spaceGrotesk(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              Text('Help us keep NOVA X safe for everyone',
                  style: GoogleFonts.inter(
                      color: AppTheme.textHint, fontSize: 12)),
            ],
          )),
          GestureDetector(
            onTap: onClose,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color:        AppTheme.bgElevated,
                borderRadius: BorderRadius.circular(10),
                border:       Border.all(color: AppTheme.divider),
              ),
              child: const Center(
                child: FaIcon(FontAwesomeIcons.xmark,
                    color: AppTheme.textHint, size: 14),
              ),
            ),
          ),
        ]),

        const SizedBox(height: 20),

        // ── Divider ─────────────────────────────────────────────────────
        Container(height: 1, color: AppTheme.divider),
        const SizedBox(height: 16),

        Text("What's the issue?",
            style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2)),
        const SizedBox(height: 12),

        // ── Category list ────────────────────────────────────────────────
        Flexible(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: AiFlagService.categories.map((cat) {
                final isSel = selected?.key == cat.key;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap:    () {
                    HapticFeedback.selectionClick();
                    onSelect(cat);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    margin:  const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSel
                          ? cat.iconColor.withOpacity(0.08)
                          : AppTheme.bgElevated,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: isSel
                            ? cat.iconColor.withOpacity(0.50)
                            : AppTheme.divider,
                        width: isSel ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(children: [
                      // FA icon in colored container
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color:        isSel
                              ? cat.iconColor.withOpacity(0.18)
                              : cat.iconBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: FaIcon(cat.icon,
                              color: cat.iconColor, size: 15),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(cat.label,
                              style: GoogleFonts.inter(
                                  color: isSel
                                      ? Colors.white
                                      : AppTheme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(cat.description,
                              style: GoogleFonts.inter(
                                  color: AppTheme.textHint,
                                  fontSize: 11,
                                  height: 1.3)),
                        ],
                      )),
                      const SizedBox(width: 8),
                      // Checkmark — FA
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 160),
                        opacity:  isSel ? 1.0 : 0.0,
                        child: Container(
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            color:  cat.iconColor,
                            shape:  BoxShape.circle,
                          ),
                          child: const Center(
                            child: FaIcon(FontAwesomeIcons.check,
                                color: Colors.white, size: 10),
                          ),
                        ),
                      ),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // ── Continue button ──────────────────────────────────────────────
        _PrimaryBtn(
          label:   'Continue',
          enabled: selected != null,
          icon:    FontAwesomeIcons.arrowRight,
          onTap:   onNext,
        ),
      ]),
    );
  }
}

// ─── Step 1 — Add Detail ──────────────────────────────────────────────────
class _StepDetail extends StatelessWidget {
  final AiFlagCategory        category;
  final TextEditingController controller;
  final bool                  submitting;
  final VoidCallback          onBack;
  final VoidCallback          onSubmit;

  const _StepDetail({
    super.key,
    required this.category,
    required this.controller,
    required this.submitting,
    required this.onBack,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [

        // Handle
        Center(
          child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color:        AppTheme.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Back + title
        Row(children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color:        AppTheme.bgElevated,
                borderRadius: BorderRadius.circular(10),
                border:       Border.all(color: AppTheme.divider),
              ),
              child: const Center(
                child: FaIcon(FontAwesomeIcons.chevronLeft,
                    color: AppTheme.textSecondary, size: 13),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text('Add More Detail',
              style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 18),

        // Selected category pill
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color:        category.iconColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: category.iconColor.withOpacity(0.30), width: 1.2),
          ),
          child: Row(children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color:        category.iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: FaIcon(category.icon,
                    color: category.iconColor, size: 13),
              ),
            ),
            const SizedBox(width: 10),
            Text(category.label,
                style: GoogleFonts.inter(
                    color: category.iconColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 16),

        // Label
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Additional context (optional)',
              style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ),
        const SizedBox(height: 8),

        // Text field
        Container(
          decoration: BoxDecoration(
            color:        AppTheme.bgElevated,
            borderRadius: BorderRadius.circular(13),
            border:       Border.all(color: AppTheme.divider),
          ),
          child: TextField(
            controller:  controller,
            maxLines:    4,
            maxLength:   500,
            style:       GoogleFonts.inter(
                color: Colors.white, fontSize: 14, height: 1.5),
            decoration: InputDecoration(
              border:         InputBorder.none,
              hintText:       'Describe the issue in more detail\u2026',
              hintStyle:      GoogleFonts.inter(
                  color: AppTheme.textHint, fontSize: 13),
              contentPadding: const EdgeInsets.all(14),
              counterStyle:   GoogleFonts.inter(
                  color: AppTheme.textHint, fontSize: 10),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Privacy note
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color:        AppTheme.bgElevated,
            borderRadius: BorderRadius.circular(10),
            border:       Border.all(color: AppTheme.divider),
          ),
          child: Row(children: [
            const FaIcon(FontAwesomeIcons.shieldHalved,
                color: AppTheme.accentCyan, size: 13),
            const SizedBox(width: 8),
            Expanded(child: Text(
                'Your report is private. Our team reviews all reports within 24 hours.',
                style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    height: 1.4))),
          ]),
        ),
        const SizedBox(height: 18),

        // Submit button
        _PrimaryBtn(
          label:      'Submit Report',
          enabled:    !submitting,
          loading:    submitting,
          icon:       FontAwesomeIcons.paperPlane,
          onTap:      onSubmit,
          isDestructive: true,
        ),
      ]),
    );
  }
}

// ─── Step 2 — Result ──────────────────────────────────────────────────────
class _StepResult extends StatelessWidget {
  final bool         success;
  final VoidCallback onClose;

  const _StepResult({
    super.key,
    required this.success,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final color = success ? AppTheme.success : AppTheme.danger;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 44),
      child: Column(mainAxisSize: MainAxisSize.min, children: [

        // Icon circle
        Container(
          width: 76, height: 76,
          decoration: BoxDecoration(
            color:  color.withOpacity(0.12),
            shape:  BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.35), width: 2),
          ),
          child: Center(
            child: FaIcon(
              success
                  ? FontAwesomeIcons.circleCheck
                  : FontAwesomeIcons.circleExclamation,
              color: color,
              size: 32,
            ),
          ),
        ),
        const SizedBox(height: 20),

        Text(
          success ? 'Report Submitted' : 'Submission Failed',
          style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textPrimary,
              fontSize: 21,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),

        Text(
          success
              ? "Thank you for helping keep NOVA X safe.\nOur team will review your report within 24 hours."
              : "We couldn't send your report right now.\nPlease check your connection and try again.",
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              fontSize: 14,
              height: 1.65),
        ),

        if (success) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color:        AppTheme.bgElevated,
              borderRadius: BorderRadius.circular(12),
              border:       Border.all(color: AppTheme.divider),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const FaIcon(FontAwesomeIcons.userShield,
                  color: AppTheme.accentCyan, size: 13),
              const SizedBox(width: 8),
              Text('Your identity is kept private',
                  style: GoogleFonts.inter(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ]),
          ),
        ],

        const SizedBox(height: 28),

        // Done button
        GestureDetector(
          onTap: onClose,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              color:        AppTheme.bgElevated,
              borderRadius: BorderRadius.circular(14),
              border:       Border.all(color: AppTheme.divider),
            ),
            child: Center(child: Text('Done',
                style: GoogleFonts.spaceGrotesk(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600))),
          ),
        ),
      ]),
    );
  }
}

// ─── Shared: Primary Button ────────────────────────────────────────────────
class _PrimaryBtn extends StatelessWidget {
  final String   label;
  final bool     enabled;
  final bool     loading;
  final IconData icon;
  final VoidCallback onTap;
  final bool     isDestructive;

  const _PrimaryBtn({
    required this.label,
    required this.enabled,
    required this.icon,
    required this.onTap,
    this.loading       = false,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final activeGrad = isDestructive
        ? const LinearGradient(
            colors: [Color(0xFFE53935), Color(0xFFFF6B6B)],
            begin:  Alignment.centerLeft,
            end:    Alignment.centerRight)
        : AppTheme.primaryGradient;

    return GestureDetector(
      onTap: (enabled && !loading) ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width:   double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          gradient:     (enabled && !loading) ? activeGrad : null,
          color:        (enabled && !loading) ? null : AppTheme.bgElevated,
          borderRadius: BorderRadius.circular(16),
          boxShadow:    (enabled && !loading)
              ? [BoxShadow(
                  color: (isDestructive
                          ? const Color(0xFFE53935)
                          : AppTheme.primaryBlue)
                      .withOpacity(0.30),
                  blurRadius: 16,
                  offset: const Offset(0, 4))]
              : null,
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.2))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  FaIcon(icon,
                      color: enabled ? Colors.white : AppTheme.textHint,
                      size:  14),
                  const SizedBox(width: 10),
                  Text(label,
                      style: GoogleFonts.spaceGrotesk(
                          color: enabled
                              ? Colors.white
                              : AppTheme.textHint,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ]),
        ),
      ),
    );
  }
}
