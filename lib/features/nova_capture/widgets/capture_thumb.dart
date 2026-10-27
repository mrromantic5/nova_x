// lib/features/nova_capture/widgets/capture_thumb.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/media_asset.dart';
import '../services/media_library_service.dart';
import 'capture_ui.dart';

/// Small preview of a capture (thumbnails are made by Android and cached in memory).
class CaptureThumb extends StatefulWidget {
  const CaptureThumb({super.key, required this.asset, this.radius = 14, this.favorite = false});
  final MediaAsset asset;
  final double radius;
  final bool favorite;

  @override
  State<CaptureThumb> createState() => _CaptureThumbState();
}

class _CaptureThumbState extends State<CaptureThumb> {
  Future<Uint8List?>? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = MediaLibraryService.instance.thumbnail(widget.asset);
  }

  @override
  void didUpdateWidget(CaptureThumb old) {
    super.didUpdateWidget(old);
    if (old.asset != widget.asset) _bytes = MediaLibraryService.instance.thumbnail(widget.asset);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.asset;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Stack(fit: StackFit.expand, children: [
        Container(color: AppTheme.bgElevated),
        FutureBuilder<Uint8List?>(
          future: _bytes,
          builder: (context, snap) {
            final b = snap.data;
            if (b != null) {
              return Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true, excludeFromSemantics: true);
            }
            if (snap.connectionState == ConnectionState.done) {
              return Center(
                child: Icon(a.isVideo ? Icons.movie_rounded : Icons.image_rounded, color: AppTheme.textHint),
              );
            }
            return const SizedBox.shrink();
          },
        ),
        if (a.isVideo)
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xCC000000), borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 12),
                if (a.durationMs > 0) ...[
                  const SizedBox(width: 2),
                  Text(formatDuration(Duration(milliseconds: a.durationMs)), style: captureText(10.5, weight: FontWeight.w700)),
                ],
              ]),
            ),
          ),
        if (widget.favorite)
          const Positioned(
            right: 6,
            top: 6,
            child: Icon(Icons.star_rounded, color: Color(0xFFFFC94D), size: 18),
          ),
      ]),
    );
  }
}
