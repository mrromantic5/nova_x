// lib/features/pro/rules_page.dart
//
// The "Rewrite Rules & Low-Data" page: Low-Data & Annoyance Mode switches
// and the user's redirect / block / CSS / JS rules (add, edit, test,
// switch on/off, import / export).

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../cyber/ui/cyber_palette.dart';
import 'page_rules.dart';
import 'pro_tab.dart';
import 'pro_ui.dart';

class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key});

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  final PageRules _r = PageRules.instance;
  final TextEditingController _test = TextEditingController();

  @override
  void initState() {
    super.initState();
    _r.ensureLoaded();
  }

  @override
  void dispose() {
    _test.dispose();
    super.dispose();
  }

  /// Request checking is turned on for open tabs that need it (rules apply
  /// from the next page load).
  void _applyAll() {
    if (_r.blockedPatterns().isEmpty) return;
    for (final t in ProTabs.instance.tabs) {
      final c = t.web;
      if (c != null) {
        c.getSettings().then((cur) {
          if (cur != null && cur.useShouldInterceptRequest != true) {
            cur.useShouldInterceptRequest = true;
            c.setSettings(settings: cur);
          }
        }).catchError((_) {});
      }
    }
  }

  Future<void> _save() async {
    await _r.save();
    _applyAll();
  }

  Future<void> _edit(PageRule? rule, {PageRuleType type = PageRuleType.redirect}) async {
    final pattern = TextEditingController(text: rule?.pattern ?? '');
    final value = TextEditingController(text: rule?.value ?? '');
    final note = TextEditingController(text: rule?.note ?? '');
    var t = rule?.type ?? type;
    final ok = await showProDialog<bool>(context, (ctx) => StatefulBuilder(builder: (ctx, setD) {
          final p = NovaThemeScope.of(ctx);
          return ProDialog(
            icon: Icons.alt_route_rounded,
            title: rule == null ? 'New rule' : 'Edit rule',
            width: 680,
            height: 560,
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
            ],
            child: ListView(padding: const EdgeInsets.all(18), children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final x in PageRuleType.values)
                  ChoiceChip(label: Text(x.label), selected: t == x, onSelected: (_) => setD(() => t = x)),
              ]),
              const SizedBox(height: 14),
              ProField(
                controller: pattern,
                label: t == PageRuleType.css || t == PageRuleType.js ? 'Sites' : 'Address pattern (* = anything)',
                hint: t.patternHint,
                mono: true,
              ),
              const SizedBox(height: 10),
              if (t == PageRuleType.redirect)
                ProField(controller: value, label: 'Send to', hint: r'https://old.reddit.com/$1   ($1 = first *)', mono: true),
              if (t == PageRuleType.css)
                ProField(controller: value, label: 'CSS', hint: '.cookie-bar, .ad { display: none !important; }', mono: true, maxLines: 10, minLines: 6),
              if (t == PageRuleType.js) ...[
                ProField(controller: value, label: 'JavaScript', hint: "document.title = 'Focus';", mono: true, maxLines: 12, minLines: 6),
                const SizedBox(height: 8),
                Text('Runs on the matching sites after they load. Only add code you wrote or fully trust — '
                    'a script can read everything on those pages.', style: p.ui(size: 12, color: p.warning)),
              ],
              if (t == PageRuleType.block)
                Text('Matching requests are stopped before they leave this phone (images, scripts, trackers…). Example: *://*.ads.example.com/*',
                    style: p.ui(size: 12, color: p.textMuted)),
              const SizedBox(height: 10),
              ProField(controller: note, label: 'Note (optional)'),
            ]),
          );
        }));
    if (ok != true || pattern.text.trim().isEmpty) return;
    if (rule == null) {
      _r.rules.add(PageRule(type: t, pattern: pattern.text.trim(), value: value.text, note: note.text.trim()));
    } else {
      rule
        ..type = t
        ..pattern = pattern.text.trim()
        ..value = value.text
        ..note = note.text.trim();
    }
    await _save();
  }

  Future<void> _export() async {
    try {
      final text = const JsonEncoder.withIndent('  ').convert(jsonDecode(_r.encode()));
      final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Export rules', fileName: 'nova-x-rules.json', bytes: Uint8List.fromList(utf8.encode(text)));
      if (path == null) return;
      proToast('Rules exported');
    } catch (_) {
      proToast('Couldn’t export the rules', ok: false);
    }
  }

  Future<void> _import() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['json'], withData: true);
      final bytes = res?.files.single.bytes;
      if (bytes == null) return;
      final before = _r.rules.length;
      _r.decode(utf8.decode(bytes), merge: true);
      await _save();
      proToast('${_r.rules.length - before} rule(s) imported');
    } catch (_) {
      proToast('That file isn’t a NOVA X rules file', ok: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ProPage(
      icon: Icons.tune_rounded,
      title: 'Rewrite Rules & Low-Data',
      guide: 'rewrite_rules',
      subtitle: 'Redirect, block, restyle or script sites; browse lighter.',
      actions: [
        PopupMenuButton<String>(
          onSelected: (v) => v == 'import' ? _import() : _export(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'import', child: Text('Import rules')),
            PopupMenuItem(value: 'export', child: Text('Export rules')),
          ],
        ),
      ],
      child: ListenableBuilder(
        listenable: _r,
        builder: (context, _) {
          final p = NovaThemeScope.of(context);
          final testUrl = _test.text.trim();
          final testTo = testUrl.isEmpty ? null : _r.redirectFor(testUrl);
          return ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 40), children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(onPressed: () => _edit(null), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('New rule')),
            ),
            const SizedBox(height: 14),
            ProCard(
              title: 'Low-Data & Annoyance Mode',
              icon: Icons.data_saver_on_rounded,
              child: Column(children: [
                _switch(p, 'Low-data mode', 'Don’t download images, video files or web fonts — useful on mobile data.',
                    _r.lowData, (v) => _r.lowData = v),
                if (_r.lowData)
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Wrap(spacing: 8, children: [
                      FilterChip(label: const Text('Images'), selected: _r.lowDataImages, onSelected: (v) => _set(() => _r.lowDataImages = v)),
                      FilterChip(label: const Text('Video files'), selected: _r.lowDataVideo, onSelected: (v) => _set(() => _r.lowDataVideo = v)),
                      FilterChip(label: const Text('Web fonts'), selected: _r.lowDataFonts, onSelected: (v) => _set(() => _r.lowDataFonts = v)),
                    ]),
                  ),
                Divider(color: p.border),
                _switch(p, 'Annoyance mode', 'Hide cookie banners, newsletter pop-ups and sticky overlays, and unlock scrolling.',
                    _r.annoyances, (v) => _r.annoyances = v),
                if (_r.annoyances)
                  _switch(p, 'Stop videos that start by themselves', 'Videos play only after you click them.', _r.stopAutoplay,
                      (v) => _r.stopAutoplay = v,
                      indent: true),
                const SizedBox(height: 6),
                Text('Changes apply when a page loads — reload open pages to see them. Works inside NOVA X only. '
                    'Hiding a cookie banner doesn’t accept it.',
                    style: p.ui(size: 11.5, color: p.textFaint)),
              ]),
            ),
            ProCard(
              title: 'Rules (${_r.rules.length})',
              icon: Icons.rule_rounded,
              trailing: PopupMenuButton<String>(
                tooltip: 'Add an example',
                icon: Icon(Icons.auto_fix_high_rounded, color: p.accent),
                onSelected: (v) async {
                  switch (v) {
                    case 'reddit':
                      _r.rules.add(PageRule(type: PageRuleType.redirect, pattern: 'https://www.reddit.com/*', value: r'https://old.reddit.com/$1', note: 'Old Reddit'));
                    case 'shorts':
                      _r.rules.add(PageRule(type: PageRuleType.redirect, pattern: 'https://www.youtube.com/shorts/*', value: r'https://www.youtube.com/watch?v=$1', note: 'Shorts as normal videos'));
                    case 'dc':
                      _r.rules.add(PageRule(type: PageRuleType.block, pattern: '*://*.doubleclick.net/*', note: 'Ad network'));
                    case 'focus':
                      _r.rules.add(PageRule(type: PageRuleType.css, pattern: '*.youtube.com', value: '#related, #comments, ytd-reel-shelf-renderer { display:none !important; }', note: 'YouTube focus'));
                  }
                  await _save();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'reddit', child: Text('Redirect Reddit to old.reddit.com')),
                  PopupMenuItem(value: 'shorts', child: Text('Open YouTube Shorts as normal videos')),
                  PopupMenuItem(value: 'dc', child: Text('Block the DoubleClick ad network')),
                  PopupMenuItem(value: 'focus', child: Text('YouTube focus mode (hide suggestions)')),
                ],
              ),
              child: _r.rules.isEmpty
                  ? Text('No rules yet. Use “New rule” or the ✨ examples.', style: p.ui(size: 12.5, color: p.textMuted))
                  : Column(children: [
                      for (final rule in _r.rules)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                          decoration: BoxDecoration(
                              color: p.surfaceAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
                          child: Row(children: [
                            ProChip(rule.type.label.split(' ').first,
                                color: switch (rule.type) {
                                  PageRuleType.redirect => p.accent,
                                  PageRuleType.block => p.danger,
                                  PageRuleType.css => p.success,
                                  PageRuleType.js => p.warning,
                                }),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(rule.pattern,
                                    style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: rule.enabled ? p.text : p.textFaint),
                                    overflow: TextOverflow.ellipsis),
                                if (rule.type == PageRuleType.redirect)
                                  Text('→ ${rule.value}', style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: p.textMuted), overflow: TextOverflow.ellipsis),
                                if (rule.note.isNotEmpty) Text(rule.note, style: p.ui(size: 11.5, color: p.textMuted)),
                              ]),
                            ),
                            Switch(
                              value: rule.enabled,
                              onChanged: (v) {
                                rule.enabled = v;
                                _save();
                              },
                            ),
                            PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert_rounded, size: 18, color: p.textMuted),
                              onSelected: (v) {
                                if (v == 'edit') {
                                  _edit(rule);
                                } else {
                                  _r.rules.remove(rule);
                                  _save();
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text('Edit')),
                                PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                          ]),
                        ),
                    ]),
            ),
            ProCard(
              title: 'Test a redirect',
              icon: Icons.science_outlined,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ProField(controller: _test, hint: 'https://www.reddit.com/r/flutter', mono: true, onChanged: (_) => setState(() {})),
                if (testUrl.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  testTo == null
                      ? Text('No redirect rule matches.', style: p.ui(size: 12.5, color: p.textMuted))
                      : SelectableText('→ $testTo', style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: p.success)),
                ],
              ]),
            ),
          ]);
        },
      ),
    );
  }

  void _set(VoidCallback f) {
    f();
    _save();
  }

  Widget _switch(NovaPalette p, String title, String sub, bool value, ValueChanged<bool> set, {bool indent = false}) => Padding(
        padding: EdgeInsets.only(left: indent ? 16 : 0),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title, style: p.ui(size: 13.5, weight: FontWeight.w600, color: p.text)),
          subtitle: Text(sub, style: p.ui(size: 12, color: p.textMuted)),
          value: value,
          onChanged: (v) => _set(() => set(v)),
        ),
      );
}
