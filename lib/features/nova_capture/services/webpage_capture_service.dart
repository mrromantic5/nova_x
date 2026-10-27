// lib/features/nova_capture/services/webpage_capture_service.dart
//
// Screenshots of the web page open in NOVA X, through the browser engine's own
// API (InAppWebViewController.takeScreenshot) — no screen-capture permission
// is involved, and only NOVA X's page is captured.
//
//  - Visible page: exactly what the tab shows, PNG (lossless).
//  - Full page: the page is scrolled one screen at a time, each screen is
//    captured, and the pieces are joined. Limits (honest, documented):
//      · at most 10 screens and about 8 megapixels, so long pages are scaled
//        down or cut at the bottom (the user is told);
//      · headers that stay fixed on screen appear in every piece;
//      · content the engine can't draw (some video, cross-origin frames that
//        block it, protected media) is captured as the engine shows it.
//    The original scroll position is restored afterwards.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/capture_models.dart';

/// The browser tab NOVA Capture can photograph (registered by BrowserView).
abstract class WebCaptureTarget {
  InAppWebViewController? get captureController;
  String get captureTitle;
  String get captureUrl;
  bool get captureIncognito;

  /// 0..1 page loading progress.
  double get captureProgress;
}

class WebCaptureOutcome {
  const WebCaptureOutcome.ok(this.bytes, {this.truncated = false, this.scaled = false}) : errorCode = null;
  const WebCaptureOutcome.error(this.errorCode)
      : bytes = null,
        truncated = false,
        scaled = false;

  final Uint8List? bytes;
  final String? errorCode;

  /// Full page only: the bottom of a very long page was left out.
  final bool truncated;

  /// Full page only: the image was scaled down to fit the memory budget.
  final bool scaled;

  bool get ok => bytes != null;
}

class WebpageCaptureService {
  WebpageCaptureService._();

  // Browser tabs can be stacked (a link opens another BrowserView on top):
  // the newest one still open is the one on screen.
  static final List<WebCaptureTarget> _open = [];

  /// The tab currently on screen (null when no browser tab is open).
  static WebCaptureTarget? get current => _open.isEmpty ? null : _open.last;

  static void register(WebCaptureTarget t) {
    _open.remove(t);
    _open.add(t);
  }

  static void unregister(WebCaptureTarget t) => _open.remove(t);

  static const int maxScreens = 10;
  static const int pixelBudget = 8000000;

  static bool _isWebPage(String url) => url.startsWith('https://') || url.startsWith('http://');

  /// What the tab shows right now.
  static Future<WebCaptureOutcome> captureVisible(WebCaptureTarget t) async {
    final c = t.captureController;
    if (c == null || !_isWebPage(t.captureUrl)) return const WebCaptureOutcome.error(CaptureErrorCode.noPage);
    try {
      final png = await c.takeScreenshot(
          screenshotConfiguration: ScreenshotConfiguration(compressFormat: CompressFormat.PNG));
      if (png == null || png.isEmpty) return const WebCaptureOutcome.error(CaptureErrorCode.webCapture);
      return WebCaptureOutcome.ok(png);
    } catch (_) {
      return const WebCaptureOutcome.error(CaptureErrorCode.webCapture);
    }
  }

  /// The whole page, top to bottom (see the limits above).
  static Future<WebCaptureOutcome> captureFullPage(WebCaptureTarget t, {void Function(double)? onProgress}) async {
    final c = t.captureController;
    if (c == null || !_isWebPage(t.captureUrl)) return const WebCaptureOutcome.error(CaptureErrorCode.noPage);

    final info = await _pageInfo(c);
    if (info == null) return captureVisible(t);
    final (pageH, viewH, startY) = info;
    if (viewH <= 0 || pageH <= viewH * 1.05) return captureVisible(t);

    final neededScreens = (pageH / viewH).ceil();
    final screens = math.min(neededScreens, maxScreens);
    final truncated = neededScreens > maxScreens;
    final coveredH = math.min(pageH, screens * viewH);

    final shots = <(ui.Image, double)>[];
    var scaled = false;
    try {
      for (var i = 0; i < screens; i++) {
        final y = math.min(i * viewH, math.max(0.0, pageH - viewH));
        await c.evaluateJavascript(source: 'window.scrollTo(0, ${y.toStringAsFixed(0)});');
        await Future<void>.delayed(const Duration(milliseconds: 320));
        final png = await c.takeScreenshot(
            screenshotConfiguration: ScreenshotConfiguration(compressFormat: CompressFormat.PNG));
        if (png == null || png.isEmpty) throw StateError('capture');
        final actualY = await _scrollY(c) ?? y;

        // Size of one CSS pixel in the screenshot; decode smaller if the whole
        // page would exceed the memory budget.
        final probe = await ui.instantiateImageCodec(png);
        final first = (await probe.getNextFrame()).image;
        final pxPerCss = first.height / viewH;
        final fullW = first.width;
        final fullH = (coveredH * pxPerCss).round();
        final scale = math.min(1.0, math.sqrt(pixelBudget / (fullW * fullH)));
        ui.Image img = first;
        if (scale < 0.999) {
          scaled = true;
          first.dispose();
          final codec = await ui.instantiateImageCodec(png, targetWidth: math.max(1, (fullW * scale).round()));
          img = (await codec.getNextFrame()).image;
        }
        shots.add((img, actualY));
        onProgress?.call((i + 1) / screens);
      }
    } catch (_) {
      for (final s in shots) {
        s.$1.dispose();
      }
      await _scrollTo(c, startY);
      return const WebCaptureOutcome.error(CaptureErrorCode.webCapture);
    }
    await _scrollTo(c, startY);

    try {
      final w = shots.first.$1.width;
      final pxPerCss = shots.first.$1.height / viewH;
      final outH = math.max(1, (coveredH * pxPerCss).round());
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      for (final (img, y) in shots) {
        canvas.drawImage(img, ui.Offset(0, y * pxPerCss), ui.Paint());
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(w, outH);
      picture.dispose();
      for (final s in shots) {
        s.$1.dispose();
      }
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return const WebCaptureOutcome.error(CaptureErrorCode.webCapture);
      return WebCaptureOutcome.ok(data.buffer.asUint8List(), truncated: truncated, scaled: scaled);
    } catch (_) {
      for (final s in shots) {
        s.$1.dispose();
      }
      return const WebCaptureOutcome.error(CaptureErrorCode.webCapture);
    }
  }

  /// (page height, viewport height, scroll y) in CSS pixels.
  static Future<(double, double, double)?> _pageInfo(InAppWebViewController c) async {
    try {
      final r = await c.evaluateJavascript(source: '''
(function(){try{var d=document.documentElement,b=document.body;
return JSON.stringify({h:Math.max(d.scrollHeight,b?b.scrollHeight:0,d.offsetHeight),vh:window.innerHeight,y:window.scrollY||0});}
catch(e){return null;}})()''');
      final m = r is String ? jsonDecode(r) : r;
      if (m is! Map) return null;
      final h = m['h'];
      final vh = m['vh'];
      final y = m['y'];
      if (h is! num || vh is! num) return null;
      return (h.toDouble(), vh.toDouble(), y is num ? y.toDouble() : 0.0);
    } catch (_) {
      return null;
    }
  }

  static Future<double?> _scrollY(InAppWebViewController c) async {
    try {
      final r = await c.evaluateJavascript(source: 'window.scrollY||0');
      return r is num ? r.toDouble() : double.tryParse('$r');
    } catch (_) {
      return null;
    }
  }

  static Future<void> _scrollTo(InAppWebViewController c, double y) async {
    try {
      await c.evaluateJavascript(source: 'window.scrollTo(0, ${y.toStringAsFixed(0)});');
    } catch (_) {}
  }
}
