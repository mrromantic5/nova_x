// lib/features/xcoder/widgets/xcoder_keybar.dart
//
// Extra keys above the phone keyboard (what phone keyboards make hard to
// type in code): Tab, brackets, symbols, arrows, undo/redo and quick actions.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../editor/ace_editor.dart';
import 'xcoder_ui.dart';

class XKeyBar extends StatelessWidget {
  const XKeyBar({super.key, required this.ace, required this.onFind, required this.onComplete, required this.onAi});
  final AceController ace;
  final VoidCallback onFind;
  final VoidCallback onComplete;
  final VoidCallback? onAi;

  static const _symbols = ['{', '}', '(', ')', '[', ']', '<', '>', ';', ':', '=', '"', "'", '`', '/', '\\', '|', '&', '!', '?',
    '\$', '#', '%', '*', '+', '-', '_', '@', '~', '^', ','];

  Widget _k(String label, VoidCallback onTap, {double width = 38, Color color = XC.text, IconData? icon, String? tip}) {
    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: width,
          height: 38,
          child: Center(
            child: icon != null
                ? Icon(icon, size: 18, color: color)
                : Text(label, style: XC.mono(15, color: color, weight: FontWeight.w600)),
          ),
        ),
      ),
    );
    return tip == null ? child : Tooltip(message: tip, child: child);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: const BoxDecoration(color: XC.bar, border: Border(top: BorderSide(color: XC.border))),
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 4), children: [
        _k('⇥', () => ace.typeKey('Tab'), width: 44, color: XC.accent, tip: 'Tab (indent)'),
        _k('⇤', () => ace.typeKey('ShiftTab'), width: 40, color: XC.dim, tip: 'Outdent'),
        _k('', () => ace.typeKey('Left'), icon: Icons.keyboard_arrow_left_rounded, tip: 'Left'),
        _k('', () => ace.typeKey('Up'), icon: Icons.keyboard_arrow_up_rounded, tip: 'Up'),
        _k('', () => ace.typeKey('Down'), icon: Icons.keyboard_arrow_down_rounded, tip: 'Down'),
        _k('', () => ace.typeKey('Right'), icon: Icons.keyboard_arrow_right_rounded, tip: 'Right'),
        for (final s in _symbols) _k(s, () => ace.typeKey(s)),
        _k('', () => ace.cmd('undo'), icon: Icons.undo_rounded, color: XC.dim, tip: 'Undo'),
        _k('', () => ace.cmd('redo'), icon: Icons.redo_rounded, color: XC.dim, tip: 'Redo'),
        _k('', onComplete, icon: Icons.lightbulb_outline_rounded, color: XC.warning, tip: 'Suggestions'),
        _k('', onFind, icon: Icons.search_rounded, color: XC.dim, tip: 'Find / replace'),
        _k('', () => ace.cmd('toggleComment'), icon: Icons.comment_outlined, color: XC.dim, tip: 'Toggle comment'),
        _k('', () => ace.cmd('duplicate'), icon: Icons.control_point_duplicate_rounded, color: XC.dim, tip: 'Duplicate line'),
        _k('', () => ace.cmd('selectNextOccurrence'), icon: Icons.select_all_rounded, color: XC.dim, tip: 'Add next occurrence (multi-cursor)'),
        if (onAi != null) _k('', onAi!, icon: Icons.auto_awesome_rounded, color: const Color(0xFFFFD54F), tip: 'NOVA'),
        _k('', () => ace.blur(), icon: Icons.keyboard_hide_outlined, color: XC.dim, tip: 'Hide keyboard'),
      ]),
    );
  }
}
