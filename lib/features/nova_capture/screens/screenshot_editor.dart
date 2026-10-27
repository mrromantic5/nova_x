// lib/features/nova_capture/screens/screenshot_editor.dart
//
// Screenshot Studio editor: crop (free or fixed ratio), rotate, pen,
// highlighter, arrows, text labels, pixelate and blur, with undo/redo.
//
//  - The original screenshot is never changed: "Save" writes a new copy
//    named "<original>_edited".
//  - Redaction is permanent in the saved copy: pixelate/blur areas are drawn
//    from a pixelated/blurred version of the image, so the hidden pixels are
//    not in the exported file. Until that version is ready the area is drawn
//    solid black — never left readable.
//
// All coordinates of edits are kept in the original image's pixels, so the
// result is identical on screen and in the exported file.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/capture_controller.dart';
import '../models/media_asset.dart';
import '../widgets/capture_ui.dart';
import 'media_preview_screen.dart';

// ── Edit model ──────────────────────────────────────────────────────────────

sealed class EditOp {
  const EditOp();
}

class StrokeOp extends EditOp {
  const StrokeOp(this.points, this.color, this.width, {this.highlighter = false});
  final List<Offset> points;
  final Color color;
  final double width;
  final bool highlighter;
}

class ArrowOp extends EditOp {
  const ArrowOp(this.from, this.to, this.color, this.width);
  final Offset from;
  final Offset to;
  final Color color;
  final double width;
}

class TextOp extends EditOp {
  const TextOp(this.at, this.text, this.color, this.size);
  final Offset at;
  final String text;
  final Color color;
  final double size;
}

class RedactOp extends EditOp {
  const RedactOp(this.rect, {required this.blur});
  final Rect rect;
  final bool blur;
}

/// One complete editor state (immutable — undo/redo keep a stack of these).
class EditorDoc {
  const EditorDoc({required this.ops, required this.rotation, required this.crop});
  final List<EditOp> ops;

  /// Quarter turns clockwise (0–3).
  final int rotation;

  /// Crop rectangle in rotated-image pixels.
  final Rect crop;

  EditorDoc copyWith({List<EditOp>? ops, int? rotation, Rect? crop}) =>
      EditorDoc(ops: ops ?? this.ops, rotation: rotation ?? this.rotation, crop: crop ?? this.crop);
}

/// Pure geometry shared by the painter, the gestures and the export (unit-tested).
class EditorGeometry {
  const EditorGeometry(this.width, this.height);
  final double width;
  final double height;

  Size rotatedSize(int rotation) => rotation.isOdd ? Size(height, width) : Size(width, height);

  /// Image pixel → rotated-image pixel.
  Offset toRotated(Offset p, int rotation) => switch (rotation % 4) {
        0 => p,
        1 => Offset(height - p.dy, p.dx),
        2 => Offset(width - p.dx, height - p.dy),
        _ => Offset(p.dy, width - p.dx),
      };

  /// Rotated-image pixel → image pixel.
  Offset fromRotated(Offset r, int rotation) => switch (rotation % 4) {
        0 => r,
        1 => Offset(r.dy, height - r.dx),
        2 => Offset(width - r.dx, height - r.dy),
        _ => Offset(width - r.dy, r.dx),
      };

  /// Applies the rotation to [canvas] so later drawing uses image pixels.
  void applyRotation(Canvas canvas, int rotation) {
    switch (rotation % 4) {
      case 1:
        canvas.translate(height, 0);
        canvas.rotate(math.pi / 2);
      case 2:
        canvas.translate(width, height);
        canvas.rotate(math.pi);
      case 3:
        canvas.translate(0, width);
        canvas.rotate(3 * math.pi / 2);
      default:
        break;
    }
  }

  /// The crop rectangle after one more clockwise quarter turn.
  Rect rotateCrop(Rect crop, int rotation) {
    final hr = rotatedSize(rotation).height;
    return Rect.fromLTRB(hr - crop.bottom, crop.left, hr - crop.top, crop.right);
  }

  /// Largest centred rectangle of [aspect] (w/h) inside [bounds].
  static Rect fitAspect(Size bounds, double aspect) {
    var w = bounds.width;
    var h = w / aspect;
    if (h > bounds.height) {
      h = bounds.height;
      w = h * aspect;
    }
    return Rect.fromLTWH((bounds.width - w) / 2, (bounds.height - h) / 2, w, h);
  }
}

/// Draws the base image and every edit in image pixels.
void paintEditorDoc(Canvas canvas, EditorDoc doc, ui.Image base,
    {ui.Image? pixelated, ui.Image? blurred, EditOp? draft}) {
  final full = Rect.fromLTWH(0, 0, base.width.toDouble(), base.height.toDouble());
  canvas.drawImage(base, Offset.zero, Paint()..filterQuality = FilterQuality.high);
  for (final op in [...doc.ops, if (draft != null) draft]) {
    switch (op) {
      case final StrokeOp o:
        if (o.points.isEmpty) continue;
        final paint = Paint()
          ..color = o.highlighter ? o.color.withOpacity(0.38) : o.color
          ..strokeWidth = o.width
          ..style = PaintingStyle.stroke
          ..strokeCap = o.highlighter ? StrokeCap.square : StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        if (o.points.length == 1) {
          canvas.drawCircle(o.points.first, o.width / 2, paint..style = PaintingStyle.fill);
          continue;
        }
        final path = Path()..moveTo(o.points.first.dx, o.points.first.dy);
        for (var i = 1; i < o.points.length; i++) {
          final p0 = o.points[i - 1];
          final p1 = o.points[i];
          path.quadraticBezierTo(p0.dx, p0.dy, (p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
        }
        path.lineTo(o.points.last.dx, o.points.last.dy);
        canvas.drawPath(path, paint);
      case final ArrowOp o:
        final line = Paint()
          ..color = o.color
          ..strokeWidth = o.width
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(o.from, o.to, line);
        final angle = math.atan2(o.to.dy - o.from.dy, o.to.dx - o.from.dx);
        final head = o.width * 4.5;
        for (final side in const [-0.5, 0.5]) {
          final a = angle + math.pi + side;
          canvas.drawLine(o.to, o.to + Offset(math.cos(a), math.sin(a)) * head, line);
        }
      case final TextOp o:
        final tp = TextPainter(
          text: TextSpan(
            text: o.text,
            style: TextStyle(color: o.color, fontSize: o.size, fontWeight: FontWeight.w800, height: 1.15),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: math.max(40.0, base.width * 0.9));
        final pad = o.size * 0.3;
        final box = Rect.fromLTWH(o.at.dx - pad, o.at.dy - pad, tp.width + pad * 2, tp.height + pad * 2);
        canvas.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(pad)), Paint()..color = const Color(0x8C000000));
        tp.paint(canvas, o.at);
        tp.dispose();
      case final RedactOp o:
        final r = Rect.fromPoints(o.rect.topLeft, o.rect.bottomRight).intersect(full);
        if (r.width <= 0 || r.height <= 0) continue;
        final src = o.blur ? blurred : pixelated;
        if (src == null) {
          canvas.drawRect(r, Paint()..color = Colors.black); // never leave it readable
          continue;
        }
        canvas.save();
        canvas.clipRect(r);
        canvas.drawImageRect(
          src,
          Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
          full,
          Paint()..filterQuality = o.blur ? FilterQuality.medium : FilterQuality.none,
        );
        canvas.restore();
    }
  }
}

// ── Screen ──────────────────────────────────────────────────────────────────

enum EditorTool { crop, pen, highlighter, arrow, text, pixelate, blur }

class ScreenshotEditor extends StatefulWidget {
  const ScreenshotEditor({super.key, required this.asset});
  final MediaAsset asset;

  @override
  State<ScreenshotEditor> createState() => _ScreenshotEditorState();
}

class _ScreenshotEditorState extends State<ScreenshotEditor> {
  final _c = CaptureController.instance;
  ui.Image? _base;
  ui.Image? _pixelated;
  ui.Image? _blurred;
  late EditorGeometry _geo;
  EditorDoc? _doc;
  final List<EditorDoc> _undo = [];
  final List<EditorDoc> _redo = [];
  EditorTool _tool = EditorTool.pen;
  Color _color = const Color(0xFFFF3B4E);
  EditOp? _draft;
  Offset? _redactOrigin;
  bool _failed = false;
  bool _saving = false;
  bool _showOriginal = false;

  // Crop mode
  Rect? _cropDraft;
  double? _aspect; // null = free
  int _dragCorner = -1; // 0 tl, 1 tr, 2 br, 3 bl, 4 move
  Offset? _dragStart;
  Rect? _dragStartRect;
  EditorTool _beforeCrop = EditorTool.pen;

  static const _colors = [
    Color(0xFFFF3B4E), Color(0xFFFFC94D), Color(0xFF00D4FF), Color(0xFF00C853), Color(0xFFFFFFFF), Color(0xFF111111),
  ];

  bool get _dirty => _undo.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _base?.dispose();
    _pixelated?.dispose();
    _blurred?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await _c.readBytes(widget.asset);
      if (bytes == null) throw StateError('read');
      final codec = await ui.instantiateImageCodec(bytes);
      final img = (await codec.getNextFrame()).image;
      if (!mounted) {
        img.dispose();
        return;
      }
      setState(() {
        _base = img;
        _geo = EditorGeometry(img.width.toDouble(), img.height.toDouble());
        _doc = EditorDoc(ops: const [], rotation: 0, crop: Offset.zero & Size(img.width.toDouble(), img.height.toDouble()));
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  // ── Redaction sources ───────────────────────────────────────────────────

  Future<void> _ensureRedactionImages() async {
    final base = _base;
    if (base == null) return;
    final w = base.width.toDouble();
    final h = base.height.toDouble();
    if (_pixelated == null) {
      final block = math.max(8, (math.max(w, h) / 60).round());
      final pw = math.max(1, (w / block).ceil());
      final ph = math.max(1, (h / block).ceil());
      final rec = ui.PictureRecorder();
      Canvas(rec).drawImageRect(base, Rect.fromLTWH(0, 0, w, h), Rect.fromLTWH(0, 0, pw.toDouble(), ph.toDouble()),
          Paint()..filterQuality = FilterQuality.medium);
      final pic = rec.endRecording();
      final img = await pic.toImage(pw, ph);
      pic.dispose();
      if (!mounted) { img.dispose(); return; }
      setState(() => _pixelated = img);
    }
    if (_blurred == null) {
      final sigma = math.max(14.0, math.max(w, h) / 60);
      final rec = ui.PictureRecorder();
      Canvas(rec).drawImage(base, Offset.zero,
          Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp));
      final pic = rec.endRecording();
      final img = await pic.toImage(base.width, base.height);
      pic.dispose();
      if (!mounted) { img.dispose(); return; }
      setState(() => _blurred = img);
    }
  }

  // ── History ─────────────────────────────────────────────────────────────

  void _commit(EditorDoc next) {
    final cur = _doc;
    if (cur == null) return;
    setState(() {
      _undo.add(cur);
      if (_undo.length > 60) _undo.removeAt(0);
      _redo.clear();
      _doc = next;
    });
  }

  void _undoStep() {
    if (_undo.isEmpty || _doc == null) return;
    setState(() {
      _redo.add(_doc!);
      _doc = _undo.removeLast();
    });
  }

  void _redoStep() {
    if (_redo.isEmpty || _doc == null) return;
    setState(() {
      _undo.add(_doc!);
      _doc = _redo.removeLast();
    });
  }

  // ── View mapping ────────────────────────────────────────────────────────

  Rect _viewCrop() {
    final d = _doc!;
    if (_showOriginal) return Offset.zero & _geo.rotatedSize(0);
    if (_tool == EditorTool.crop) return Offset.zero & _geo.rotatedSize(d.rotation);
    return d.crop;
  }

  ({double scale, Offset offset}) _fit(Size viewport) {
    final c = _viewCrop();
    final s = math.min(viewport.width / c.width, viewport.height / c.height);
    return (scale: s, offset: Offset((viewport.width - c.width * s) / 2, (viewport.height - c.height * s) / 2));
  }

  Offset _screenToRotated(Offset p, Size viewport) {
    final f = _fit(viewport);
    return (p - f.offset) / f.scale + _viewCrop().topLeft;
  }

  Offset _screenToImage(Offset p, Size viewport) => _geo.fromRotated(_screenToRotated(p, viewport), _doc!.rotation);

  double get _shortSide => math.min(_geo.width, _geo.height);

  // ── Gestures ────────────────────────────────────────────────────────────

  void _panStart(Offset p, Size vp) {
    if (_doc == null || _showOriginal) return;
    if (_tool == EditorTool.crop) return _cropStart(p, vp);
    final at = _screenToImage(p, vp);
    switch (_tool) {
      case EditorTool.pen:
        _draft = StrokeOp([at], _color, _shortSide * 0.007);
      case EditorTool.highlighter:
        _draft = StrokeOp([at], _color, _shortSide * 0.035, highlighter: true);
      case EditorTool.arrow:
        _draft = ArrowOp(at, at, _color, _shortSide * 0.009);
      case EditorTool.pixelate:
      case EditorTool.blur:
        _redactOrigin = at;
        _draft = RedactOp(Rect.fromPoints(at, at), blur: _tool == EditorTool.blur);
      case EditorTool.text:
      case EditorTool.crop:
        break;
    }
    setState(() {});
  }

  void _panUpdate(Offset p, Size vp) {
    if (_tool == EditorTool.crop) return _cropUpdate(p, vp);
    final d = _draft;
    if (d == null) return;
    final at = _screenToImage(p, vp);
    setState(() {
      _draft = switch (d) {
        final StrokeOp s => StrokeOp([...s.points, at], s.color, s.width, highlighter: s.highlighter),
        final ArrowOp a => ArrowOp(a.from, at, a.color, a.width),
        final RedactOp r => RedactOp(Rect.fromPoints(_redactOrigin ?? r.rect.topLeft, at), blur: r.blur),
        final TextOp t => t,
      };
    });
  }

  void _panEnd() {
    if (_tool == EditorTool.crop) {
      _dragCorner = -1;
      return;
    }
    final d = _draft;
    _draft = null;
    if (d == null || _doc == null) return;
    final keep = switch (d) {
      final ArrowOp a => (a.to - a.from).distance > _shortSide * 0.02,
      final RedactOp r => r.rect.width.abs() > 4 && r.rect.height.abs() > 4,
      _ => true,
    };
    if (!keep) {
      setState(() {});
      return;
    }
    _commit(_doc!.copyWith(ops: [..._doc!.ops, d]));
  }

  Future<void> _tap(Offset p, Size vp) async {
    if (_tool != EditorTool.text || _doc == null || _showOriginal) return;
    final at = _screenToImage(p, vp);
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgElevated,
        title: Text('Add text', style: captureText(17, weight: FontWeight.w800)),
        content: TextField(controller: ctrl, autofocus: true, maxLength: 80, style: captureText(15),
            onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Add')),
        ],
      ),
    );
    ctrl.dispose();
    final t = text?.trim() ?? '';
    if (t.isEmpty || _doc == null) return;
    _commit(_doc!.copyWith(ops: [..._doc!.ops, TextOp(at, t, _color, _shortSide * 0.045)]));
  }

  // ── Crop ────────────────────────────────────────────────────────────────

  void _enterCrop() {
    setState(() {
      _beforeCrop = _tool == EditorTool.crop ? EditorTool.pen : _tool;
      _tool = EditorTool.crop;
      _cropDraft = _doc!.crop;
    });
  }

  void _applyCrop() {
    final next = _cropDraft;
    setState(() => _tool = _beforeCrop);
    if (next != null && next != _doc!.crop) _commit(_doc!.copyWith(crop: next));
  }

  void _cancelCrop() => setState(() {
        _tool = _beforeCrop;
        _cropDraft = null;
      });

  void _setAspect(double? aspect) {
    setState(() {
      _aspect = aspect;
      final bounds = _geo.rotatedSize(_doc!.rotation);
      _cropDraft = aspect == null ? Offset.zero & bounds : EditorGeometry.fitAspect(bounds, aspect);
    });
  }

  void _rotate() {
    final d = _doc!;
    final crop = _tool == EditorTool.crop ? (_cropDraft ?? d.crop) : d.crop;
    final nextCrop = _geo.rotateCrop(crop, d.rotation);
    final next = d.copyWith(rotation: (d.rotation + 1) % 4, crop: nextCrop);
    if (_tool == EditorTool.crop) _cropDraft = nextCrop;
    _commit(next);
  }

  void _cropStart(Offset p, Size vp) {
    final rect = _cropDraft ?? _doc!.crop;
    final f = _fit(vp);
    Offset toScreen(Offset r) => (r - _viewCrop().topLeft) * f.scale + f.offset;
    final corners = [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft].map(toScreen).toList();
    _dragCorner = -1;
    for (var i = 0; i < 4; i++) {
      if ((corners[i] - p).distance < 32) {
        _dragCorner = i;
        break;
      }
    }
    if (_dragCorner < 0 && Rect.fromPoints(corners[0], corners[2]).contains(p)) _dragCorner = 4;
    _dragStart = _screenToRotated(p, vp);
    _dragStartRect = rect;
  }

  void _cropUpdate(Offset p, Size vp) {
    final start = _dragStart;
    final r0 = _dragStartRect;
    if (_dragCorner < 0 || start == null || r0 == null) return;
    final bounds = Offset.zero & _geo.rotatedSize(_doc!.rotation);
    final delta = _screenToRotated(p, vp) - start;
    final minSide = math.max(40.0, _shortSide * 0.06);
    Rect next;
    if (_dragCorner == 4) {
      var moved = r0.shift(delta);
      final dx = moved.left < 0 ? -moved.left : (moved.right > bounds.right ? bounds.right - moved.right : 0.0);
      final dy = moved.top < 0 ? -moved.top : (moved.bottom > bounds.bottom ? bounds.bottom - moved.bottom : 0.0);
      next = moved.shift(Offset(dx, dy));
    } else {
      // The opposite corner stays put.
      final anchor = [r0.bottomRight, r0.bottomLeft, r0.topLeft, r0.topRight][_dragCorner];
      final dragged = [r0.topLeft, r0.topRight, r0.bottomRight, r0.bottomLeft][_dragCorner] + delta;
      var x = dragged.dx.clamp(bounds.left, bounds.right).toDouble();
      var y = dragged.dy.clamp(bounds.top, bounds.bottom).toDouble();
      var w = (x - anchor.dx).abs();
      var h = (y - anchor.dy).abs();
      final aspect = _aspect;
      if (aspect != null) {
        h = w / aspect;
        y = anchor.dy + (dragged.dy >= anchor.dy ? h : -h);
        if (y < bounds.top || y > bounds.bottom) {
          y = y.clamp(bounds.top, bounds.bottom).toDouble();
          h = (y - anchor.dy).abs();
          w = h * aspect;
          x = anchor.dx + (dragged.dx >= anchor.dx ? w : -w);
        }
      }
      if (w < minSide || h < minSide) return;
      next = Rect.fromPoints(anchor, Offset(x, y));
    }
    setState(() => _cropDraft = next.intersect(bounds));
  }

  // ── Save ────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final base = _base;
    final doc = _doc;
    if (base == null || doc == null || _saving) return;
    final format = await _askFormat();
    if (format == null) return;
    setState(() => _saving = true);
    try {
      if (doc.ops.any((o) => o is RedactOp)) await _ensureRedactionImages();
      final crop = doc.crop;
      final w = math.max(1, crop.width.round());
      final h = math.max(1, crop.height.round());
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      canvas.translate(-crop.left, -crop.top);
      _geo.applyRotation(canvas, doc.rotation);
      paintEditorDoc(canvas, doc, base, pixelated: _pixelated, blurred: _blurred);
      final pic = rec.endRecording();
      final out = await pic.toImage(w, h);
      pic.dispose();
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      out.dispose();
      if (data == null) throw StateError('encode');
      final stem = widget.asset.name.contains('.')
          ? widget.asset.name.substring(0, widget.asset.name.lastIndexOf('.'))
          : widget.asset.name;
      final r = await _c.saveEdited(Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes),
          name: '${stem}_edited', format: format.$1, quality: format.$2);
      if (!mounted) return;
      if (!r.success || r.item == null) {
        captureReport(r);
        setState(() => _saving = false);
        return;
      }
      captureToast('Saved as a new copy. Your original is unchanged.', title: 'Edited screenshot saved');
      _undo.clear();
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        settings: const RouteSettings(name: 'nova/capture_preview'),
        builder: (_) => MediaPreviewScreen(asset: r.item!, justCaptured: true),
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      captureToast("The edited screenshot couldn't be saved.", ok: false);
    }
  }

  /// (format, quality) or null when cancelled.
  Future<(String, int)?> _askFormat() async {
    var format = _c.shotSettings.format;
    var quality = _c.shotSettings.quality.toDouble();
    return showModalBottomSheet<(String, int)>(
      context: context,
      backgroundColor: AppTheme.bgElevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Save edited copy', style: captureText(17, weight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('The original screenshot stays as it is.', style: captureText(13, color: AppTheme.textSecondary)),
              const SizedBox(height: 14),
              Wrap(spacing: 8, children: [
                for (final f in const [('png', 'PNG · best quality'), ('jpeg', 'JPEG · smaller'), ('webp', 'WebP · smallest')])
                  ChoiceChip(
                    label: Text(f.$2, style: captureText(12.5, color: format == f.$1 ? Colors.black : AppTheme.textPrimary)),
                    selected: format == f.$1,
                    selectedColor: AppTheme.accentCyan,
                    backgroundColor: AppTheme.bgCard,
                    onSelected: (_) => setSheet(() => format = f.$1),
                  ),
              ]),
              if (format != 'png') ...[
                const SizedBox(height: 10),
                Text('Quality ${quality.round()}', style: captureText(13)),
                Slider(
                  value: quality,
                  min: 40,
                  max: 100,
                  divisions: 12,
                  label: '${quality.round()}',
                  onChanged: (v) => setSheet(() => quality = v),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentCyan, minimumSize: const Size.fromHeight(48)),
                  onPressed: () => Navigator.pop(ctx, (format, quality.round())),
                  child: Text('Save copy', style: captureText(14, weight: FontWeight.w800, color: Colors.black)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgElevated,
        title: Text('Discard your edits?', style: captureText(17, weight: FontWeight.w800)),
        content: Text('The original screenshot is not affected.', style: captureText(14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard', style: TextStyle(color: AppTheme.danger))),
        ],
      ),
    );
    return ok == true;
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && mounted) {
          _undo.clear();
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          title: Text('Edit copy', style: captureText(16, weight: FontWeight.w800)),
          actions: [
            IconButton(
              tooltip: 'Undo',
              onPressed: _undo.isEmpty ? null : _undoStep,
              icon: Icon(Icons.undo_rounded, color: _undo.isEmpty ? AppTheme.textHint : Colors.white),
            ),
            IconButton(
              tooltip: 'Redo',
              onPressed: _redo.isEmpty ? null : _redoStep,
              icon: Icon(Icons.redo_rounded, color: _redo.isEmpty ? AppTheme.textHint : Colors.white),
            ),
            IconButton(
              tooltip: _showOriginal ? 'Show edits' : 'Show original',
              onPressed: _doc == null ? null : () => setState(() => _showOriginal = !_showOriginal),
              icon: Icon(_showOriginal ? Icons.visibility_off_rounded : Icons.compare_rounded, color: Colors.white),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: _doc == null || _saving || _tool == EditorTool.crop ? null : _save,
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Save', style: captureText(15, weight: FontWeight.w800, color: AppTheme.accentCyan)),
              ),
            ),
          ],
        ),
        body: _failed
            ? Center(
                child: Text("This screenshot couldn't be opened.", style: captureText(14, color: AppTheme.textSecondary)))
            : (_doc == null
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : Column(children: [
                    if (_showOriginal)
                      Container(
                        width: double.infinity,
                        color: AppTheme.accentCyan.withOpacity(0.15),
                        padding: const EdgeInsets.all(8),
                        child: Text('Original screenshot (unchanged)', textAlign: TextAlign.center,
                            style: captureText(12.5, weight: FontWeight.w700, color: AppTheme.accentCyan)),
                      ),
                    Expanded(child: _canvas()),
                    _toolbar(),
                  ])),
      ),
    );
  }

  Widget _canvas() => LayoutBuilder(builder: (context, box) {
        final vp = Size(box.maxWidth, box.maxHeight);
        return Semantics(
          image: true,
          label: 'Screenshot being edited. Tool: ${_toolLabel(_tool)}',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) => _panStart(d.localPosition, vp),
            onPanUpdate: (d) => _panUpdate(d.localPosition, vp),
            onPanEnd: (_) => _panEnd(),
            onTapUp: (d) => _tap(d.localPosition, vp),
            child: CustomPaint(
              size: vp,
              painter: _EditorPainter(
                base: _base!,
                doc: _showOriginal ? EditorDoc(ops: const [], rotation: 0, crop: Offset.zero & _geo.rotatedSize(0)) : _doc!,
                geo: _geo,
                view: _viewCrop(),
                draft: _showOriginal ? null : _draft,
                pixelated: _pixelated,
                blurred: _blurred,
                cropDraft: _tool == EditorTool.crop && !_showOriginal ? _cropDraft : null,
              ),
            ),
          ),
        );
      });

  String _toolLabel(EditorTool t) => switch (t) {
        EditorTool.crop => 'Crop',
        EditorTool.pen => 'Pen',
        EditorTool.highlighter => 'Highlight',
        EditorTool.arrow => 'Arrow',
        EditorTool.text => 'Text',
        EditorTool.pixelate => 'Pixelate',
        EditorTool.blur => 'Blur',
      };

  IconData _toolIcon(EditorTool t) => switch (t) {
        EditorTool.crop => Icons.crop_rounded,
        EditorTool.pen => Icons.edit_rounded,
        EditorTool.highlighter => Icons.highlight_rounded,
        EditorTool.arrow => Icons.north_east_rounded,
        EditorTool.text => Icons.text_fields_rounded,
        EditorTool.pixelate => Icons.grid_on_rounded,
        EditorTool.blur => Icons.blur_on_rounded,
      };

  Widget _toolbar() {
    final cropping = _tool == EditorTool.crop;
    return SafeArea(
      top: false,
      child: Container(
        color: const Color(0xFF0B1524),
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (cropping)
            SizedBox(
              height: 44,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
                for (final a in const [('Free', null), ('1:1', 1.0), ('4:3', 4 / 3), ('3:4', 3 / 4), ('16:9', 16 / 9), ('9:16', 9 / 16)])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(a.$1, style: captureText(12.5, color: _aspect == a.$2 ? Colors.black : AppTheme.textPrimary)),
                      selected: _aspect == a.$2,
                      selectedColor: AppTheme.accentCyan,
                      backgroundColor: AppTheme.bgCard,
                      onSelected: (_) => _setAspect(a.$2),
                    ),
                  ),
                IconButton(
                  tooltip: 'Rotate right',
                  onPressed: _rotate,
                  icon: const Icon(Icons.rotate_90_degrees_cw_rounded, color: Colors.white),
                ),
              ]),
            )
          else if (_tool != EditorTool.pixelate && _tool != EditorTool.blur)
            SizedBox(
              height: 44,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                for (final c in _colors)
                  Semantics(
                    button: true,
                    selected: _color == c,
                    label: 'Colour',
                    child: GestureDetector(
                      onTap: () => setState(() => _color = c),
                      child: Container(
                        width: 32,
                        height: 32,
                        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(color: _color == c ? Colors.white : Colors.white24, width: _color == c ? 3 : 1),
                        ),
                      ),
                    ),
                  ),
              ]),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                'Drag over anything private. ${_tool == EditorTool.pixelate ? 'Pixelate' : 'Blur'} is applied to the saved copy permanently.',
                style: captureText(12.5, color: AppTheme.textSecondary),
              ),
            ),
          SizedBox(
            height: 64,
            child: cropping
                ? Row(children: [
                    Expanded(child: TextButton(onPressed: _cancelCrop, child: const Text('Cancel'))),
                    Expanded(
                      child: TextButton(
                        onPressed: _applyCrop,
                        child: Text('Done', style: captureText(14, weight: FontWeight.w800, color: AppTheme.accentCyan)),
                      ),
                    ),
                  ])
                : ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 6), children: [
                    for (final t in EditorTool.values)
                      Semantics(
                        button: true,
                        selected: _tool == t,
                        label: _toolLabel(t),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () async {
                            if (t == EditorTool.crop) {
                              _enterCrop();
                              return;
                            }
                            setState(() => _tool = t);
                            if (t == EditorTool.pixelate || t == EditorTool.blur) await _ensureRedactionImages();
                          },
                          child: Container(
                            width: 66,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: _tool == t ? AppTheme.accentCyan.withOpacity(0.16) : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: ExcludeSemantics(
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(_toolIcon(t), color: _tool == t ? AppTheme.accentCyan : Colors.white, size: 22),
                                const SizedBox(height: 4),
                                Text(_toolLabel(t), style: captureText(11, color: _tool == t ? AppTheme.accentCyan : Colors.white)),
                              ]),
                            ),
                          ),
                        ),
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }
}

class _EditorPainter extends CustomPainter {
  _EditorPainter({
    required this.base,
    required this.doc,
    required this.geo,
    required this.view,
    this.draft,
    this.pixelated,
    this.blurred,
    this.cropDraft,
  });

  final ui.Image base;
  final EditorDoc doc;
  final EditorGeometry geo;
  final Rect view;
  final EditOp? draft;
  final ui.Image? pixelated;
  final ui.Image? blurred;
  final Rect? cropDraft;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width / view.width, size.height / view.height);
    final o = Offset((size.width - view.width * s) / 2, (size.height - view.height * s) / 2);
    canvas.save();
    canvas.translate(o.dx, o.dy);
    canvas.scale(s);
    canvas.translate(-view.left, -view.top);
    canvas.clipRect(view);
    geo.applyRotation(canvas, doc.rotation);
    paintEditorDoc(canvas, doc, base, pixelated: pixelated, blurred: blurred, draft: draft);
    canvas.restore();

    final crop = cropDraft;
    if (crop == null) return;
    Rect toScreen(Rect r) => Rect.fromLTRB(
          (r.left - view.left) * s + o.dx,
          (r.top - view.top) * s + o.dy,
          (r.right - view.left) * s + o.dx,
          (r.bottom - view.top) * s + o.dy,
        );
    final all = toScreen(view);
    final c = toScreen(crop);
    final shade = Paint()..color = const Color(0x99000000);
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(all), Path()..addRect(c)),
      shade,
    );
    canvas.drawRect(c, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    final grid = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(Offset(c.left + c.width * i / 3, c.top), Offset(c.left + c.width * i / 3, c.bottom), grid);
      canvas.drawLine(Offset(c.left, c.top + c.height * i / 3), Offset(c.right, c.top + c.height * i / 3), grid);
    }
    final handle = Paint()..color = AppTheme.accentCyan;
    for (final p in [c.topLeft, c.topRight, c.bottomRight, c.bottomLeft]) {
      canvas.drawCircle(p, 9, handle);
    }
  }

  @override
  bool shouldRepaint(_EditorPainter old) =>
      old.doc != doc ||
      old.draft != draft ||
      old.view != view ||
      old.cropDraft != cropDraft ||
      old.pixelated != pixelated ||
      old.blurred != blurred;
}
