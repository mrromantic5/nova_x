// lib/core/widgets/nova_toast.dart
//
// App-wide bottom toast (rewards credited / taken back, limits…). Shown on the
// root navigator's overlay, so it works from any screen and from services
// with no BuildContext. Toasts queue one after another.

import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

enum NovaToastKind { success, reward, warning, info }

class NovaToast {
  NovaToast._();

  /// Set once by the app (main.dart's navigatorKey).
  static GlobalKey<NavigatorState>? navigatorKey;

  static final Queue<_ToastData> _queue = Queue();
  static bool _showing = false;

  static void show(
    String message, {
    String? title,
    NovaToastKind kind = NovaToastKind.info,
    IconData? icon,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (message.trim().isEmpty) return;
    _queue.add(_ToastData(message, title, kind, icon, duration));
    if (!_showing) _next();
  }

  static void _next() {
    if (navigatorKey == null) {
      // Not in the main app (e.g. NOVA's floating window): nothing to show on.
      _queue.clear();
      _showing = false;
      return;
    }
    final overlay = navigatorKey?.currentState?.overlay;
    if (_queue.isEmpty || overlay == null) {
      _showing = false;
      if (_queue.isNotEmpty) {
        // The app isn't ready yet (cold start): try again shortly.
        Timer(const Duration(milliseconds: 800), () {
          if (!_showing) _next();
        });
      }
      return;
    }
    _showing = true;
    final data = _queue.removeFirst();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastView(
        data: data,
        onDone: () {
          entry.remove();
          _next();
        },
      ),
    );
    overlay.insert(entry);
  }
}

class _ToastData {
  _ToastData(this.message, this.title, this.kind, this.icon, this.duration);
  final String message;
  final String? title;
  final NovaToastKind kind;
  final IconData? icon;
  final Duration duration;
}

class _ToastView extends StatefulWidget {
  const _ToastView({required this.data, required this.onDone});
  final _ToastData data;
  final VoidCallback onDone;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _timer = Timer(widget.data.duration, _close);
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    if (mounted) await _c.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  (Color, IconData) _style() => switch (widget.data.kind) {
        NovaToastKind.reward => (const Color(0xFFFFC83D), Icons.monetization_on_rounded),
        NovaToastKind.success => (AppTheme.success, Icons.check_circle_rounded),
        NovaToastKind.warning => (const Color(0xFFFF6B6B), Icons.error_outline_rounded),
        NovaToastKind.info => (AppTheme.accentCyan, Icons.info_outline_rounded),
      };

  @override
  Widget build(BuildContext context) {
    final (color, defaultIcon) = _style();
    final bottom = MediaQuery.of(context).padding.bottom + 18;
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
    return Positioned(
      left: 16,
      right: 16,
      bottom: bottom,
      child: AnimatedBuilder(
        animation: curve,
        builder: (_, child) => Opacity(
          opacity: _c.value.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, (1 - curve.value) * 40), child: child),
        ),
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: _close,
            onVerticalDragEnd: (_) => _close(),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
              decoration: BoxDecoration(
                color: const Color(0xF2141A26),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: color.withOpacity(0.55)),
                boxShadow: [
                  BoxShadow(color: color.withOpacity(0.22), blurRadius: 24, spreadRadius: 1),
                  const BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 6)),
                ],
              ),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.data.icon ?? defaultIcon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.data.title != null)
                        Text(widget.data.title!,
                            style: GoogleFonts.spaceGrotesk(
                                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                      Text(widget.data.message,
                          style: GoogleFonts.inter(
                              color: Colors.white.withOpacity(0.82), fontSize: 12.5, height: 1.35)),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
