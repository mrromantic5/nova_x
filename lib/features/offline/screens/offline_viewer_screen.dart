// lib/features/offline/screens/offline_viewer_screen.dart
//
// Renders a saved offline page (MHTML web-archive) from local storage in a
// WebView — works with no network connection.

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/theme/app_theme.dart';

class OfflineViewerScreen extends StatelessWidget {
  final String path;
  final String title;
  const OfflineViewerScreen({super.key, required this.path, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
            Row(children: [
              const Icon(Icons.offline_pin_rounded, color: Color(0xFF00C853), size: 12),
              const SizedBox(width: 4),
              Text('Offline copy',
                  style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11)),
            ]),
          ],
        ),
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri('file://$path')),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          allowFileAccess: true,
          allowContentAccess: true,
          allowFileAccessFromFileURLs: true,
          allowUniversalAccessFromFileURLs: true,
          transparentBackground: true,
        ),
      ),
    );
  }
}
