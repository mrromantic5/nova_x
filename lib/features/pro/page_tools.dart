// lib/features/pro/page_tools.dart
//
// NOVA X Page tools (3.13.0, the Android version of the PC's "NOVA Tools"
// button): tools for the page in the current tab (Scam Explainer, Security
// Lens, Site Data X-ray, Safe NOVA Agent), quick switches (Low-data,
// Annoyance mode) and the Pro pages (Open a link safely, Rewrite Rules).
// Opened from the browser menu › Page tools.

import 'package:flutter/material.dart';

import '../cyber/ui/cyber_palette.dart';
import '../guide/guide_screen.dart';
import 'nova_agent.dart';
import 'open_safely.dart';
import 'page_rules.dart';
import 'pro_tab.dart';
import 'pro_ui.dart';
import 'rules_page.dart';
import 'scam_check.dart';
import 'security_lens.dart';
import 'site_xray.dart';

class ProTools {
  ProTools._();

  static bool _webTab(ProTab? t) => t != null && t.isWeb && t.web != null;

  static Future<void> scam(BuildContext context, ProTab? t) async {
    if (!_webTab(t)) {
      proNeedsPage(context);
      return;
    }
    await showScamExplainer(context, t!);
  }

  static Future<void> lens(BuildContext context, ProTab? t) async {
    if (!_webTab(t)) {
      proNeedsPage(context);
      return;
    }
    await showSecurityLens(context, t!);
  }

  static Future<void> xray(BuildContext context, ProTab? t) async {
    if (!_webTab(t)) {
      proNeedsPage(context);
      return;
    }
    await showSiteXray(context, t!);
  }

  static void agent(BuildContext context, ProTab? t) {
    if (!_webTab(t)) {
      proNeedsPage(context);
      return;
    }
    NovaAgent.instance.show(context, t!);
  }

  static Future<void> toggleLowData(ProTab? t) async {
    final r = PageRules.instance;
    await r.ensureLoaded();
    r.lowData = !r.lowData;
    await r.save();
    final c = t?.web;
    if (r.lowData && c != null) {
      try {
        final cur = await c.getSettings();
        if (cur != null && cur.useShouldInterceptRequest != true) {
          cur.useShouldInterceptRequest = true;
          await c.setSettings(settings: cur);
        }
      } catch (_) {}
    }
    proToast(r.lowData ? 'Low-data mode on — reload pages to save data' : 'Low-data mode off');
  }

  static Future<void> toggleAnnoyances(ProTab? t) async {
    final r = PageRules.instance;
    await r.ensureLoaded();
    r.annoyances = !r.annoyances;
    await r.save();
    if (r.annoyances && t != null && t.web != null && t.isWeb && !t.safe) {
      await r.applyPage(t.web!, t.url);
    }
    proToast(r.annoyances ? 'Annoyance mode on — banners and pop-ups are hidden' : 'Annoyance mode off');
  }
}

/// The Page tools sheet for [t] (the tab the menu was opened from).
Future<void> showPageTools(BuildContext context, ProTab t) async {
  await PageRules.instance.ensureLoaded();
  if (!context.mounted) return;
  final p = NovaPalette.instance;
  final web = t.isWeb && t.web != null;
  final r = PageRules.instance;
  final v = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: p.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => NovaThemed(
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(8, 10, 8, 12), children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: p.border, borderRadius: BorderRadius.circular(2)))),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(children: [
                Icon(Icons.construction_rounded, color: p.accent),
                const SizedBox(width: 10),
                Expanded(child: Text('Page tools', style: p.title(size: 17))),
                const ReadMoreLink('scam_explainer', label: 'Guide', compact: true),
              ]),
            ),
            _head(p, 'This page'),
            _item(ctx, p, 'scam', Icons.gpp_maybe_rounded, 'Scam Explainer', 'Is this page trying to trick me?', enabled: web),
            _item(ctx, p, 'lens', Icons.policy_rounded, 'Security Lens', 'Passive security review of this site', enabled: web),
            _item(ctx, p, 'xray', Icons.manage_search_rounded, 'Site Data X-ray', 'Cookies, storage and trackers', enabled: web),
            _item(ctx, p, 'agent', Icons.smart_toy_rounded, 'Safe NOVA Agent', 'NOVA does it — you approve each step',
                enabled: web && !t.incognito && !t.safe),
            _head(p, 'Browse lighter'),
            _item(ctx, p, 'lowdata', Icons.data_saver_on_rounded, 'Low-data mode', 'No images, video files or web fonts', check: r.lowData),
            _item(ctx, p, 'annoy', Icons.block_rounded, 'Annoyance mode', 'Hide cookie banners and pop-ups', check: r.annoyances),
            _head(p, 'Pro tools'),
            _item(ctx, p, 'safely', Icons.health_and_safety_rounded, 'Open a link safely…', 'Check where it goes, open in Safe View'),
            _item(ctx, p, 'rules', Icons.tune_rounded, 'Rewrite Rules', 'Redirect, block, restyle sites'),
          ]),
        ),
      ),
    ),
  );
  if (v == null || !context.mounted) return;
  switch (v) {
    case 'scam':
      await ProTools.scam(context, t);
    case 'lens':
      await ProTools.lens(context, t);
    case 'xray':
      await ProTools.xray(context, t);
    case 'agent':
      ProTools.agent(context, t);
    case 'lowdata':
      await ProTools.toggleLowData(t);
    case 'annoy':
      await ProTools.toggleAnnoyances(t);
    case 'safely':
      await showOpenSafely(context);
    case 'rules':
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const RulesScreen()));
  }
}

Widget _head(NovaPalette p, String s) => Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      child: Text(s.toUpperCase(), style: p.ui(size: 10.5, weight: FontWeight.w800, color: p.textFaint, letterSpacing: 0.8)),
    );

Widget _item(BuildContext ctx, NovaPalette p, String v, IconData icon, String label, String sub, {bool enabled = true, bool? check}) =>
    ListTile(
      enabled: enabled,
      onTap: () => Navigator.pop(ctx, v),
      leading: Icon(icon, size: 21, color: enabled ? p.accent : p.textFaint),
      title: Text(label, style: p.ui(size: 14, weight: FontWeight.w600, color: enabled ? p.text : p.textFaint)),
      subtitle: Text(sub, style: p.ui(size: 11.5, color: p.textMuted)),
      trailing: check == null
          ? null
          : Icon(check ? Icons.toggle_on_rounded : Icons.toggle_off_outlined, color: check ? p.accent : p.textFaint, size: 30),
    );
