// lib/features/nova_capture/screens/media_actions.dart
//
// Actions on one saved capture. Deleting always asks first; sharing and
// exporting happen only when the user taps them (Android's own share sheet /
// "save to" picker). Nothing is uploaded by NOVA X.

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/capture_controller.dart';
import '../models/media_asset.dart';
import '../services/media_library_service.dart';
import '../widgets/capture_flows.dart';
import '../widgets/capture_ui.dart';
import 'screenshot_editor.dart';

class MediaActions {
  MediaActions._();

  static CaptureController get _c => CaptureController.instance;
  static MediaLibraryService get _lib => MediaLibraryService.instance;

  static Future<void> sheet(BuildContext context, MediaAsset a, {VoidCallback? onDeleted}) async {
    final fav = _lib.isFavorite(a.uri);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bgElevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Text(a.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: captureText(15, weight: FontWeight.w700)),
            ),
            _tile(ctx, Icons.open_in_full_rounded, 'Open', () => CaptureFlows.openPreview(context, a)),
            if (a.isImage)
              _tile(ctx, Icons.edit_rounded, 'Edit (crop, draw, blur)', () => openEditor(context, a)),
            _tile(ctx, Icons.share_rounded, 'Share', () async => captureReport(await _c.share(a))),
            if (a.isImage)
              _tile(ctx, Icons.copy_rounded, 'Copy image', () async => captureReport(await _c.copyImage(a),
                  success: 'Copied. Paste it where you need it.')),
            _tile(ctx, fav ? Icons.star_rounded : Icons.star_border_rounded, fav ? 'Remove from favourites' : 'Add to favourites',
                () async {
              await _lib.setFavorite(a.uri, !fav);
              _c.libraryVersion.value++;
            }),
            _tile(ctx, Icons.folder_rounded, 'Move to folder', () => pickFolder(context, a)),
            _tile(ctx, Icons.drive_file_rename_outline_rounded, 'Rename', () => rename(context, a)),
            _tile(ctx, Icons.save_alt_rounded, 'Save a copy to…', () async =>
                captureReport(await _c.exportTo(a), success: 'Saved.')),
            _tile(ctx, Icons.open_in_new_rounded, 'Open in another app', () async => captureReport(await _c.openExternal(a))),
            _tile(ctx, Icons.info_outline_rounded, 'Details', () => details(context, a)),
            _tile(ctx, Icons.delete_outline_rounded, 'Delete', () => delete(context, a, onDeleted: onDeleted),
                color: AppTheme.danger),
          ]),
        ),
      ),
    );
  }

  static Widget _tile(BuildContext ctx, IconData icon, String label, VoidCallback onTap, {Color? color}) => ListTile(
        leading: Icon(icon, color: color ?? AppTheme.textPrimary),
        title: Text(label, style: captureText(14, color: color ?? AppTheme.textPrimary)),
        onTap: () {
          Navigator.pop(ctx);
          onTap();
        },
      );

  static Future<void> openEditor(BuildContext context, MediaAsset a) => Navigator.of(context).push(MaterialPageRoute(
        settings: const RouteSettings(name: 'nova/capture_editor'),
        builder: (_) => ScreenshotEditor(asset: a),
      ));

  static Future<void> rename(BuildContext context, MediaAsset a) async {
    final dot = a.name.lastIndexOf('.');
    final ctrl = TextEditingController(text: dot > 0 ? a.name.substring(0, dot) : a.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgElevated,
        title: Text('Rename', style: captureText(17, weight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 80,
          style: captureText(14),
          decoration: InputDecoration(
            suffixText: dot > 0 ? a.name.substring(dot) : null,
            helperText: 'Letters, numbers, spaces, - and _',
            helperStyle: captureText(11.5, color: AppTheme.textHint),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Rename')),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.trim().isEmpty) return;
    captureReport(await _c.rename(a, name.trim()), success: 'Renamed.');
  }

  static Future<bool> delete(BuildContext context, MediaAsset a, {VoidCallback? onDeleted}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgElevated,
        title: Text('Delete ${a.isVideo ? 'recording' : 'screenshot'}?', style: captureText(17, weight: FontWeight.w800)),
        content: Text('“${a.name}” will be deleted from your phone. This can’t be undone.', style: captureText(14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    final r = await _c.delete(a);
    captureReport(r, success: 'Deleted.');
    if (r.success) onDeleted?.call();
    return r.success;
  }

  static Future<void> pickFolder(BuildContext context, MediaAsset a) async {
    final current = _lib.categories[a.uri];
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.bgElevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text('Folder', style: captureText(16, weight: FontWeight.w800)),
          ),
          ListTile(
            leading: Icon(current == null ? Icons.radio_button_checked : Icons.radio_button_off, color: AppTheme.accentCyan),
            title: Text('No folder', style: captureText(14)),
            onTap: () => Navigator.pop(ctx, ''),
          ),
          for (final f in _lib.folders)
            ListTile(
              leading: Icon(current == f ? Icons.radio_button_checked : Icons.radio_button_off, color: AppTheme.accentCyan),
              title: Text(f, style: captureText(14)),
              onTap: () => Navigator.pop(ctx, f),
            ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_rounded, color: AppTheme.textPrimary),
            title: Text('New folder…', style: captureText(14)),
            onTap: () => Navigator.pop(ctx, '\u0000new'),
          ),
        ]),
      ),
    );
    if (picked == null) return;
    var folder = picked;
    if (picked == '\u0000new') {
      if (!context.mounted) return;
      final ctrl = TextEditingController();
      final name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.bgElevated,
          title: Text('New folder', style: captureText(17, weight: FontWeight.w800)),
          content: TextField(controller: ctrl, autofocus: true, maxLength: 24, style: captureText(14),
              onSubmitted: (v) => Navigator.pop(ctx, v)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Create')),
          ],
        ),
      );
      ctrl.dispose();
      if (name == null) return;
      final clean = MediaLibrary.cleanCategory(name);
      if (clean == null || !await _lib.addFolder(clean)) {
        captureToast('Use 1–24 letters, numbers or spaces for the folder name.', ok: false);
        return;
      }
      folder = clean;
    }
    await _lib.setCategory(a.uri, folder.isEmpty ? null : folder);
    _c.libraryVersion.value++;
    captureToast(folder.isEmpty ? 'Removed from folder.' : 'Moved to $folder.');
  }

  static Future<void> details(BuildContext context, MediaAsset a) async {
    final meta = _lib.metadataFor(a.uri);
    final rows = <(String, String)>[
      ('Name', a.name),
      ('Type', a.isVideo ? 'Screen recording (${a.mime})' : 'Screenshot (${a.mime})'),
      ('Saved', formatCaptureDate(a.created)),
      ('Size', formatBytes(a.sizeBytes)),
      if (a.width > 0) ('Resolution', '${a.width} × ${a.height}'),
      if (a.isVideo && a.durationMs > 0) ('Length', formatDuration(Duration(milliseconds: a.durationMs))),
      ('Location', a.isVideo ? 'Movies › NOVA X › Recordings' : 'Pictures › NOVA X › Screenshots'),
      if (meta != null && meta.title.isNotEmpty) ('Page', meta.title),
      if (meta != null && meta.url.isNotEmpty) ('Address', meta.url),
    ];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bgElevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Details', style: captureText(16, weight: FontWeight.w800)),
            const SizedBox(height: 10),
            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 92, child: Text(k, style: captureText(12.5, color: AppTheme.textHint))),
                  Expanded(child: SelectableText(v, style: captureText(13))),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}
