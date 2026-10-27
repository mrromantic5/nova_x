// lib/features/nova_capture/widgets/capture_action_sheet.dart
//
// "NOVA Capture" from the browser menu: the two screenshot modes are clearly
// separated (this page, through the browser — no permission; the entire
// screen, through Android's screen-capture dialog) plus recording.

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/capture_controller.dart';
import '../screens/capture_dashboard.dart';
import '../services/webpage_capture_service.dart';
import 'capture_flows.dart';
import 'capture_ui.dart';

class CaptureActionSheet {
  CaptureActionSheet._();

  static Future<void> show(BuildContext context, {WebCaptureTarget? page}) async {
    final c = CaptureController.instance;
    await c.init();
    if (!context.mounted) return;
    final recording = c.state.isActive;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.bgElevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Text('NOVA Capture', style: captureText(17, weight: FontWeight.w800)),
          ),
          if (page != null) ...[
            _group('This web page — no permission needed'),
            _item(ctx, 'page', Icons.crop_free_rounded, 'Screenshot this page', 'What you see in this tab'),
            _item(ctx, 'full', Icons.view_day_rounded, 'Full-page screenshot', 'The whole page, top to bottom'),
          ],
          _group('Your entire screen — Android will ask first'),
          _item(ctx, 'screen', Icons.screenshot_monitor_rounded, 'Capture entire screen', 'One screenshot of the screen'),
          _item(ctx, 'record', Icons.fiber_manual_record_rounded,
              recording ? 'Recording in progress' : 'Record screen',
              recording ? 'Open the controls' : 'With ${c.settings.audio.label.toLowerCase()}',
              color: CaptureColors.record),
          const Divider(color: AppTheme.divider, height: 18),
          _item(ctx, 'studio', Icons.photo_library_rounded, 'Open NOVA Capture', 'Recent captures, library and settings'),
          const SizedBox(height: 6),
        ]),
      ),
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case 'page':
        if (page != null) await CaptureFlows.captureWebpage(context, page, fullPage: false);
      case 'full':
        if (page != null) await CaptureFlows.captureWebpage(context, page, fullPage: true);
      case 'screen':
        await CaptureFlows.captureScreen(context);
      case 'record':
        if (recording) {
          await _openStudio(context);
        } else {
          await CaptureFlows.startRecording(context);
        }
      case 'studio':
        await _openStudio(context);
    }
  }

  static Future<void> _openStudio(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(
        settings: const RouteSettings(name: 'nova/capture'),
        builder: (_) => const CaptureDashboard(),
      ));

  static Widget _group(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
        child: Text(text, style: captureText(12, weight: FontWeight.w700, color: AppTheme.textHint)),
      );

  static Widget _item(BuildContext ctx, String id, IconData icon, String title, String subtitle,
          {Color color = AppTheme.accentCyan}) =>
      ListTile(
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(title, style: captureText(14.5, weight: FontWeight.w600)),
        subtitle: Text(subtitle, style: captureText(12, color: AppTheme.textSecondary)),
        onTap: () => Navigator.pop(ctx, id),
      );
}
