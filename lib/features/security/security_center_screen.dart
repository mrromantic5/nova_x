// lib/features/security/security_center_screen.dart
//
// NOVA X Security Center (3.13.0, ported from NOVA X for PC) — every
// protection in one screen, with real numbers only: NOVA Shield blocking
// (lists, blocked today / all time, paused sites), Password Guard, Session
// Shield, fingerprint protection, download safety, the malware-filtering
// DNS check, and a self-test that proves each protection works on this phone.

import 'package:flutter/material.dart';

import '../../core/services/nova_shield_service.dart';
import '../cyber/ui/cyber_palette.dart';
import '../guide/guide_screen.dart';
import '../pro/pro_tab.dart';
import '../pro/pro_ui.dart';
import '../shield/engine/shield_cosmetic.dart';
import '../shield/engine/shield_engine.dart';
import '../shield/engine/shield_lists.dart';
import 'download_safety.dart';
import 'password_guard.dart';
import 'security_selftest.dart';
import 'session_shield.dart';
import 'site_controls.dart';

class SecurityCenterScreen extends StatefulWidget {
  const SecurityCenterScreen({super.key});

  @override
  State<SecurityCenterScreen> createState() => _SecurityCenterScreenState();
}

class _SecurityCenterScreenState extends State<SecurityCenterScreen> {
  bool _loading = true;
  bool _updating = false;
  bool _downloadSafety = true;
  DateTime? _listDate;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Future.wait([
      NovaShieldEngine.instance.ensureReady(),
      PasswordGuard.instance.ensureLoaded(),
      SessionShield.instance.ensureLoaded(),
      SiteControls.instance.ensureLoaded(),
      ShieldLists.instance.load(),
      ShieldCosmetic.instance.load(),
    ]);
    _listDate = await ShieldLists.instance.lastDownload();
    _downloadSafety = await DownloadSafety.enabled();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _updateLists() async {
    setState(() => _updating = true);
    final ok = await NovaShieldEngine.instance.updateListsNow();
    _listDate = await ShieldLists.instance.lastDownload();
    if (!mounted) return;
    setState(() => _updating = false);
    proToast(ok ? 'Block lists updated' : (ShieldLists.instance.lastUpdateError ?? 'Lists are already up to date'), ok: ok);
  }

  static List<String> _hosts(String text) => text
      .split(RegExp(r'[,\s]+'))
      .map((s) => s.trim().toLowerCase().replaceFirst(RegExp(r'^https?://'), '').split('/').first.replaceFirst(RegExp(r'^www\.'), ''))
      .where((s) => s.contains('.'))
      .toSet()
      .toList();

  Future<void> _addPassword() async {
    final label = TextEditingController();
    final sites = TextEditingController();
    final pw = TextEditingController();
    final pw2 = TextEditingController();
    final ok = await showProDialog<bool>(context, (ctx) {
      final p = NovaThemeScope.of(ctx);
      return AlertDialog(
        backgroundColor: p.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Text('Protect a password', style: p.title(size: 17)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ProField(controller: label, label: 'Name (e.g. Google account)'),
            const SizedBox(height: 10),
            ProField(controller: sites, label: 'Sites it belongs to', hint: 'google.com, youtube.com'),
            const SizedBox(height: 10),
            ProField(controller: pw, label: 'Password', obscure: true),
            const SizedBox(height: 10),
            ProField(controller: pw2, label: 'Password again', obscure: true),
            const SizedBox(height: 10),
            Text('NOVA X keeps only a slow, salted hash — never the password.', style: p.ui(size: 12, color: p.textMuted)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Protect')),
        ],
      );
    });
    final hosts = _hosts(sites.text);
    final password = pw.text;
    final again = pw2.text;
    final name = label.text.trim();
    for (final c in [label, sites, pw, pw2]) {
      c.dispose();
    }
    if (ok != true) return;
    if (password.length < 4 || password != again || hosts.isEmpty) {
      proToast(password != again ? 'The passwords don’t match' : 'Enter the password and at least one site', ok: false);
      return;
    }
    await PasswordGuard.instance.addManual(name.isEmpty ? hosts.first : name, hosts, password);
    proToast('Password protected for ${hosts.join(', ')}');
  }

  Future<void> _addSessionSite() async {
    final c = TextEditingController();
    final site = await showProDialog<String>(context, (ctx) {
      final p = NovaThemeScope.of(ctx);
      return AlertDialog(
        backgroundColor: p.surface,
        title: Text('Protect a site’s session', style: p.title(size: 17)),
        content: ProField(controller: c, hint: 'mybank.com', onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Add')),
        ],
      );
    });
    c.dispose();
    final h = _hosts(site ?? '').firstOrNull;
    if (h != null) await SessionShield.instance.setProtected(h, true);
  }

  @override
  Widget build(BuildContext context) {
    return ProPage(
      icon: Icons.health_and_safety_rounded,
      title: 'Security Center',
      guide: 'security_center',
      subtitle: 'Every NOVA X protection, with real numbers from this phone.',
      actions: [
        IconButton(
          tooltip: 'Run self-test',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SecuritySelfTestScreen())),
          icon: const Icon(Icons.fact_check_rounded),
        ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: Listenable.merge([
                NovaShieldEngine.instance,
                PasswordGuard.instance,
                SessionShield.instance,
                SiteControls.instance,
              ]),
              builder: (context, _) => _body(NovaThemeScope.of(context)),
            ),
    );
  }

  Widget _stat(NovaPalette p, String value, String label, IconData icon) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
        child: Row(children: [
          Icon(icon, color: p.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: p.title(size: 18)),
              Text(label, style: p.ui(size: 11, color: p.textMuted), maxLines: 2),
            ]),
          ),
        ]),
      );

  Widget _body(NovaPalette p) {
    final shield = NovaShieldEngine.instance;
    final lists = ShieldLists.instance.current;
    final guard = PasswordGuard.instance;
    final session = SessionShield.instance;
    final sc = SiteControls.instance;
    final active = ProTabs.instance.active;
    final tabCounts = active != null && active.isWeb ? shield.countsFor(active.id) : null;
    return ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 40), children: [
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.2,
        children: [
          _stat(p, '${shield.blockedToday()}', 'requests blocked today', Icons.today_rounded),
          _stat(p, '${shield.lifetimeTotal}', 'blocked since counting began', Icons.shield_rounded),
          _stat(p, tabCounts == null ? '—' : '${tabCounts.total}', 'blocked on the open page', Icons.tab_rounded),
          _stat(p, '${guard.protectedCount}', 'passwords protected', Icons.password_rounded),
        ],
      ),
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SecuritySelfTestScreen())),
          icon: const Icon(Icons.fact_check_rounded, size: 18),
          label: const Text('Run self-test'),
        ),
      ),
      const SizedBox(height: 14),
      ProCard(
        title: 'NOVA Shield — ad, tracker and miner blocking',
        guide: 'shield',
        icon: Icons.shield_rounded,
        trailing: Switch(value: shield.enabled, onChanged: shield.setEnabled),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ProKv('Blocking', shield.ruleCount > 0 ? 'Inside NOVA X’s browser · ${shield.ruleCount} domain rules loaded' : 'Loading lists…',
              valueColor: shield.ruleCount > 0 ? p.success : p.textMuted),
          ProKv('Block lists', lists == null
              ? '—'
              : '${lists.countOf(ShieldCategory.ads)} ad · ${lists.countOf(ShieldCategory.trackers)} tracker · '
                  '${lists.countOf(ShieldCategory.miners)} miner domains'),
          ProKv('Page clean-up', () {
            final r = ShieldCosmetic.instance.rules;
            return r == null ? 'Loading…' : 'Empty ad boxes removed · ${r.genericCount} ad-container rules + ${r.siteCount} site rules';
          }()),
          const Align(alignment: Alignment.centerLeft, child: ReadMoreLink('page_cleanup', label: 'How page clean-up works', compact: true)),
          ProKv('Lists from', _listDate == null
              ? 'Snapshot built into NOVA X (updates weekly when online)'
              : '${lists?.source ?? 'download'} · ${_listDate!.toLocal().toString().substring(0, 16)}'),
          ProKv('Blocked so far', shield.lifetimeByCategory.isEmpty
              ? 'Nothing yet'
              : shield.lifetimeByCategory.entries.map((e) => '${e.value} ${ShieldCategory.label(e.key).toLowerCase()}').join(' · ')),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: _updating ? null : _updateLists,
              icon: _updating
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync_rounded, size: 18),
              label: const Text('Update lists now'),
            ),
            TextButton(onPressed: shield.resetLifetime, child: const Text('Reset counters')),
          ]),
          if (shield.paused.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Paused on these sites', style: p.ui(size: 12.5, weight: FontWeight.w700, color: p.text)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in shield.paused) InputChip(label: Text(s), onDeleted: () => shield.setPaused(s, false)),
            ]),
          ],
          const SizedBox(height: 8),
          Text('Lists: EasyList and EasyPrivacy by The EasyList authors (https://easylist.to/), GPLv3 / CC BY-SA 3.0. '
              'Only requests to other companies are blocked; the site you visit is never blocked. Works inside NOVA X only.',
              style: p.ui(size: 11.5, color: p.textFaint)),
        ]),
      ),
      ProCard(
        title: 'Password Guard — stops phishing pages getting your passwords',
        guide: 'password_guard',
        icon: Icons.password_rounded,
        trailing: Switch(value: guard.enabled, onChanged: guard.setEnabled),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${guard.managerCount} saved password(s) protected automatically, ${guard.manualCount} added by you. '
              'A protected password can only be sent to the sites it belongs to.',
              style: p.ui(size: 12.5, color: p.textMuted)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(onPressed: _addPassword, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Protect a password')),
            TextButton(onPressed: guard.syncWithPasswordManager, child: const Text('Re-check saved passwords')),
          ]),
          if (guard.entries.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final e in guard.entries.where((e) => e.source != 'selftest').take(40))
              ProFindingRow(
                level: e.source == 'manual' ? ProLevel.info : ProLevel.good,
                title: e.label,
                detail: '${e.source == 'manual' ? 'Added by you' : 'From the password manager'} · ${e.hosts.join(', ')}',
                trailing: e.source == 'manual'
                    ? IconButton(icon: Icon(Icons.close_rounded, size: 16, color: p.textFaint), onPressed: () => guard.remove(e))
                    : null,
              ),
          ],
          if (guard.alerts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Stopped this session', style: p.ui(size: 12.5, weight: FontWeight.w700, color: p.danger)),
            for (final a in guard.alerts)
              ProFindingRow(level: ProLevel.critical, title: a.host, detail: 'Password for ${a.belongsTo.join(', ')} · ${a.at.toLocal().toString().substring(11, 16)}'),
          ],
        ]),
      ),
      ProCard(
        title: 'Session Shield — sign out of important sites',
        guide: 'session_shield',
        icon: Icons.logout_rounded,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Stolen login cookies let criminals into accounts without your password. For these sites NOVA X deletes cookies and '
              'site data when it closes and every time it starts, so a stolen session stops working.',
              style: p.ui(size: 12.5, color: p.textMuted)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in session.sites) InputChip(label: Text(s), onDeleted: () => session.setProtected(s, false)),
            ActionChip(avatar: const Icon(Icons.add_rounded, size: 16), label: const Text('Add site'), onPressed: _addSessionSite),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text('Also sign out after', style: p.ui(size: 12.5, color: p.text))),
            DropdownButton<int>(
              value: const [0, 5, 15, 30, 60, 240].contains(session.idleMinutes) ? session.idleMinutes : 0,
              dropdownColor: p.surface,
              items: const [
                DropdownMenuItem(value: 0, child: Text('never (close / start only)')),
                DropdownMenuItem(value: 5, child: Text('5 min away from NOVA X')),
                DropdownMenuItem(value: 15, child: Text('15 min away from NOVA X')),
                DropdownMenuItem(value: 30, child: Text('30 min away from NOVA X')),
                DropdownMenuItem(value: 60, child: Text('1 hour away from NOVA X')),
                DropdownMenuItem(value: 240, child: Text('4 hours away from NOVA X')),
              ],
              onChanged: (v) => session.setIdleMinutes(v ?? 0),
            ),
          ]),
          const SizedBox(height: 6),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: p.danger, foregroundColor: Colors.white),
            onPressed: session.sites.isEmpty
                ? null
                : () async {
                    final n = await session.signOutEverywhereNow();
                    proToast('Signed out everywhere ($n cookies deleted)');
                  },
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Sign out everywhere now'),
          ),
          for (final l in session.log.take(5)) Text(l, style: p.ui(size: 11.5, color: p.textFaint)),
        ]),
      ),
      ProCard(
        title: 'Fingerprint protection',
        guide: 'fingerprint',
        icon: Icons.fingerprint_rounded,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Each site sees slightly different canvas and audio values (strict: also generic graphics and hardware values), '
              'the same for the whole session and new after NOVA X restarts — so sites can’t link your visits by fingerprint.',
              style: p.ui(size: 12.5, color: p.textMuted)),
          const SizedBox(height: 8),
          SegmentedButton<FingerprintLevel>(
            segments: [for (final l in FingerprintLevel.values) ButtonSegment(value: l, label: Text(l.label))],
            selected: {sc.fingerprintDefault},
            onSelectionChanged: (s) {
              sc.setFingerprintDefault(s.first);
              proToast('Applies to tabs you open from now on');
            },
          ),
          if (sc.fingerprintOverrides().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Site exceptions: ${sc.fingerprintOverrides().entries.map((e) => '${e.key} (${e.value})').join(', ')}',
                  style: p.ui(size: 12, color: p.textMuted)),
            ),
        ]),
      ),
      ProCard(
        title: 'Dangerous sites and downloads',
        guide: 'shield_dns',
        icon: Icons.travel_explore_rounded,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ProKv('Google Safe Browsing', 'On in NOVA X’s browser (Android System WebView)'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text('Extra check with a malware-filtering DNS', style: p.ui(size: 13, color: p.text)),
            subtitle: Text(
                'Looks up each site you open with ${NovaShieldService.providers[NovaShieldService.activeProvider]?.name ?? 'the chosen provider'} '
                '(encrypted) and blocks known malware sites.',
                style: p.ui(size: 11.5, color: p.textMuted)),
            value: NovaShieldService.isEnabled,
            onChanged: (v) async {
              await NovaShieldService.setEnabled(v);
              setState(() {});
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text('Warn before keeping app files (APK)', style: p.ui(size: 13, color: p.text)),
            subtitle: Text('Shows where an app file comes from and any warning signs. NOVA X never installs apps.',
                style: p.ui(size: 11.5, color: p.textMuted)),
            value: _downloadSafety,
            onChanged: (v) async {
              await DownloadSafety.setEnabled(v);
              setState(() => _downloadSafety = v);
            },
          ),
        ]),
      ),
    ]);
  }
}
