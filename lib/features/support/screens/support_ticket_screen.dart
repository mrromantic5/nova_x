// lib/features/support/screens/support_ticket_screen.dart
//
// 3.9.0 — one support ticket: the conversation with the NOVA X team, a reply
// box (same ticket), and "Close ticket" with an optional rating. Refreshes
// every 15 seconds while open, so team replies show up without reloading.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/platform_api.dart';
import '../../../core/theme/app_theme.dart';
import '../support_data.dart';
import '../widgets/support_widgets.dart';

class SupportTicketScreen extends StatefulWidget {
  const SupportTicketScreen({super.key, required this.ticketId});
  final int ticketId;

  @override
  State<SupportTicketScreen> createState() => _SupportTicketScreenState();
}

class _SupportTicketScreenState extends State<SupportTicketScreen> {
  SupportTicket? _ticket;
  List<SupportMessage> _messages = const [];
  bool _loading = true;
  String? _error;
  bool _sending = false;
  final _reply = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _reply.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final r = await PlatformApi.ticket(widget.ticketId);
      if (!mounted) return;
      final grew = r.messages.length != _messages.length;
      setState(() {
        _ticket = r.ticket;
        _messages = r.messages;
        _loading = false;
        _error = null;
      });
      if (grew) _toBottom();
    } on NovaServiceError catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent || _ticket == null) _error = e.message;
      });
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent + 80,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await PlatformApi.reply(widget.ticketId, text);
      _reply.clear();
      HapticFeedback.lightImpact();
      await _load(silent: true);
    } on NovaServiceError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(supportSnack(e.message, error: true));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _close() async {
    final rating = await showDialog<int>(
      context: context,
      builder: (_) => const _RateDialog(),
    );
    if (rating == null || !mounted) return; // -1 = close without rating
    try {
      await PlatformApi.closeTicket(widget.ticketId, rating: rating > 0 ? rating : null);
      await _load(silent: true);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(supportSnack('Ticket closed. Thank you!'));
    } on NovaServiceError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(supportSnack(e.message, error: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _ticket;
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: t == null
            ? Text('Ticket', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.w800))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.subject, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Row(children: [
                  Text(t.ticketNo, style: GoogleFonts.robotoMono(color: AppTheme.textHint, fontSize: 11)),
                  const SizedBox(width: 8),
                  SupportStatusPill(t.status),
                ]),
              ]),
        actions: [
          if (t != null && !t.isClosed)
            PopupMenuButton<String>(
              color: AppTheme.bgElevated,
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
              onSelected: (v) {
                if (v == 'close') _close();
                if (v == 'refresh') _load();
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'refresh', child: Text('Refresh', style: GoogleFonts.inter(color: Colors.white))),
                PopupMenuItem(value: 'close', child: Text('Close ticket', style: GoogleFonts.inter(color: Colors.white))),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentCyan))
          : _error != null && t == null
              ? SupportEmptyState(
                  icon: Icons.wifi_off_rounded,
                  title: "Couldn't open this ticket",
                  message: _error!,
                  actionLabel: 'Try again',
                  onAction: () {
                    setState(() => _loading = true);
                    _load();
                  },
                )
              : Column(children: [
                  Expanded(
                    child: RefreshIndicator(
                      color: AppTheme.accentCyan,
                      backgroundColor: AppTheme.bgCard,
                      onRefresh: () => _load(silent: true),
                      child: ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
                        children: [
                          if (t != null) _ticketInfo(t),
                          const SizedBox(height: 12),
                          for (final m in _messages) _bubble(m),
                        ],
                      ),
                    ),
                  ),
                  if (t != null) t.isClosed ? _closedBar() : _composer(),
                ]),
    );
  }

  Widget _ticketInfo(SupportTicket t) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, color: AppTheme.textHint, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${supportCategoryLabel(t.category)} · opened ${supportWhen(t.createdAt)}'
              '${t.priority == 'high' ? ' · priority' : ''}',
              style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 11.5),
            ),
          ),
        ]),
      );

  Widget _bubble(SupportMessage m) {
    if (m.sender == 'system') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.bgElevated.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: [
              Text(m.body, textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 11.5, height: 1.4)),
              const SizedBox(height: 3),
              Text(supportWhen(m.createdAt), style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 10)),
            ]),
          ),
        ),
      );
    }
    final mine = m.sender == 'user';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            Container(
              width: 30, height: 30,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppTheme.primaryGradient),
              child: const Icon(Icons.support_agent_rounded, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
              padding: const EdgeInsets.fromLTRB(13, 10, 13, 8),
              decoration: BoxDecoration(
                gradient: mine ? const LinearGradient(colors: [AppTheme.primaryBlue, Color(0xFF1560D6)]) : null,
                color: mine ? null : AppTheme.bgCard,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(mine ? 16 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 16),
                ),
                border: mine ? null : Border.all(color: AppTheme.accentCyan.withOpacity(0.25)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (!mine)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(m.senderName?.isNotEmpty == true ? m.senderName! : 'NOVA Support',
                          style: GoogleFonts.inter(color: AppTheme.accentCyan, fontSize: 11, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 4),
                      const Icon(Icons.verified_rounded, color: AppTheme.accentCyan, size: 12),
                    ]),
                  ),
                SelectableText(m.body, style: GoogleFonts.inter(color: Colors.white, fontSize: 13.5, height: 1.45)),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Text(supportWhen(m.createdAt),
                      style: GoogleFonts.inter(color: mine ? Colors.white60 : AppTheme.textHint, fontSize: 10)),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _composer() => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: const BoxDecoration(
            color: AppTheme.bgCard,
            border: Border(top: BorderSide(color: AppTheme.divider)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                controller: _reply,
                minLines: 1,
                maxLines: 5,
                maxLength: 4000,
                textCapitalization: TextCapitalization.sentences,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 13.5),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'Reply to NOVA Support…',
                  hintStyle: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 13),
                  filled: true,
                  fillColor: AppTheme.bgInput,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppTheme.primaryGradient),
              child: IconButton(
                tooltip: 'Send',
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ]),
        ),
      );

  Widget _closedBar() => SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          color: AppTheme.bgCard,
          child: Row(children: [
            const Icon(Icons.lock_outline_rounded, color: AppTheme.textHint, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _ticket?.rating != null
                    ? 'This ticket is closed · you rated it ${_ticket!.rating}/5. Need more help? Open a new ticket.'
                    : 'This ticket is closed. Need more help? Open a new ticket from Support.',
                style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12),
              ),
            ),
          ]),
        ),
      );
}

class _RateDialog extends StatefulWidget {
  const _RateDialog();
  @override
  State<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<_RateDialog> {
  int _stars = 0;

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text('Close this ticket?', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('How was the help you received?',
              style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                onPressed: () => setState(() => _stars = i),
                icon: Icon(i <= _stars ? Icons.star_rounded : Icons.star_border_rounded,
                    color: const Color(0xFFFFC83D), size: 32),
              ),
          ]),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textHint)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _stars == 0 ? -1 : _stars),
            child: Text('Close ticket', style: GoogleFonts.inter(color: AppTheme.accentCyan, fontWeight: FontWeight.w700)),
          ),
        ],
      );
}
