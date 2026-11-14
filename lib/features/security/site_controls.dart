// lib/features/security/site_controls.dart
//
// Site Control Center (3.13.0, ported from NOVA X for PC) — every per-site
// setting in one place, opened from the padlock in the address bar.
// Settings are saved per site ("example.com" also covers its subdomains) and
// applied to NOVA X's own WebView when a page of that site loads:
//
//   NOVA Shield on/off ........ paused sites (shield_engine.dart)
//   JavaScript ................ InAppWebViewSettings.javaScriptEnabled
//   Images .................... InAppWebViewSettings.blockNetworkImage
//   Pop-ups ................... NOVA X never lets pages open windows by
//                               themselves; "off" also stops window.open
//                               after a tap (noPopupsJs)
//   Camera / microphone ....... onPermissionRequest
//   Location .................. onGeolocationPermissionsShowPrompt
//   Autoplay .................. mediaPlaybackRequiresUserGesture + a small
//                               script that pauses media the user didn't start
//   Fingerprint protection .... off / standard / strict (fingerprint_guard.dart)
//   Sign out when NOVA X closes (Session Shield)
//   Identify as ............... phone (default) / desktop site
//
// Android System WebView doesn't support web notifications, so there is no
// notifications setting here (pages can't show them in NOVA X anyway).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cyber/ui/cyber_palette.dart';
import '../guide/guide_screen.dart';
import '../pro/pro_ui.dart';
import '../shield/engine/shield_engine.dart';
import '../shield/engine/shield_lists.dart';
import 'session_shield.dart';

enum SiteChoice { ask, allow, block }

extension SiteChoiceX on SiteChoice {
  String get label => switch (this) { SiteChoice.ask => 'Ask', SiteChoice.allow => 'Allow', SiteChoice.block => 'Block' };
  static SiteChoice parse(Object? v) => SiteChoice.values.where((c) => c.name == v).firstOrNull ?? SiteChoice.ask;
}

enum FingerprintLevel { off, standard, strict }

extension FingerprintLevelX on FingerprintLevel {
  String get label => switch (this) {
        FingerprintLevel.off => 'Off',
        FingerprintLevel.standard => 'Standard',
        FingerprintLevel.strict => 'Strict',
      };
  static FingerprintLevel? parse(Object? v) => FingerprintLevel.values.where((c) => c.name == v).firstOrNull;
}

class SiteSettings {
  SiteSettings(this.site);

  final String site;
  bool scripts = true;
  bool images = true;
  bool blockPopups = false;
  bool autoplay = true;
  SiteChoice camera = SiteChoice.ask;
  SiteChoice microphone = SiteChoice.ask;
  SiteChoice location = SiteChoice.ask;
  FingerprintLevel? fingerprint; // null = global default
  String userAgent = ''; // '' (phone) | 'desktop'

  bool get isDefault =>
      scripts && images && !blockPopups && autoplay &&
      camera == SiteChoice.ask && microphone == SiteChoice.ask && location == SiteChoice.ask &&
      fingerprint == null && userAgent.isEmpty;

  Map<String, Object?> toJson() => {
        'scripts': scripts,
        'images': images,
        'blockPopups': blockPopups,
        'autoplay': autoplay,
        'camera': camera.name,
        'microphone': microphone.name,
        'location': location.name,
        'fingerprint': fingerprint?.name,
        'ua': userAgent,
      };

  static SiteSettings fromJson(String site, Map j) => SiteSettings(site)
    ..scripts = j['scripts'] != false
    ..images = j['images'] != false
    ..blockPopups = j['blockPopups'] == true
    ..autoplay = j['autoplay'] != false
    ..camera = SiteChoiceX.parse(j['camera'])
    ..microphone = SiteChoiceX.parse(j['microphone'])
    ..location = SiteChoiceX.parse(j['location'])
    ..fingerprint = FingerprintLevelX.parse(j['fingerprint'])
    ..userAgent = j['ua'] == 'desktop' ? 'desktop' : '';
}

class SiteControls extends ChangeNotifier {
  SiteControls._();
  static final SiteControls instance = SiteControls._();

  static const String _key = 'nova_site_controls_v1';
  static const String _kFpDefault = 'nova_fp_default_level';
  static const String desktopUa =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

  final Map<String, SiteSettings> _sites = {};
  FingerprintLevel fingerprintDefault = FingerprintLevel.standard;
  SharedPreferences? _prefs;
  bool _loaded = false;
  Future<void>? _loading;

  bool get loaded => _loaded;

  Future<void> ensureLoaded() => _loaded ? Future.value() : (_loading ??= _load());

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    decode(_prefs!.getString(_key));
    fingerprintDefault = FingerprintLevelX.parse(_prefs!.getString(_kFpDefault)) ?? FingerprintLevel.standard;
    _loaded = true;
    notifyListeners();
  }

  void decode(String? raw) {
    _sites.clear();
    if (raw == null) return;
    try {
      final j = jsonDecode(raw);
      if (j is Map) {
        j.forEach((k, v) {
          if (k is String && v is Map) _sites[k] = SiteSettings.fromJson(k, v);
        });
      }
    } catch (_) {}
  }

  String encode() => jsonEncode({for (final e in _sites.entries) if (!e.value.isDefault) e.key: e.value.toJson()});

  Future<void> save(SiteSettings s) async {
    if (s.isDefault) {
      _sites.remove(s.site);
    } else {
      _sites[s.site] = s;
    }
    await _prefs?.setString(_key, encode());
    notifyListeners();
  }

  Future<void> setFingerprintDefault(FingerprintLevel l) async {
    await ensureLoaded();
    fingerprintDefault = l;
    await _prefs?.setString(_kFpDefault, l.name);
    notifyListeners();
  }

  /// "www.Shop.Example.com" → "shop.example.com" (the key settings are saved under).
  static String keyOf(String host) => NovaShieldEngine.siteKey(host);

  /// The most specific saved settings covering [host], else defaults.
  SiteSettings forHost(String host) {
    final h = keyOf(host);
    SiteSettings? best;
    _sites.forEach((site, s) {
      if (h == site || h.endsWith('.$site')) {
        if (best == null || site.length > best!.site.length) best = s;
      }
    });
    return best ?? SiteSettings(h);
  }

  bool hasCustom(String host) => !forHost(host).isDefault;

  Iterable<SiteSettings> get all => _sites.values;

  /// Fingerprint level per site that differs from the default (for the script).
  Map<String, String> fingerprintOverrides() => {
        for (final s in _sites.values)
          if (s.fingerprint != null && s.fingerprint != fingerprintDefault) s.site: s.fingerprint!.name,
      };

  // ── Applying (Android WebView) ────────────────────────────────────────────

  /// Applies [host]'s settings to [c] (call before the page loads; the
  /// Site Control Center reloads the page after a change). The WebView's
  /// current settings are read first and only these values change, so the
  /// browser's own settings (text size, storage…) are kept.
  /// [desktopMode] is the browser's own "Desktop site" switch.
  Future<void> apply(InAppWebViewController c, String host, {required bool desktopMode, bool safeView = false}) async {
    await ensureLoaded();
    final s = forHost(host);
    try {
      final cur = await c.getSettings();
      if (cur == null) return;
      final js = !safeView && s.scripts;
      final desktop = desktopMode || s.userAgent == 'desktop';
      final ua = desktop ? desktopUa : '';
      if (cur.javaScriptEnabled == js &&
          cur.blockNetworkImage == !s.images &&
          cur.mediaPlaybackRequiresUserGesture == !s.autoplay &&
          (desktopMode || (cur.userAgent ?? '') == ua)) {
        return; // nothing to change
      }
      cur
        ..javaScriptEnabled = js
        ..blockNetworkImage = !s.images
        ..mediaPlaybackRequiresUserGesture = !s.autoplay;
      // The browser's "Desktop site" switch sets its own user agent.
      if (!desktopMode) cur.userAgent = ua;
      await c.setSettings(settings: cur);
    } catch (_) {}
  }

  /// Pop-ups off: the site can't open new windows, even after a tap.
  static const String noPopupsJs = r'''
(function(){
  if (window.__novaNoPopups) return; window.__novaNoPopups = 1;
  try { window.open = function(){ return null; }; } catch(_){}
  document.addEventListener('click', function(e){
    var a = e.target && e.target.closest ? e.target.closest('a[target="_blank"]') : null;
    if (a) { try { a.removeAttribute('target'); } catch(_){} }
  }, true);
})();''';

  /// Script that stops videos starting by themselves (autoplay off).
  static const String noAutoplayJs = r'''
(function(){
  if (window.__novaNoAutoplay) return; window.__novaNoAutoplay = 1;
  var userAt = 0;
  ['pointerdown','keydown','touchstart'].forEach(function(e){ addEventListener(e, function(ev){ if (ev.isTrusted) userAt = Date.now(); }, true); });
  function guard(v){
    if (v.__novaGuard) return; v.__novaGuard = 1;
    v.autoplay = false;
    v.addEventListener('play', function(){ if (Date.now() - userAt > 1500) { try { v.pause(); } catch(_){} } }, true);
    if (!v.paused && Date.now() - userAt > 1500) { try { v.pause(); } catch(_){} }
  }
  document.querySelectorAll('video,audio').forEach(guard);
  new MutationObserver(function(){ document.querySelectorAll('video,audio').forEach(guard); })
    .observe(document.documentElement, {childList:true, subtree:true});
})();''';
}

/// The Site Control Center sheet for the site shown in a tab.
/// [tabKey] identifies the tab's Shield counts; [reload] reloads the page.
Future<void> showSiteControlCenter(
  BuildContext context, {
  required String host,
  required int tabKey,
  required Future<void> Function() reload,
}) async {
  await SiteControls.instance.ensureLoaded();
  await NovaShieldEngine.instance.ensureReady();
  await SessionShield.instance.ensureLoaded();
  if (!context.mounted || host.isEmpty) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: NovaPalette.instance.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => NovaThemed(child: _SiteControlSheet(host: host, tabKey: tabKey, reload: reload)),
  );
}

class _SiteControlSheet extends StatefulWidget {
  const _SiteControlSheet({required this.host, required this.tabKey, required this.reload});
  final String host;
  final int tabKey;
  final Future<void> Function() reload;

  @override
  State<_SiteControlSheet> createState() => _SiteControlSheetState();
}

class _SiteControlSheetState extends State<_SiteControlSheet> {
  late SiteSettings _s;
  late String _host;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _host = SiteControls.keyOf(widget.host);
    final current = SiteControls.instance.forHost(_host);
    // Edit a copy saved under this exact site.
    _s = SiteSettings.fromJson(_host, current.toJson());
  }

  void _set(VoidCallback f) {
    setState(f);
    _dirty = true;
  }

  Future<void> _apply() async {
    await SiteControls.instance.save(_s);
    if (mounted) Navigator.pop(context);
    if (_dirty) await widget.reload();
  }

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    final shield = NovaShieldEngine.instance;
    final counts = shield.countsFor(widget.tabKey);
    final paused = shield.isPaused(_host);
    final session = SessionShield.instance;
    final signOut = session.isProtected(_host);
    Widget choice(String label, IconData icon, SiteChoice v, ValueChanged<SiteChoice> set) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(icon, size: 18, color: p.textMuted),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: p.ui(size: 13, color: p.text))),
            SegmentedButton<SiteChoice>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [for (final c in SiteChoice.values) ButtonSegment(value: c, label: Text(c.label, style: const TextStyle(fontSize: 12)))],
              selected: {v},
              onSelectionChanged: (x) => _set(() => set(x.first)),
            ),
          ]),
        );
    Widget toggle(String label, String sub, IconData icon, bool v, ValueChanged<bool> set) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          secondary: Icon(icon, size: 18, color: p.textMuted),
          title: Text(label, style: p.ui(size: 13, color: p.text)),
          subtitle: Text(sub, style: p.ui(size: 11.5, color: p.textMuted)),
          value: v,
          onChanged: (x) => _set(() => set(x)),
        );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
          child: Column(children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: p.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.tune_rounded, color: p.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Site controls', style: p.title(size: 17)),
                  Text(_host, maxLines: 1, overflow: TextOverflow.ellipsis, style: p.ui(size: 12, color: p.textMuted)),
                ]),
              ),
              const ReadMoreLink('site_controls', compact: true),
            ]),
          ]),
        ),
        Divider(height: 1, color: p.border),
        Expanded(
          child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), children: [
            ProCard(
              title: 'NOVA Shield',
              icon: Icons.shield_rounded,
              trailing: Switch(
                value: !paused && shield.enabled,
                onChanged: shield.enabled
                    ? (v) async {
                        await shield.setPaused(_host, !v);
                        if (mounted) setState(() => _dirty = true);
                      }
                    : null,
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  !shield.enabled
                      ? 'The ad & tracker blocker is off (Settings › Ad blocker).'
                      : paused
                          ? 'Paused on this site: nothing is blocked here.'
                          : '${counts.total} request(s) blocked on this page from ${counts.uniqueHosts} domain(s).',
                  style: p.ui(size: 12.5, color: p.textMuted),
                ),
                if (counts.byCategory.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final e in counts.byCategory.entries) ProChip('${e.value} ${ShieldCategory.label(e.key)}'),
                  ]),
                ],
              ]),
            ),
            ProCard(
              title: 'Content',
              icon: Icons.web_rounded,
              child: Column(children: [
                toggle('JavaScript', 'Off: the site runs without scripts (some sites stop working).', Icons.code_rounded, _s.scripts,
                    (v) => _s.scripts = v),
                toggle('Images', 'Off: images are not downloaded on this site.', Icons.image_outlined, _s.images, (v) => _s.images = v),
                toggle('Autoplay', 'Off: videos and sound play only when you start them.', Icons.play_circle_outline_rounded, _s.autoplay,
                    (v) => _s.autoplay = v),
                toggle('Pop-ups and new windows', 'Off: windows the site tries to open are blocked.', Icons.open_in_new_rounded,
                    !_s.blockPopups, (v) => _s.blockPopups = !v),
              ]),
            ),
            ProCard(
              title: 'Permissions',
              icon: Icons.admin_panel_settings_outlined,
              child: Column(children: [
                choice('Camera', Icons.videocam_outlined, _s.camera, (v) => _s.camera = v),
                choice('Microphone', Icons.mic_none_rounded, _s.microphone, (v) => _s.microphone = v),
                choice('Location', Icons.place_outlined, _s.location, (v) => _s.location = v),
              ]),
            ),
            ProCard(
              title: 'Privacy',
              icon: Icons.fingerprint_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('Fingerprint protection', style: p.ui(size: 13, color: p.text))),
                  DropdownButton<FingerprintLevel?>(
                    value: _s.fingerprint,
                    dropdownColor: p.surface,
                    items: [
                      DropdownMenuItem(value: null, child: Text('Default (${SiteControls.instance.fingerprintDefault.label})')),
                      for (final l in FingerprintLevel.values) DropdownMenuItem(value: l, child: Text(l.label)),
                    ],
                    onChanged: (v) => _set(() => _s.fingerprint = v),
                  ),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('Sign out when NOVA X closes', style: p.ui(size: 13, color: p.text)),
                  subtitle: Text('Session Shield deletes this site’s cookies and storage, so a stolen session stops working.',
                      style: p.ui(size: 11.5, color: p.textMuted)),
                  value: signOut,
                  onChanged: (v) async {
                    await session.setProtected(_host, v);
                    if (mounted) setState(() {});
                  },
                ),
                Row(children: [
                  Expanded(child: Text('Identify as', style: p.ui(size: 13, color: p.text))),
                  DropdownButton<String>(
                    value: _s.userAgent,
                    dropdownColor: p.surface,
                    items: const [
                      DropdownMenuItem(value: '', child: Text('Phone (default)')),
                      DropdownMenuItem(value: 'desktop', child: Text('Desktop computer')),
                    ],
                    onChanged: (v) => _set(() => _s.userAgent = v ?? ''),
                  ),
                ]),
              ]),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final n = await SessionShield.instance.signOutSite(_host);
                  proToast('Signed out of $_host${n > 0 ? ' ($n cookies deleted)' : ''}');
                  if (mounted) Navigator.pop(context);
                  await widget.reload();
                },
                icon: Icon(Icons.logout_rounded, color: p.danger, size: 18),
                label: Text('Sign out of $_host now', style: TextStyle(color: p.danger)),
              ),
            ),
          ]),
        ),
        Divider(height: 1, color: p.border),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(children: [
              TextButton(onPressed: () => _set(() => _s = SiteSettings(_host)), child: const Text('Reset this site')),
              const Spacer(),
              FilledButton(onPressed: _apply, child: Text(_dirty ? 'Save and reload' : 'Done')),
            ]),
          ),
        ),
      ]),
    );
  }
}
