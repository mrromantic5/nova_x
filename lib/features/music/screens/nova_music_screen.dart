// lib/features/music/screens/nova_music_screen.dart
//
// NOVA Music — the built-in music player for songs saved on the phone.
// Works offline, keeps playing in the background (notification and
// lock-screen controls), and NOVA can drive it by voice:
// "Hey NOVA, play Like You by Tatiana", "pause", "next song".
//
// Access to the phone's music is asked here with an explanation first
// (Android 13+: "Music and audio"; older: storage). Nothing is uploaded.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../nova/nova_launcher.dart';
import '../../nova/services/nova_native.dart';
import '../services/nova_music_service.dart';

class NovaMusicScreen extends StatefulWidget {
  const NovaMusicScreen({super.key});

  @override
  State<NovaMusicScreen> createState() => _NovaMusicScreenState();
}

class _NovaMusicScreenState extends State<NovaMusicScreen> with WidgetsBindingObserver {
  final NovaMusicService _music = NovaMusicService.instance;
  final TextEditingController _search = TextEditingController();

  List<NovaSongInfo> _songs = const [];
  String _query = '';
  String? _artist;
  bool _artistsTab = false;
  bool _loading = true;
  bool _needsPermission = false;
  bool _denied = false;
  bool _failed = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _music.refreshState();
    // Moves the progress bar while a song plays.
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && _music.state.value.isPlaying) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  // Back from Android settings (permission) or from another app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _music.refreshState();
      if (_needsPermission) _load(refresh: true);
    }
  }

  Future<void> _load({bool refresh = false}) async {
    final lib = await _music.library(refresh: refresh);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _needsPermission = lib.status == 'permission_required';
      _failed = lib.status == 'error';
      _songs = lib.songs;
    });
  }

  Future<void> _allow() async {
    final granted = await NovaNative.instance.requestPermission('audio');
    if (!mounted) return;
    if (granted) {
      setState(() => _loading = true);
      await _load(refresh: true);
    } else {
      setState(() => _denied = true);
    }
  }

  List<NovaSongInfo> get _visible {
    var list = _songs;
    final artist = _artist;
    if (artist != null) list = list.where((s) => s.artist == artist).toList();
    final q = _query.trim();
    if (q.isNotEmpty) list = list.where((s) => s.matches(q)).toList();
    return list;
  }

  Map<String, int> get _artists {
    final counts = <String, int>{};
    for (final s in _songs) {
      if (s.artist.isEmpty) continue;
      counts[s.artist] = (counts[s.artist] ?? 0) + 1;
    }
    final keys = counts.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return {for (final k in keys) k: counts[k]!};
  }

  Future<void> _playFrom(List<NovaSongInfo> list, int index) async {
    final ok = await _music.playSongs(list.map((s) => s.id).toList(), index, shuffle: false);
    if (!ok && mounted) _snack("That song couldn't be played.");
  }

  Future<void> _shuffleAll() async {
    final list = _visible;
    if (list.isEmpty) return;
    final ok = await _music.playSongs(list.map((s) => s.id).toList(), 0, shuffle: true);
    if (!ok && mounted) _snack("Music couldn't be started.");
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text, style: GoogleFonts.inter(color: Colors.white)),
      backgroundColor: AppTheme.bgElevated,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _openPlayer() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NowPlayingSheet(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        foregroundColor: AppTheme.textPrimary,
        title: Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Text('NOVA Music',
              style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, fontSize: 18)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Ask NOVA',
            icon: const Icon(Icons.auto_awesome_rounded, color: AppTheme.accentCyan),
            onPressed: () => showNovaAssistant(context),
          ),
          if (!_needsPermission)
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
              onPressed: () {
                setState(() => _loading = true);
                _load(refresh: true);
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentCyan))
          : _needsPermission
              ? _permissionView()
              : _songs.isEmpty
                  ? _emptyView()
                  : _libraryView(),
      bottomNavigationBar: ValueListenableBuilder<NovaMusicState>(
        valueListenable: _music.state,
        builder: (_, s, __) => s.hasSong ? _miniPlayer(s) : const SizedBox.shrink(),
      ),
    );
  }

  Widget _permissionView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      children: [
        Center(
          child: Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppTheme.primaryGradient,
              boxShadow: AppTheme.glowShadow,
            ),
            child: const Icon(Icons.library_music_rounded, color: Colors.white, size: 44),
          ),
        ),
        const SizedBox(height: 24),
        Text('Play the music on your phone',
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Text(
          'NOVA Music plays the songs saved on this phone — even offline — and lets you say '
          '“Hey NOVA, play …”.\n\nTo do that, NOVA X needs access to your music and audio files. '
          'Your music stays on your phone: nothing is uploaded.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 14, height: 1.55),
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _allow,
            icon: const Icon(Icons.lock_open_rounded),
            label: Text('Allow access to music',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentCyan,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        if (_denied) ...[
          const SizedBox(height: 14),
          Text(
            'Access was not allowed. If Android no longer asks, allow "Music and audio" for '
            'NOVA X in Settings.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: AppTheme.warning, fontSize: 12.5, height: 1.5),
          ),
          TextButton(
            onPressed: NovaNative.instance.openAppPermissionSettings,
            child: Text('Open app settings',
                style: GoogleFonts.inter(color: AppTheme.accentCyan, fontWeight: FontWeight.w600)),
          ),
        ],
      ],
    );
  }

  Widget _emptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.music_off_rounded, color: AppTheme.textHint, size: 56),
          const SizedBox(height: 16),
          Text(_failed ? "Your music couldn't be read" : 'No songs on this phone yet',
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Songs you download or copy to your phone appear here automatically.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13.5, height: 1.5),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () {
              setState(() => _loading = true);
              _load(refresh: true);
            },
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Check again'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.accentCyan,
              side: const BorderSide(color: AppTheme.accentCyan),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _libraryView() {
    final visible = _visible;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: TextField(
          controller: _search,
          onChanged: (v) => setState(() => _query = v),
          style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search songs, artists or albums',
            hintStyle: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 14),
            prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textHint),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppTheme.textHint),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                  ),
            filled: true,
            fillColor: AppTheme.bgCard,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Row(children: [
          _tabChip('Songs', !_artistsTab, () => setState(() => _artistsTab = false)),
          const SizedBox(width: 8),
          _tabChip('Artists', _artistsTab, () => setState(() => _artistsTab = true)),
          const Spacer(),
          if (!_artistsTab)
            TextButton.icon(
              onPressed: visible.isEmpty ? null : _shuffleAll,
              icon: const Icon(Icons.shuffle_rounded, size: 18, color: AppTheme.accentCyan),
              label: Text('Shuffle',
                  style: GoogleFonts.inter(color: AppTheme.accentCyan, fontWeight: FontWeight.w600)),
            ),
        ]),
      ),
      if (_artist != null && !_artistsTab)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              label: Text(_artist!, style: GoogleFonts.inter(color: AppTheme.textPrimary)),
              backgroundColor: AppTheme.bgElevated,
              onDeleted: () => setState(() => _artist = null),
              deleteIconColor: AppTheme.textSecondary,
            ),
          ),
        ),
      Expanded(child: _artistsTab ? _artistList() : _songList(visible)),
    ]);
  }

  Widget _tabChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected ? AppTheme.primaryGradient : null,
          color: selected ? null : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: GoogleFonts.inter(
                color: selected ? Colors.white : AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _songList(List<NovaSongInfo> list) {
    if (list.isEmpty) {
      return Center(
        child: Text('No songs match “$_query”.',
            style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 13.5)),
      );
    }
    return ValueListenableBuilder<NovaMusicState>(
      valueListenable: _music.state,
      builder: (_, s, __) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        itemCount: list.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) return _voiceTip();
          final song = list[i - 1];
          final current = s.hasSong && s.id == song.id;
          return ListTile(
            onTap: () => _playFrom(list, i - 1),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: current ? AppTheme.accentCyan.withOpacity(0.15) : AppTheme.bgCard,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                current
                    ? (s.isPlaying ? Icons.graphic_eq_rounded : Icons.pause_rounded)
                    : Icons.music_note_rounded,
                color: current ? AppTheme.accentCyan : AppTheme.textHint,
              ),
            ),
            title: Text(song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    color: current ? AppTheme.accentCyan : AppTheme.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600)),
            subtitle: Text(song.artistLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12.5)),
            trailing: Text(novaMusicDuration(song.durationMs),
                style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12)),
          );
        },
      ),
    );
  }

  Widget _voiceTip() {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(children: [
        const Icon(Icons.record_voice_over_rounded, color: AppTheme.accentPurple, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${_songs.length} songs · Say “Hey NOVA, play …”, “pause” or “next song” — works offline.',
            style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.4),
          ),
        ),
      ]),
    );
  }

  Widget _artistList() {
    final artists = _artists;
    if (artists.isEmpty) {
      return Center(
        child: Text('No artist information in your songs.',
            style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 13.5)),
      );
    }
    final names = artists.keys.toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      itemCount: names.length,
      itemBuilder: (_, i) {
        final name = names[i];
        final count = artists[name] ?? 0;
        return ListTile(
          onTap: () => setState(() {
            _artist = name;
            _artistsTab = false;
          }),
          leading: CircleAvatar(
            backgroundColor: AppTheme.accentPurple.withOpacity(0.18),
            child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                style: GoogleFonts.spaceGrotesk(
                    color: AppTheme.accentPurple, fontWeight: FontWeight.w700)),
          ),
          title: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  color: AppTheme.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w600)),
          subtitle: Text(count == 1 ? '1 song' : '$count songs',
              style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12.5)),
          trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textHint),
        );
      },
    );
  }

  Widget _miniPlayer(NovaMusicState s) {
    final now = DateTime.now();
    final progress = s.durationMs > 0 ? s.livePositionMs(now) / s.durationMs : 0.0;
    return SafeArea(
      top: false,
      child: GestureDetector(
        onTap: _openPlayer,
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          decoration: BoxDecoration(
            color: AppTheme.bgElevated,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.glassBorder),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0).toDouble(),
                minHeight: 3,
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation(AppTheme.accentCyan),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.music_note_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.title ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                    Text((s.artist ?? '').isEmpty ? 'Unknown artist' : s.artist!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12)),
                  ]),
                ),
                IconButton(
                  icon: Icon(s.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: AppTheme.textPrimary, size: 30),
                  onPressed: _music.toggle,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded, color: AppTheme.textPrimary, size: 28),
                  onPressed: _music.next,
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}


/// Full-screen player: big artwork, seek bar and all controls.
class _NowPlayingSheet extends StatefulWidget {
  const _NowPlayingSheet();

  @override
  State<_NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends State<_NowPlayingSheet> {
  final NovaMusicService _music = NovaMusicService.instance;
  Timer? _ticker;
  double? _dragging;

  @override
  void initState() {
    super.initState();
    _music.refreshState();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && _dragging == null && _music.state.value.isPlaying) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return ValueListenableBuilder<NovaMusicState>(
      valueListenable: _music.state,
      builder: (_, s, __) {
        final duration = s.durationMs > 0 ? s.durationMs.toDouble() : 1.0;
        final position = (_dragging ?? s.livePositionMs(DateTime.now()).toDouble()).clamp(0.0, duration).toDouble();
        return Container(
          height: height * 0.86,
          decoration: const BoxDecoration(
            color: AppTheme.bgDark,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: SafeArea(
            top: false,
            child: Column(children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Row(children: [
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.textSecondary, size: 30),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text('NOW PLAYING',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                          color: AppTheme.textHint,
                          fontSize: 11,
                          letterSpacing: 1.6,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 48),
              ]),
              const Spacer(),
              AspectRatio(
                aspectRatio: 1,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppTheme.accentPurple, AppTheme.primaryBlue, AppTheme.accentCyan],
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: AppTheme.accentCyan.withOpacity(0.25),
                          blurRadius: 40,
                          spreadRadius: -4),
                    ],
                  ),
                  child: Icon(s.isPlaying ? Icons.graphic_eq_rounded : Icons.music_note_rounded,
                      color: Colors.white, size: 96),
                ),
              ),
              const Spacer(),
              Text(s.title ?? 'Nothing playing',
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.spaceGrotesk(
                      color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text((s.artist ?? '').isEmpty ? 'Unknown artist' : s.artist!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 14.5)),
              const SizedBox(height: 18),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppTheme.accentCyan,
                  inactiveTrackColor: AppTheme.bgElevated,
                  thumbColor: Colors.white,
                  trackHeight: 3,
                ),
                child: Slider(
                  value: position,
                  max: duration,
                  onChanged: s.hasSong ? (v) => setState(() => _dragging = v) : null,
                  onChangeEnd: (v) {
                    _music.seekTo(v.round());
                    setState(() => _dragging = null);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(children: [
                  Text(novaMusicDuration(position.round()),
                      style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12)),
                  const Spacer(),
                  Text(novaMusicDuration(s.durationMs),
                      style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12)),
                ]),
              ),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                IconButton(
                  tooltip: 'Shuffle',
                  icon: Icon(Icons.shuffle_rounded,
                      color: s.shuffle ? AppTheme.accentCyan : AppTheme.textHint),
                  onPressed: () => _music.setShuffle(!s.shuffle),
                ),
                IconButton(
                  iconSize: 40,
                  icon: const Icon(Icons.skip_previous_rounded, color: AppTheme.textPrimary),
                  onPressed: _music.previous,
                ),
                GestureDetector(
                  onTap: _music.toggle,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppTheme.primaryGradient,
                      boxShadow: AppTheme.glowShadow,
                    ),
                    child: Icon(s.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.white, size: 40),
                  ),
                ),
                IconButton(
                  iconSize: 40,
                  icon: const Icon(Icons.skip_next_rounded, color: AppTheme.textPrimary),
                  onPressed: _music.next,
                ),
                IconButton(
                  tooltip: 'Repeat',
                  icon: Icon(s.repeat == 'one' ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                      color: s.repeat == 'off' ? AppTheme.textHint : AppTheme.accentCyan),
                  onPressed: () => _music.setRepeat(switch (s.repeat) {
                    'off' => 'all',
                    'all' => 'one',
                    _ => 'off',
                  }),
                ),
              ]),
            ]),
          ),
        );
      },
    );
  }
}
