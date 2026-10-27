// lib/features/nova_capture/screens/media_preview_screen.dart
//
// Full view of one capture: zoomable screenshot or playable recording, with
// edit, share, favourite, rename, delete (with confirmation) and details.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/capture_controller.dart';
import '../models/media_asset.dart';
import '../services/media_library_service.dart';
import '../widgets/capture_ui.dart';
import 'media_actions.dart';

class MediaPreviewScreen extends StatefulWidget {
  const MediaPreviewScreen({super.key, required this.asset, this.justCaptured = false});
  final MediaAsset asset;
  final bool justCaptured;

  @override
  State<MediaPreviewScreen> createState() => _MediaPreviewScreenState();
}

class _MediaPreviewScreenState extends State<MediaPreviewScreen> {
  final _c = CaptureController.instance;
  final _lib = MediaLibraryService.instance;
  late MediaAsset _asset = widget.asset;
  Uint8List? _image;
  VideoPlayerController? _video;
  bool _failed = false;
  bool _loading = true;
  bool _closing = false;

  /// Leaves the screen once (a delete is reported both here and by the library).
  void _closeOnce() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).maybePop();
  }

  @override
  void initState() {
    super.initState();
    _c.libraryVersion.addListener(_refresh);
    _load();
  }

  @override
  void dispose() {
    _c.libraryVersion.removeListener(_refresh);
    _video?.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final fresh = await _c.describe(_asset.uri);
    if (!mounted) return;
    if (fresh == null) {
      // Deleted (here or in the Gallery).
      _closeOnce();
      return;
    }
    setState(() => _asset = fresh.copyWith(durationMs: fresh.durationMs > 0 ? fresh.durationMs : _asset.durationMs));
  }

  Future<void> _load() async {
    try {
      if (_asset.isImage) {
        final b = await _c.readBytes(_asset);
        if (!mounted) return;
        setState(() {
          _image = b;
          _failed = b == null;
          _loading = false;
        });
      } else {
        final v = VideoPlayerController.contentUri(Uri.parse(_asset.uri));
        await v.initialize();
        if (!mounted) {
          await v.dispose();
          return;
        }
        v.addListener(() {
          if (mounted) setState(() {});
        });
        setState(() {
          _video = v;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _failed = true; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fav = _lib.isFavorite(_asset.uri);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(_asset.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: captureText(15, weight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: fav ? 'Remove from favourites' : 'Add to favourites',
            icon: Icon(fav ? Icons.star_rounded : Icons.star_border_rounded,
                color: fav ? const Color(0xFFFFC94D) : Colors.white),
            onPressed: () async {
              await _lib.setFavorite(_asset.uri, !fav);
              setState(() {});
              _c.libraryVersion.value++;
            },
          ),
          IconButton(
            tooltip: 'More actions',
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            onPressed: () => MediaActions.sheet(context, _asset, onDeleted: _closeOnce),
          ),
        ],
      ),
      body: Column(children: [
        if (widget.justCaptured)
          Container(
            width: double.infinity,
            color: AppTheme.success.withOpacity(0.15),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Semantics(
              liveRegion: true,
              child: Text(
                'Saved to ${_asset.isVideo ? 'Movies › NOVA X › Recordings' : 'Pictures › NOVA X › Screenshots'}',
                style: captureText(13, weight: FontWeight.w600, color: AppTheme.success),
              ),
            ),
          ),
        Expanded(child: _content()),
        _bottomBar(),
      ]),
    );
  }

  Widget _content() {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.broken_image_outlined, color: AppTheme.textHint, size: 52),
            const SizedBox(height: 12),
            Text("This capture can't be shown. It may have been moved or deleted.",
                textAlign: TextAlign.center, style: captureText(14, color: AppTheme.textSecondary)),
            TextButton(onPressed: () => _c.openExternal(_asset), child: const Text('Open in another app')),
          ]),
        ),
      );
    }
    final img = _image;
    if (img != null) {
      return InteractiveViewer(
        maxScale: 6,
        child: Center(
          child: Image.memory(img, fit: BoxFit.contain, semanticLabel: 'Screenshot ${_asset.name}'),
        ),
      );
    }
    final v = _video;
    if (v == null) return const SizedBox.shrink();
    final playing = v.value.isPlaying;
    return GestureDetector(
      onTap: () => playing ? v.pause() : v.play(),
      child: Stack(alignment: Alignment.center, children: [
        Center(child: AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v))),
        if (!playing)
          Semantics(
            button: true,
            label: 'Play recording',
            child: Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 44),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(children: [
            VideoProgressIndicator(v, allowScrubbing: true, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                colors: const VideoProgressColors(playedColor: AppTheme.accentCyan)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Row(children: [
                Text(formatDuration(v.value.position), style: captureText(12, color: Colors.white70)),
                const Spacer(),
                Text(formatDuration(v.value.duration), style: captureText(12, color: Colors.white70)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _bottomBar() {
    Widget btn(IconData icon, String label, VoidCallback onTap, {Color color = Colors.white}) => Expanded(
          child: Semantics(
            button: true,
            label: label,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: ExcludeSemantics(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, color: color),
                    const SizedBox(height: 4),
                    Text(label, style: captureText(11.5, color: color)),
                  ]),
                ),
              ),
            ),
          ),
        );
    return SafeArea(
      top: false,
      child: Container(
        color: const Color(0xFF0B1524),
        child: Row(children: [
          if (_asset.isImage) btn(Icons.edit_rounded, 'Edit', () => MediaActions.openEditor(context, _asset)),
          btn(Icons.share_rounded, 'Share', () async => captureReport(await _c.share(_asset))),
          if (_asset.isImage)
            btn(Icons.copy_rounded, 'Copy', () async =>
                captureReport(await _c.copyImage(_asset), success: 'Copied. Paste it where you need it.')),
          btn(Icons.drive_file_rename_outline_rounded, 'Rename', () => MediaActions.rename(context, _asset)),
          btn(Icons.delete_outline_rounded, 'Delete',
              () => MediaActions.delete(context, _asset, onDeleted: _closeOnce),
              color: AppTheme.danger),
        ]),
      ),
    );
  }
}
