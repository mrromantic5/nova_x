// lib/features/nova_capture/screens/capture_latest_screen.dart
//
// Opens the newest capture (from the "saved" notification or "Hey NOVA, open
// my latest screenshot"). Shows a clear message when there is none.

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/capture_controller.dart';
import '../models/media_asset.dart';
import '../widgets/capture_ui.dart';
import 'capture_media_library.dart';
import 'media_preview_screen.dart';
import 'screenshot_editor.dart';

class CaptureLatestScreen extends StatefulWidget {
  const CaptureLatestScreen({super.key, this.kind, this.edit = false});
  final MediaKind? kind;
  final bool edit;

  @override
  State<CaptureLatestScreen> createState() => _CaptureLatestScreenState();
}

class _CaptureLatestScreenState extends State<CaptureLatestScreen> {
  bool _none = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final c = CaptureController.instance;
    await c.init();
    final kind = widget.edit ? MediaKind.screenshot : widget.kind;
    final item = await c.library.latest(kind: kind);
    if (!mounted) return;
    if (item == null) {
      setState(() => _none = true);
      return;
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      settings: RouteSettings(name: widget.edit ? 'nova/capture_editor' : 'nova/capture_preview'),
      builder: (_) => widget.edit && item.isImage ? ScreenshotEditor(asset: item) : MediaPreviewScreen(asset: item),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final what = widget.kind == MediaKind.recording
        ? 'recordings'
        : (widget.kind == MediaKind.screenshot || widget.edit ? 'screenshots' : 'captures');
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(backgroundColor: AppTheme.bgDark, elevation: 0),
      body: Center(
        child: !_none
            ? const CircularProgressIndicator(strokeWidth: 2)
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.photo_library_outlined, color: AppTheme.textHint, size: 56),
                  const SizedBox(height: 12),
                  Text('You have no saved $what yet.', textAlign: TextAlign.center,
                      style: captureText(15, color: AppTheme.textSecondary)),
                  TextButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const CaptureMediaLibrary())),
                    child: const Text('Open my captures'),
                  ),
                ]),
              ),
      ),
    );
  }
}
