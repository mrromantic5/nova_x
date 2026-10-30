// lib/features/xcoder/widgets/xcoder_settings.dart
//
// Editor settings: theme, font size, tabs, word wrap, autocomplete, line
// numbers, whitespace, auto save, format on save, extra keys row.

import 'package:flutter/material.dart';

import 'xcoder_ui.dart';

Future<void> showXSettings(BuildContext context, XSettings s, ValueChanged<XSettings> onChanged) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: XC.side,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => StatefulBuilder(builder: (ctx, set) {
        void change(void Function() f) {
          set(f);
          onChanged(s);
        }

        Widget sw(String title, String sub, bool v, void Function(bool) on) => SwitchListTile(
              value: v,
              onChanged: (x) => change(() => on(x)),
              activeColor: XC.accent,
              dense: true,
              title: Text(title, style: XC.ui(14, weight: FontWeight.w600)),
              subtitle: sub.isEmpty ? null : Text(sub, style: XC.ui(12, color: XC.faint)),
            );

        Widget head(String t) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
              child: Text(t, style: XC.ui(11.5, color: XC.dim, weight: FontWeight.w800)),
            );

        return ListView(controller: scroll, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(children: [
              const Icon(Icons.tune_rounded, color: XC.accent),
              const SizedBox(width: 10),
              Text('Editor settings', style: XC.ui(17, weight: FontWeight.w800)),
            ]),
          ),
          head('THEME'),
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (final e in kAceThemes.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: s.theme == e.key,
                    onSelected: (_) => change(() => s.theme = e.key),
                    selectedColor: XC.status,
                    backgroundColor: XC.bg,
                    labelStyle: XC.ui(12.5, color: s.theme == e.key ? Colors.white : XC.dim),
                    side: const BorderSide(color: XC.border),
                    showCheckmark: false,
                  ),
                ),
            ]),
          ),
          head('TEXT'),
          ListTile(
            dense: true,
            title: Text('Font size', style: XC.ui(14, weight: FontWeight.w600)),
            subtitle: Slider(
              value: s.fontSize,
              min: 9,
              max: 24,
              divisions: 15,
              label: '${s.fontSize.round()}',
              activeColor: XC.accent,
              onChanged: (v) => change(() => s.fontSize = v),
            ),
            trailing: Text('${s.fontSize.round()} px', style: XC.mono(13)),
          ),
          ListTile(
            dense: true,
            title: Text('Tab size', style: XC.ui(14, weight: FontWeight.w600)),
            trailing: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 2, label: Text('2')),
                ButtonSegment(value: 4, label: Text('4')),
                ButtonSegment(value: 8, label: Text('8')),
              ],
              selected: {s.tabSize},
              showSelectedIcon: false,
              onSelectionChanged: (v) => change(() => s.tabSize = v.first),
            ),
          ),
          sw('Insert spaces', 'Tab key inserts spaces instead of a tab character', s.softTabs, (v) => s.softTabs = v),
          sw('Word wrap', 'Wrap long lines to the screen width', s.wrap, (v) => s.wrap = v),
          sw('Show whitespace', '', s.invisibles, (v) => s.invisibles = v),
          head('EDITING'),
          sw('Suggestions while typing', 'Keywords, snippets, words from this file and the project', s.liveAutocomplete,
              (v) => s.liveAutocomplete = v),
          sw('Line numbers', '', s.lineNumbers, (v) => s.lineNumbers = v),
          sw('Relative line numbers', '', s.relativeNumbers, (v) => s.relativeNumbers = v),
          sw('Extra keys row', 'Tab, brackets, symbols and arrows above the keyboard', s.keyBar, (v) => s.keyBar = v),
          head('FILES'),
          sw('Auto save', 'Saves changes a moment after you stop typing', s.autoSave, (v) => s.autoSave = v),
          sw('Format on save', 'HTML, CSS, JavaScript, TypeScript, JSON, PHP, XML', s.formatOnSave, (v) => s.formatOnSave = v),
          const SizedBox(height: 30),
        ]);
      }),
    ),
  );
}
