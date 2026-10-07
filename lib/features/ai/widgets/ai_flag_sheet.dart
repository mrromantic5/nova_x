// lib/features/ai/widgets/ai_flag_sheet.dart
//
// NOVA X — AI Content Report Bottom Sheet
// 3-step modal: choose reason → add detail → confirmation
// Google Play AI-Generated Content Policy compliance.
// v1.0.1 — verified clean (apostrophe bug fixed, animation simplified)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import 'package:nova_x/core/services/ai_flag_service.dart';

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
  // Steps: 0 = select reason | 1 = add detail | 2 = result
  int             _step       = 0;
  bool            _submitting = false;
  bool            _success    = false;
  AiFlagCategory? _selected;

  final TextEditingController _detailCtrl = TextEditingController();

  @override
  void dispose() {
    _detailCtrl.dispose();
    super.dispose();
  }

  // ── Submit ─────────────────────────────────────────────────────────────────
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
    setState(() {
      _submitting = false;
      _success    = ok;
      _step       = 2;
    });
    HapticFeedback.lightImpact();
  }

  void _next() {
    if (_step == 0 && _selected == null) return;
    setState(() => _step++);
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: EdgeInsets.only(bottom: keyboardHeight),
      decoration: const BoxDecoration(
        color:        AppTheme.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      // AnimatedSwitcher provides step transition
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: _buildStep(),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _StepSelectReason(
          key:      const ValueKey<int>(0),
          selected: _selected,
          onSelect: (c) => setState(() => _selected = c),
          onNext:   _next,
          onClose:  () => Navigator.pop(context),
        );
      case 1:
        return _StepAddDetail(
          key:        const ValueKey<int>(1),
          category:   _selected!,
          controller: _detailCtrl,
          submitting: _submitting,
          onBack:     _back,
          onSubmit:   _submit,
        );
      default:
        return _StepResult(
          key:     const ValueKey<int>(2),
          success: _success,
          onClose: () => Navigator.pop(context),
        );
    }
  }
}

// ─── Step 0 — Choose a reason ─────────────────────────────────────────────
class _StepSelectReason extends StatelessWidget {
  final AiFlagCategory?             selected;
  final ValueChanged<AiFlagCategory> onSelect;
  final VoidCallback                onNext;
  final VoidCallback                onClose;

  const _StepSelectReason({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onNext,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final hasSelection = selected != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        _Handle(),
        const SizedBox(height: 20),

        // Header row
        Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color:        const Color(0xFF1A0A0A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppTheme.danger.withOpacity(0.35), width: 1.2),
            ),
            child: const Icon(Icons.flag_rounded,
                color: AppTheme.danger, size: 20),
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
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded,
                  color: AppTheme.textHint, size: 20),
            ),
          ),
        ]),

        const SizedBox(height: 18),
        // Using double-quoted string to safely include the apostrophe character
        Text("What's the issue?",
            style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 10),

        // Category list
        Flexible(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: AiFlagService.categories.map((cat) {
                final isSelected = selected?.key == cat.key;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onSelect(cat);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    margin:  const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.danger.withOpacity(0.11)
                          : AppTheme.bgElevated,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.danger.withOpacity(0.55)
                            : AppTheme.divider,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(children: [
                      Text(cat.emoji,
                          style: const TextStyle(fontSize: 19)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(cat.label,
                              style: GoogleFonts.inter(
                                  color: isSelected
                                      ? Colors.white
                                      : AppTheme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 1),
                          Text(cat.description,
                              style: GoogleFonts.inter(
                                  color: AppTheme.textHint,
                                  fontSize: 11)),
                        ],
                      )),
                      if (isSelected)
                        const Icon(Icons.check_circle_rounded,
                            color: AppTheme.danger, size: 18),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Continue button
        _PrimaryButton(
          label:   'Continue',
          enabled: hasSelection,
          onTap:   onNext,
        ),
      ]),
    );
  }
}

// ─── Step 1 — Add detail ──────────────────────────────────────────────────
class _StepAddDetail extends StatelessWidget {
  final AiFlagCategory        category;
  final TextEditingController controller;
  final bool                  submitting;
  final VoidCallback          onBack;
  final VoidCallback          onSubmit;

  const _StepAddDetail({
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
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _Handle(),
        const SizedBox(height: 20),

        // Back + title
        Row(children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color:        AppTheme.bgElevated,
                borderRadius: BorderRadius.circular(10),
                border:       Border.all(color: AppTheme.divider),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: AppTheme.textSecondary, size: 14),
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

        // Selected reason pill
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color:        AppTheme.danger.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
            border:       Border.all(
                color: AppTheme.danger.withOpacity(0.30), width: 1.2),
          ),
          child: Row(children: [
            Text(category.emoji,
                style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Text(category.label,
                style: GoogleFonts.inter(
                    color: AppTheme.danger,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 14),

        Align(
          alignment: Alignment.centerLeft,
          child: Text('Additional context (optional)',
              style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ),
        const SizedBox(height: 8),

        // Detail text field
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
            style:       GoogleFonts.inter(color: Colors.white, fontSize: 14),
            decoration:  InputDecoration(
              border:           InputBorder.none,
              hintText:         'Describe the issue in more detail\u2026',
              hintStyle:        GoogleFonts.inter(
                  color: AppTheme.textHint, fontSize: 13),
              contentPadding:   const EdgeInsets.all(14),
              counterStyle:     GoogleFonts.inter(
                  color: AppTheme.textHint, fontSize: 10),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Privacy note
        Row(children: [
          const Icon(Icons.lock_outline_rounded,
              color: AppTheme.textHint, size: 12),
          const SizedBox(width: 6),
          Expanded(child: Text(
              'Your report is private. Our team reviews all reports within 24h.',
              style: GoogleFonts.inter(
                  color: AppTheme.textHint, fontSize: 11))),
        ]),
        const SizedBox(height: 18),

        // Submit button
        GestureDetector(
          onTap: submitting ? null : onSubmit,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE53935), Color(0xFFFF6B6B)],
                begin:  Alignment.centerLeft,
                end:    Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color:      const Color(0xFFE53935).withOpacity(0.28),
                  blurRadius: 16,
                  offset:     const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: submitting
                  ? const SizedBox(
                      width:  20, height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.2))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.send_rounded,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 8),
                      Text('Submit Report',
                          style: GoogleFonts.spaceGrotesk(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                    ]),
            ),
          ),
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
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 44),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color:  color.withOpacity(0.12),
            shape:  BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.40), width: 2),
          ),
          child: Icon(
            success ? Icons.check_rounded : Icons.error_outline_rounded,
            color: color, size: 36,
          ),
        ),
        const SizedBox(height: 20),

        Text(
          success ? 'Report Submitted' : 'Submission Failed',
          style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),

        Text(
          success
              // FIX: use escaped apostrophes inside double-quoted strings
              ? "Thank you for helping keep NOVA X safe.\nOur team will review your report within 24 hours."
              : "We couldn't send your report right now.\nPlease check your connection and try again.",
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
              color: AppTheme.textSecondary, fontSize: 14, height: 1.6),
        ),

        if (success) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color:        AppTheme.bgElevated,
              borderRadius: BorderRadius.circular(12),
              border:       Border.all(color: AppTheme.divider),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.shield_outlined,
                  color: AppTheme.accentCyan, size: 16),
              const SizedBox(width: 8),
              Text('Your identity is kept private',
                  style: GoogleFonts.inter(
                      color: AppTheme.textSecondary, fontSize: 12)),
            ]),
          ),
        ],

        const SizedBox(height: 28),

        // Done button
        GestureDetector(
          onTap: onClose,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
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

// ─── Shared sub-widgets ────────────────────────────────────────────────────
class _Handle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 40, height: 4,
      decoration: BoxDecoration(
        color:        AppTheme.divider,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

class _PrimaryButton extends StatelessWidget {
  final String     label;
  final bool       enabled;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width:   double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(
                  colors: [Color(0xFFE53935), Color(0xFFFF6B6B)],
                  begin:  Alignment.centerLeft,
                  end:    Alignment.centerRight)
              : null,
          color:        enabled ? null : AppTheme.bgElevated,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(label,
              style: GoogleFonts.spaceGrotesk(
                  color: enabled ? Colors.white : AppTheme.textHint,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
