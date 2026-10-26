// lib/features/support/screens/support_screen.dart
//
// 3.9.0 — NOVA X Help & Support.
//
//   Help    — instant answers from NOVA AI, searchable FAQ (some questions are
//             answered live by NOVA), and "Contact the team" (new ticket).
//   Inbox   — tickets NOVA Support has answered (unread replies first).
//   Outbox  — every ticket you sent, with its status.
//
// Replies from the team arrive as a push notification and in the
// Notifications page; tapping one opens the ticket here.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/platform_api.dart';
import '../../../core/theme/app_theme.dart';
import '../../ai/widgets/nova_markdown_view.dart';
import '../../auth/screens/auth_screen.dart';
import '../../nova/services/nova_api.dart';
import '../support_data.dart';
import '../widgets/support_widgets.dart';
import 'new_ticket_screen.dart';
import 'support_ticket_screen.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, this.initialTab = 0, this.openTicketId});

  /// 0 = Help, 1 = Inbox, 2 = Outbox.
  final int initialTab;

  /// Opens this ticket straight away (from a notification).
  final int? openTicketId;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  late int _tab = widget.initialTab < 0 ? 0 : (widget.initialTab > 2 ? 2 : widget.initialTab);
  final NovaApiClient _nova = NovaApiClient();

  bool _loggedIn = false;
  bool _loadingTickets = true;
  String? _ticketsError;
  List<SupportTicket> _tickets = const [];
  int _unread = 0;
  Timer? _poll;

  // Help tab
  final _askCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  String _search = '';
  bool _asking = false;
  String? _askedQuestion;
  String? _novaAnswer;
  String? _novaError;
  final Map<String, String> _faqNova = {};
  final Set<String> _faqLoading = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _loggedIn = await ApiService.isLoggedIn();
    if (!mounted) return;
    setState(() {});
    await _loadTickets();
    final open = widget.openTicketId;
    if (open != null && mounted && _loggedIn) _openTicket(open);
    // Near-real-time: refresh while the screen is open.
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _loggedIn) _loadTickets(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _askCtrl.dispose();
    _searchCtrl.dispose();
    _nova.dispose();
    super.dispose();
  }

  Future<void> _loadTickets({bool silent = false}) async {
    if (!_loggedIn) {
      if (mounted) setState(() => _loadingTickets = false);
      return;
    }
    if (!silent && mounted) setState(() => _loadingTickets = true);
    try {
      final r = await PlatformApi.tickets();
      if (!mounted) return;
      setState(() {
        _tickets = r.tickets;
        _unread = r.unread;
        _ticketsError = null;
        _loadingTickets = false;
      });
    } on NovaServiceError catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _ticketsError = e.message;
        _loadingTickets = false;
      });
    }
  }

  List<SupportTicket> get _inbox => _tickets.where((t) => t.inInbox).toList()
    ..sort((a, b) {
      if ((a.userUnread > 0) != (b.userUnread > 0)) return a.userUnread > 0 ? -1 : 1;
      return (b.lastMessageAt ?? DateTime(0)).compareTo(a.lastMessageAt ?? DateTime(0));
    });

  Future<void> _openTicket(int id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SupportTicketScreen(ticketId: id)));
    if (mounted) _loadTickets(silent: true);
  }

  Future<void> _newTicket({String? subject, String? message, String? category}) async {
    if (!_loggedIn) {
      await _signIn();
      if (!_loggedIn) return;
    }
    if (!mounted) return;
    final created = await Navigator.of(context).push<int>(MaterialPageRoute(
      builder: (_) => NewTicketScreen(subject: subject, message: message, category: category),
    ));
    if (!mounted) return;
    await _loadTickets(silent: true);
    if (created != null) setState(() => _tab = 2);
  }

  Future<void> _signIn() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen(showGuestOption: false)));
    final now = await ApiService.isLoggedIn();
    if (!mounted) return;
    setState(() => _loggedIn = now);
    if (now) _loadTickets();
  }

  // ── NOVA answers ───────────────────────────────────────────────
  static String _supportPrompt(String q) =>
      'NOVA X support question from a NOVA X user: $q\n\n'
      'Answer as NOVA X support: short, friendly, with the exact steps and where to tap in the NOVA X app. '
      'If it needs the NOVA X team (payments, a problem with the account, a bug), say so in one sentence '
      'and suggest opening a ticket in Profile → Contact Support.';

  Future<void> _askNova() async {
    final q = _askCtrl.text.trim();
    if (q.length < 4 || _asking) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _asking = true;
      _askedQuestion = q;
      _novaAnswer = null;
      _novaError = null;
    });
    try {
      final a = await _nova.chat(_supportPrompt(q), const []);
      if (!mounted) return;
      setState(() => _novaAnswer = a);
    } on NovaApiException catch (e) {
      if (!mounted) return;
      setState(() => _novaError = e.userMessage);
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  Future<void> _faqAsk(String q) async {
    if (_faqLoading.contains(q) || _faqNova.containsKey(q)) return;
    setState(() => _faqLoading.add(q));
    try {
      final a = await _nova.chat(_supportPrompt(q), const []);
      if (mounted) setState(() => _faqNova[q] = a);
    } on NovaApiException catch (e) {
      if (mounted) setState(() => _faqNova[q] = '⚠️ ${e.userMessage}');
    } finally {
      if (mounted) setState(() => _faqLoading.remove(q));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final outboxCount = _tickets.length;
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
            actions: [
              IconButton(
                tooltip: 'New ticket',
                icon: const Icon(Icons.edit_note_rounded, color: AppTheme.accentCyan, size: 21),
                onPressed: () => _newTicket(),
              ),
              const SizedBox(width: 4),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: SupportHeader(
                icon: Icons.support_agent_rounded,
                title: 'Help & Support',
                subtitle: 'Answers in seconds from NOVA, or a reply from our team — usually within 24 hours.',
                colors: const [AppTheme.primaryBlue, AppTheme.accentPurple],
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
                    const SupportSegmentItem(Icons.lightbulb_outline_rounded, 'Help'),
                    SupportSegmentItem(Icons.move_to_inbox_rounded, 'Inbox', badge: _unread),
                    SupportSegmentItem(Icons.outbox_rounded, 'Outbox', count: outboxCount),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: switch (_tab) {
            1 => _ticketList(key: const ValueKey('inbox'), inbox: true),
            2 => _ticketList(key: const ValueKey('outbox'), inbox: false),
            _ => _helpTab(),
          },
        ),
      ),
    );
  }

  // ── Help tab ───────────────────────────────────────────────────
  Widget _helpTab() {
    final q = _search.toLowerCase();
    final sections = faqSections
        .map((s) => FaqSection(
              s.title,
              s.icon,
              s.items.where((i) => q.isEmpty || i.question.toLowerCase().contains(q) ||
                  (i.answer ?? '').toLowerCase().contains(q)).toList(),
            ))
        .where((s) => s.items.isNotEmpty)
        .toList();

    return ListView(
      key: const ValueKey('help'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _askNovaCard(),
        const SizedBox(height: 22),
        SupportSectionLabel('FREQUENTLY ASKED'),
        const SizedBox(height: 10),
        SupportSearchField(
          controller: _searchCtrl,
          hint: 'Search help articles',
          onChanged: (v) => setState(() => _search = v.trim()),
        ),
        const SizedBox(height: 12),
        if (sections.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text('No article matches "$_search". Ask NOVA above or contact the team.',
                style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12.5)),
          ),
        for (final s in sections) _faqSection(s),
        const SizedBox(height: 16),
        _contactCard(),
        const SizedBox(height: 14),
        _infoStrip(),
      ],
    );
  }

  Widget _askNovaCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.accentCyan.withOpacity(0.12), AppTheme.accentPurple.withOpacity(0.10)],
        ),
        border: Border.all(color: AppTheme.accentCyan.withOpacity(0.28)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppTheme.primaryGradient),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Ask NOVA', style: GoogleFonts.spaceGrotesk(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              Text('Instant answers about NOVA X, 24/7',
                  style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 11.5)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.bgInput,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _askCtrl,
                minLines: 1,
                maxLines: 4,
                maxLength: 600,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _askNova(),
                style: GoogleFonts.inter(color: Colors.white, fontSize: 13.5),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'Describe your problem, e.g. "Hey NOVA stopped listening"',
                  hintStyle: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12.5),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Ask',
              onPressed: _asking ? null : _askNova,
              icon: _asking
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentCyan))
                  : const Icon(Icons.send_rounded, color: AppTheme.accentCyan),
            ),
          ]),
        ),
        if (_asking || _novaAnswer != null || _novaError != null) ...[
          const SizedBox(height: 12),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.glassBorder),
              ),
              child: _asking
                  ? Row(children: [
                      const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentCyan)),
                      const SizedBox(width: 10),
                      Text('NOVA is looking into it…',
                          style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12.5)),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (_novaError != null)
                        Text(_novaError!, style: GoogleFonts.inter(color: AppTheme.warning, fontSize: 12.5))
                      else
                        NovaMarkdownView(text: _novaAnswer!, fontSize: 13.5),
                      const SizedBox(height: 12),
                      Text('Did this solve your problem?',
                          style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11.5)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        SupportChipButton(
                          icon: Icons.thumb_up_alt_rounded,
                          label: 'Yes, thanks',
                          color: AppTheme.success,
                          onTap: () {
                            setState(() {
                              _novaAnswer = null;
                              _novaError = null;
                              _askCtrl.clear();
                            });
                            ScaffoldMessenger.of(context).showSnackBar(supportSnack('Glad NOVA could help!'));
                          },
                        ),
                        SupportChipButton(
                          icon: Icons.support_agent_rounded,
                          label: 'No, contact the team',
                          color: AppTheme.accentCyan,
                          onTap: () => _newTicket(
                            subject: _askedQuestion == null
                                ? null
                                : (_askedQuestion!.length > 80 ? '${_askedQuestion!.substring(0, 80)}…' : _askedQuestion),
                            message: _askedQuestion,
                          ),
                        ),
                      ]),
                    ]),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _faqSection(FaqSection s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _search.isNotEmpty,
          leading: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: AppTheme.accentCyan.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(s.icon, color: AppTheme.accentCyan, size: 18),
          ),
          title: Text(s.title, style: GoogleFonts.spaceGrotesk(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
          subtitle: Text('${s.items.length} article${s.items.length == 1 ? '' : 's'}',
              style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11)),
          iconColor: AppTheme.accentCyan,
          collapsedIconColor: AppTheme.textHint,
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          children: [for (final i in s.items) _faqItem(i)],
        ),
      ),
    );
  }

  Widget _faqItem(FaqItem item) {
    final novaText = _faqNova[item.question];
    final loading = _faqLoading.contains(item.question);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: AppTheme.bgElevated.withOpacity(0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          onExpansionChanged: (open) {
            if (open && item.askNova) _faqAsk(item.question);
          },
          title: Text(item.question, style: GoogleFonts.inter(
              color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          trailing: item.askNova
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.accentPurple.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.auto_awesome_rounded, color: AppTheme.accentPurple, size: 11),
                    const SizedBox(width: 3),
                    Text('NOVA', style: GoogleFonts.inter(
                        color: AppTheme.accentPurple, fontSize: 9.5, fontWeight: FontWeight.w800)),
                  ]),
                )
              : null,
          iconColor: AppTheme.accentCyan,
          collapsedIconColor: AppTheme.textHint,
          children: [
            if (item.answer != null)
              Text(item.answer!, style: GoogleFonts.inter(
                  color: AppTheme.textSecondary, fontSize: 12.5, height: 1.5))
            else if (loading || novaText == null)
              Row(children: [
                const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentPurple)),
                const SizedBox(width: 10),
                Text('NOVA is writing the answer…',
                    style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12)),
              ])
            else
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                NovaMarkdownView(text: novaText, fontSize: 12.8, color: AppTheme.textSecondary),
                const SizedBox(height: 6),
                Text('Answered by NOVA AI', style: GoogleFonts.inter(
                    color: AppTheme.accentPurple, fontSize: 10.5, fontWeight: FontWeight.w600)),
              ]),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _newTicket(subject: item.question),
              child: Text('Still need help? Contact the team',
                  style: GoogleFonts.inter(
                      color: AppTheme.accentCyan, fontSize: 11.5, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contactCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.forum_rounded, color: AppTheme.primaryBlue, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Still need help?', style: GoogleFonts.spaceGrotesk(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 6),
          Text('Send a message to the NOVA X team. You will get a notification when we reply, and you can '
              'answer in the same ticket.',
              style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.45)),
          const SizedBox(height: 14),
          SupportPrimaryButton(
            icon: Icons.edit_note_rounded,
            label: _loggedIn ? 'Contact support' : 'Sign in to contact support',
            onTap: () => _newTicket(),
          ),
        ]),
      );

  Widget _infoStrip() => Row(children: [
        Expanded(child: SupportStat(icon: Icons.bolt_rounded, value: 'Instant', label: 'NOVA answers')),
        const SizedBox(width: 8),
        Expanded(child: SupportStat(icon: Icons.schedule_rounded, value: '< 24 h', label: 'Team replies')),
        const SizedBox(width: 8),
        Expanded(child: SupportStat(icon: Icons.lock_rounded, value: 'Private', label: 'Only our team')),
      ]);

  // ── Inbox / Outbox ─────────────────────────────────────────────
  Widget _ticketList({required Key key, required bool inbox}) {
    if (!_loggedIn) {
      return SupportEmptyState(
        key: key,
        icon: Icons.lock_person_rounded,
        title: 'Sign in to see your tickets',
        message: 'Support tickets are linked to your NOVA X account so our replies reach you.',
        actionLabel: 'Sign in',
        onAction: _signIn,
      );
    }
    if (_loadingTickets) {
      return const Center(key: ValueKey('loading'), child: CircularProgressIndicator(color: AppTheme.accentCyan));
    }
    if (_ticketsError != null && _tickets.isEmpty) {
      return SupportEmptyState(
        key: key,
        icon: Icons.wifi_off_rounded,
        title: "Couldn't load your tickets",
        message: _ticketsError!,
        actionLabel: 'Try again',
        onAction: () => _loadTickets(),
      );
    }
    final list = inbox ? _inbox : _tickets;
    if (list.isEmpty) {
      return SupportEmptyState(
        key: key,
        icon: inbox ? Icons.mark_email_read_rounded : Icons.outbox_rounded,
        title: inbox ? 'No replies yet' : 'No tickets yet',
        message: inbox
            ? 'When NOVA Support answers one of your tickets, the reply appears here.'
            : 'Questions you send to the NOVA X team appear here with their status.',
        actionLabel: 'New ticket',
        onAction: () => _newTicket(),
      );
    }
    return RefreshIndicator(
      key: key,
      color: AppTheme.accentCyan,
      backgroundColor: AppTheme.bgCard,
      onRefresh: () => _loadTickets(silent: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => SupportTicketCard(
          ticket: list[i],
          inbox: inbox,
          onTap: () => _openTicket(list[i].id),
        ),
      ),
    );
  }
}
