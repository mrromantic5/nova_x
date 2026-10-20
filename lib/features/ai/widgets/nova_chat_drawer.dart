// lib/features/ai/widgets/nova_chat_drawer.dart
//
// NOVA AI chat history — the side menu of the NOVA AI screen.
// Tap a chat to open it; long-press it to rename or delete it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/theme/app_theme.dart';

import '../services/nova_chat_api.dart';
import '../services/nova_chat_models.dart';
import '../services/nova_chat_repository.dart';

class NovaChatDrawer extends StatefulWidget {
  const NovaChatDrawer({
    super.key,
    required this.repository,
    required this.currentChatId,
    required this.onOpen,
    required this.onNewChat,
    required this.onDeleted,
    required this.onReport,
  });

  /// Null while the history is loading or when it can't be used.
  final NovaChatRepository? repository;
  final String? currentChatId;
  final ValueChanged<String> onOpen;
  final VoidCallback onNewChat;

  /// A chat was deleted (the screen starts a new chat if it was open).
  final ValueChanged<String> onDeleted;
  final VoidCallback onReport;

  @override
  State<NovaChatDrawer> createState() => _NovaChatDrawerState();
}

class _NovaChatDrawerState extends State<NovaChatDrawer> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _showOptions(NovaChatMeta chat) async {
    HapticFeedback.mediumImpact();
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheet) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(sheet).padding.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(color: AppTheme.divider, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(chat.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(
                    color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          _SheetButton(
            icon: Icons.drive_file_rename_outline_rounded,
            label: 'Rename',
            color: AppTheme.accentCyan,
            onTap: () => Navigator.pop(sheet, 'rename'),
          ),
          const SizedBox(height: 8),
          _SheetButton(
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            color: AppTheme.danger,
            onTap: () => Navigator.pop(sheet, 'delete'),
          ),
        ]),
      ),
    );
    if (!mounted) return;
    if (choice == 'rename') await _rename(chat);
    if (choice == 'delete') await _delete(chat);
  }

  Future<void> _rename(NovaChatMeta chat) async {
    final repo = widget.repository;
    if (repo == null) return;
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: chat.title),
    );
    if (title == null || !mounted) return;
    final clean = NovaChatRepository.cleanTitle(title);
    if (clean == chat.title) return;
    await repo.rename(chat.id, clean);
  }

  Future<void> _delete(NovaChatMeta chat) async {
    final repo = widget.repository;
    if (repo == null) return;
    final where = repo.signedIn ? 'this phone and your NOVA X account' : 'this phone';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Delete chat?',
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text('“${chat.title}” will be deleted from $where.',
            style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13, height: 1.45)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text('Delete',
                style: GoogleFonts.inter(color: AppTheme.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await repo.delete(chat.id);
    widget.onDeleted(chat.id);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final repo = widget.repository;
    return Drawer(
      width: width * 0.86 > 340.0 ? 340.0 : width * 0.86,
      backgroundColor: AppTheme.bgDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(22)),
      ),
      child: SafeArea(
        child: repo == null
            ? _buildUnavailable()
            : AnimatedBuilder(
                animation: repo,
                builder: (_, __) => _buildContent(repo),
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 6),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(Icons.forum_rounded, color: Colors.white, size: 17),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text('NOVA AI chats',
              style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded, color: AppTheme.textHint, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ]),
    );
  }

  Widget _buildNewChatButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onNewChat();
          },
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppTheme.glowShadow,
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.add_rounded, color: Colors.white, size: 19),
              const SizedBox(width: 6),
              Text('New chat',
                  style: GoogleFonts.inter(
                      color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildUnavailable() {
    return Column(children: [
      _buildHeader(),
      _buildNewChatButton(),
      const Spacer(),
      Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Chat history isn’t available on this phone right now.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 13, height: 1.45)),
      ),
      const Spacer(),
      _buildFooter(null),
    ]);
  }

  Widget _buildContent(NovaChatRepository repo) {
    final all = repo.chats;
    final q = _query.trim().toLowerCase();
    final chats = q.isEmpty ? all : all.where((c) => c.title.toLowerCase().contains(q)).toList();
    return Column(children: [
      _buildHeader(),
      _buildNewChatButton(),
      if (all.length > 5) _buildSearch(),
      Expanded(
        child: chats.isEmpty
            ? _buildEmpty(searching: q.isNotEmpty)
            : RefreshIndicator(
                color: AppTheme.accentCyan,
                backgroundColor: AppTheme.bgCard,
                onRefresh: repo.sync,
                child: _buildList(chats),
              ),
      ),
      _buildFooter(repo),
    ]);
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          const Icon(Icons.search_rounded, color: AppTheme.textHint, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: 'Search chats',
                hintStyle: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 13),
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() {
                _search.clear();
                _query = '';
              }),
              child: const Icon(Icons.close_rounded, color: AppTheme.textHint, size: 16),
            ),
        ]),
      ),
    );
  }

  Widget _buildEmpty({required bool searching}) {
    return ListView(
      // Scrollable so pull-to-refresh is not needed here; keeps layout simple.
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 20),
      children: [
        const Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.textHint, size: 34),
        const SizedBox(height: 12),
        Text(searching ? 'No chats match your search.' : 'No chats yet',
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textSecondary, fontSize: 14, fontWeight: FontWeight.w600)),
        if (!searching) ...[
          const SizedBox(height: 6),
          Text('Your conversations with NOVA AI will appear here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12, height: 1.45)),
        ],
      ],
    );
  }

  Widget _buildList(List<NovaChatMeta> chats) {
    final items = <Widget>[];
    String? lastGroup;
    final now = DateTime.now();
    for (final chat in chats) {
      final group = _groupOf(chat.updatedAt, now);
      if (group != lastGroup) {
        lastGroup = group;
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
          child: Text(group.toUpperCase(),
              style: GoogleFonts.inter(
                  color: AppTheme.textHint,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1)),
        ));
      }
      items.add(_ChatCard(
        chat: chat,
        selected: chat.id == widget.currentChatId,
        subtitle: _subtitle(chat, now),
        onTap: () => widget.onOpen(chat.id),
        onLongPress: () => _showOptions(chat),
      ));
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 8),
      children: items,
    );
  }

  Widget _buildFooter(NovaChatRepository? repo) {
    final status = _status(repo);
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppTheme.divider))),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: repo != null && repo.syncing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.6, color: AppTheme.accentCyan),
                  )
                : Icon(status.$1, color: status.$3, size: 15),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(status.$2,
                style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11, height: 1.4)),
          ),
        ]),
        if (repo != null && repo.chats.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Long-press a chat to rename or delete it.',
                style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 10.5)),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: widget.onReport,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              visualDensity: VisualDensity.compact,
            ),
            icon: const FaIcon(FontAwesomeIcons.flag, color: AppTheme.textHint, size: 12),
            label: Text('Report AI content',
                style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12)),
          ),
        ),
      ]),
    );
  }

  // ── Text helpers ─────────────────────────────────────────────────────────

  (IconData, String, Color) _status(NovaChatRepository? repo) {
    if (repo == null) {
      return (Icons.info_outline_rounded, 'New chats can still be started.', AppTheme.textHint);
    }
    if (!repo.signedIn) {
      return (
        Icons.phone_android_rounded,
        'Chats are saved on this phone. Sign in to keep them on all your devices.',
        AppTheme.textHint,
      );
    }
    if (repo.syncing) return (Icons.sync_rounded, 'Syncing your chats…', AppTheme.accentCyan);
    return switch (repo.problem) {
      NovaChatSyncProblem.offline => (
          Icons.cloud_off_rounded,
          'You’re offline. Chats are saved on this phone and sync when you’re back online.',
          AppTheme.warning,
        ),
      NovaChatSyncProblem.signedOut => (
          Icons.lock_outline_rounded,
          'Your session has ended. Sign in again to sync your chats.',
          AppTheme.warning,
        ),
      NovaChatSyncProblem.notSetUp => (
          Icons.cloud_off_rounded,
          'Chat sync isn’t available yet. Chats are saved on this phone.',
          AppTheme.textHint,
        ),
      NovaChatSyncProblem.failed => (
          Icons.cloud_off_rounded,
          'Couldn’t sync right now. Chats are saved on this phone. Pull down to try again.',
          AppTheme.warning,
        ),
      null => (Icons.cloud_done_rounded, 'Synced with your NOVA X account.', AppTheme.success),
    };
  }

  static String _groupOf(int ms, DateTime now) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return 'Previous 7 days';
    if (diff < 30) return 'Previous 30 days';
    return 'Older';
  }

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _subtitle(NovaChatMeta chat, DateTime now) {
    final d = DateTime.fromMillisecondsSinceEpoch(chat.updatedAt);
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    final String when;
    if (sameDay) {
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      final m = d.minute.toString().padLeft(2, '0');
      when = '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
    } else if (d.year == now.year) {
      when = '${_months[d.month - 1]} ${d.day}';
    } else {
      when = '${_months[d.month - 1]} ${d.day}, ${d.year}';
    }
    final n = chat.messageCount;
    return n > 0 ? '$when · $n message${n == 1 ? '' : 's'}' : when;
  }
}

// ── Chat card ─────────────────────────────────────────────────────────────

class _ChatCard extends StatelessWidget {
  const _ChatCard({
    required this.chat,
    required this.selected,
    required this.subtitle,
    required this.onTap,
    required this.onLongPress,
  });

  final NovaChatMeta chat;
  final bool selected;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: selected ? AppTheme.bgElevated : AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppTheme.accentCyan.withOpacity(0.55) : AppTheme.divider,
              ),
            ),
            child: Row(children: [
              Icon(
                chat.title.startsWith('Image:')
                    ? Icons.image_outlined
                    : chat.title.startsWith('Video:')
                        ? Icons.videocam_outlined
                        : Icons.chat_bubble_outline_rounded,
                color: selected ? AppTheme.accentCyan : AppTheme.textHint,
                size: 17,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(chat.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          color: AppTheme.textPrimary,
                          fontSize: 13.5,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11)),
                ]),
              ),
              if (chat.onServerOnly)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.cloud_outlined, color: AppTheme.textHint, size: 15),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.bgElevated,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Text(label,
                style: GoogleFonts.inter(color: color, fontSize: 14, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    Navigator.pop(context, t);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text('Rename chat',
          style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLength: NovaChatRepository.maxTitleLength,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
        cursorColor: AppTheme.accentCyan,
        decoration: InputDecoration(
          hintText: 'Chat name',
          hintStyle: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 14),
          counterStyle: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 10),
          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.divider)),
          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.accentCyan)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textSecondary)),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _ctrl,
          builder: (_, value, __) => TextButton(
            onPressed: value.text.trim().isEmpty ? null : _submit,
            child: Text('Rename',
                style: GoogleFonts.inter(
                    color: value.text.trim().isEmpty ? AppTheme.textHint : AppTheme.accentCyan,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}
