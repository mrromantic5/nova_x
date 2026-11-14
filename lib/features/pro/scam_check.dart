// lib/features/pro/scam_check.dart
//
// Scam Explainer — "Is this page trying to trick me?" in plain words.
//
// Checks done on this phone: the address (look-alike brand names, odd
// characters, raw IP, risky endings, no HTTPS), what the page asks for
// (passwords, card numbers, one-time codes, crypto, gift cards), pressure
// tactics (countdowns, "act now", prizes) and where its forms send data.
// NOVA Shield's threat check is added when Shield is on. NOVA AI can then
// explain the result in simple language (sends the address, the signals and
// a short part of the page text; never in incognito tabs).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/services/nova_shield_service.dart';
import '../cyber/ui/cyber_palette.dart';
import '../nova/services/nova_api.dart';
import 'pro_tab.dart';
import 'pro_ui.dart';

class ScamReason {
  const ScamReason(this.level, this.title, this.detail, this.points);
  final ProLevel level;
  final String title;
  final String detail;
  final int points;
}

class ScamVerdict {
  ScamVerdict(this.reasons, {this.shieldThreat});
  final List<ScamReason> reasons;
  final String? shieldThreat;

  int get score {
    var s = reasons.fold<int>(0, (a, r) => a + r.points);
    if (shieldThreat != null) s += 70;
    return s.clamp(0, 100);
  }

  String get label => score >= 55 ? 'Likely scam' : (score >= 25 ? 'Be careful' : 'Looks normal');
  ProLevel get level => score >= 55 ? ProLevel.critical : (score >= 25 ? ProLevel.medium : ProLevel.good);
}

/// What the page shows and asks for (read by [ScamAnalyzer.collectJs]).
class ScamPageSignals {
  ScamPageSignals.fromJson(Map<String, dynamic> j)
      : title = '${j['title'] ?? ''}',
        text = '${j['text'] ?? ''}',
        hasPassword = j['hasPassword'] == true,
        hasCard = j['hasCard'] == true,
        hasOtp = j['hasOtp'] == true,
        hasSeed = j['hasSeed'] == true,
        formHosts = [for (final h in (j['formHosts'] is List ? j['formHosts'] as List : const [])) '$h'],
        insecureForm = j['insecureForm'] == true,
        countdown = j['countdown'] == true,
        chatLinks = (j['chatLinks'] as num?)?.toInt() ?? 0,
        iframes = (j['iframes'] as num?)?.toInt() ?? 0,
        noRightClick = j['noRightClick'] == true;

  final String title;
  final String text;
  final bool hasPassword;
  final bool hasCard;
  final bool hasOtp;
  final bool hasSeed;
  final List<String> formHosts;
  final bool insecureForm;
  final bool countdown;
  final int chatLinks;
  final int iframes;
  final bool noRightClick;
}

class ScamAnalyzer {
  ScamAnalyzer._();

  /// Well-known brands and the sites that really belong to them.
  static const Map<String, List<String>> brands = {
    'paypal': ['paypal.com', 'paypal.me'],
    'apple': ['apple.com', 'icloud.com'],
    'icloud': ['icloud.com', 'apple.com'],
    'microsoft': ['microsoft.com', 'live.com', 'office.com', 'microsoftonline.com', 'outlook.com', 'xbox.com', 'bing.com', 'msn.com'],
    'outlook': ['outlook.com', 'live.com', 'office.com', 'microsoft.com'],
    'office365': ['office.com', 'microsoft.com', 'microsoftonline.com'],
    'google': ['google.com', 'youtube.com', 'gmail.com', 'goo.gl', 'g.co', 'googleapis.com', 'gstatic.com'],
    'gmail': ['gmail.com', 'google.com'],
    'amazon': ['amazon.com', 'amazon.co.uk', 'amazon.ae', 'amazon.de', 'amazon.in', 'amazon.ca', 'amazon.sa', 'amzn.to', 'aws.amazon.com'],
    'netflix': ['netflix.com'],
    'facebook': ['facebook.com', 'fb.com', 'fb.me', 'meta.com'],
    'instagram': ['instagram.com'],
    'whatsapp': ['whatsapp.com', 'wa.me', 'whatsapp.net'],
    'telegram': ['telegram.org', 't.me', 'telegram.me'],
    'tiktok': ['tiktok.com'],
    'binance': ['binance.com'],
    'coinbase': ['coinbase.com'],
    'metamask': ['metamask.io'],
    'trustwallet': ['trustwallet.com'],
    'dhl': ['dhl.com'],
    'fedex': ['fedex.com'],
    'ups': ['ups.com'],
    'usps': ['usps.com'],
    'aramex': ['aramex.com'],
    'emiratespost': ['emiratespost.ae'],
    'chase': ['chase.com'],
    'wellsfargo': ['wellsfargo.com'],
    'bankofamerica': ['bankofamerica.com'],
    'hsbc': ['hsbc.com', 'hsbc.co.uk', 'hsbc.ae'],
    'emiratesnbd': ['emiratesnbd.com'],
    'mtn': ['mtn.com', 'mtn.com.gh', 'mtn.ng', 'mtn.co.za'],
    'vodafone': ['vodafone.com', 'vodafone.co.uk', 'vodafone.com.gh'],
    'steam': ['steampowered.com', 'steamcommunity.com'],
    'roblox': ['roblox.com'],
    'linkedin': ['linkedin.com'],
    'dropbox': ['dropbox.com'],
    'docusign': ['docusign.com', 'docusign.net'],
    'adobe': ['adobe.com'],
    'spotify': ['spotify.com'],
    'ebay': ['ebay.com', 'ebay.co.uk'],
    'walmart': ['walmart.com'],
  };

  static const Set<String> riskyTlds = {
    'zip', 'mov', 'top', 'xyz', 'click', 'link', 'live', 'buzz', 'rest', 'gq', 'tk', 'ml', 'cf', 'ga', 'icu', 'cam',
    'monster', 'cfd', 'sbs', 'quest', 'bond', 'lol', 'shop', 'online', 'site', 'info', 'support', 'help', 'win', 'loan',
  };

  static int _lev(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  /// The address on its own (also used before a link is opened).
  static List<ScamReason> analyzeUrl(String url) {
    final out = <ScamReason>[];
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return out;
    final host = uri.host.toLowerCase();
    final base = proBaseDomain(host);
    final sld = base.split('.').first;
    final tld = host.split('.').last;

    if (uri.scheme == 'http') {
      out.add(const ScamReason(ProLevel.medium, 'Not a secure connection',
          'The page uses plain HTTP, so anything you type can be read on the way. Real banks and shops always use HTTPS.', 15));
    }
    if (host.contains('xn--')) {
      out.add(const ScamReason(ProLevel.high, 'Unusual characters in the address',
          'The address uses look-alike letters from other alphabets — a common trick to imitate a real site.', 30));
    }
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) {
      out.add(const ScamReason(ProLevel.high, 'The address is just numbers',
          'Real companies use a name, not a raw IP address. Be very careful entering anything here.', 25));
    }
    if (uri.userInfo.isNotEmpty) {
      out.add(const ScamReason(ProLevel.high, 'Hidden real address',
          'The link has text before an "@", which hides the real website it opens.', 30));
    }
    if (riskyTlds.contains(tld)) {
      out.add(ScamReason(ProLevel.low, 'Address ends in ".$tld"',
          'Many scam sites use cheap endings like this one. It doesn’t prove anything on its own.', 8));
    }
    if (host.split('.').length >= 5) {
      out.add(const ScamReason(ProLevel.low, 'Very long address',
          'Lots of parts before the real site name can be used to make an address look official.', 8));
    }
    if ('-'.allMatches(base).length >= 2) {
      out.add(const ScamReason(ProLevel.low, 'Many hyphens in the site name',
          'Names like "secure-login-account-update" are typical of fake pages.', 8));
    }
    if (RegExp(r'(login|verify|secure|update|account|wallet|unlock|support|billing|refund|claim|bonus)').hasMatch(host) &&
        !brands.values.any((d) => d.contains(base))) {
      out.add(const ScamReason(ProLevel.low, 'Pressure words in the address',
          'Words like "verify", "secure" or "claim" in a site name are often used by fake pages.', 8));
    }

    // Brand look-alikes.
    for (final e in brands.entries) {
      final official = e.value;
      final isOfficial = official.any((d) => base == d || host == d || host.endsWith('.$d'));
      if (isOfficial) return out; // the real site: no look-alike warnings
      final name = e.key;
      final labels = host.split(RegExp(r'[.\-]'));
      final contains = labels.contains(name) || (name.length >= 5 && host.replaceAll('-', '').replaceAll('.', '').contains(name));
      final close = name.length >= 5 && sld.length >= 4 && _lev(sld, name) <= (name.length >= 8 ? 2 : 1) && sld != name;
      if (contains || close) {
        out.add(ScamReason(ProLevel.critical, 'Pretends to be ${_cap(name)}?',
            'The address mentions "${_cap(name)}" but this isn’t one of ${_cap(name)}’s sites (${official.take(3).join(', ')}).', 45));
        break;
      }
    }
    return out;
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static final RegExp _urgent = RegExp(
      r'(act now|immediately|within 24 hours|within 48 hours|account (will be )?(suspended|locked|closed|disabled)|'
      r'final (notice|warning)|urgent|last chance|expires today|verify your (account|identity)|unusual (sign-?in|activity)|'
      r'confirm your (details|payment|identity)|limited time)',
      caseSensitive: false);
  static final RegExp _prize = RegExp(
      r"(congratulations|you('ve| have) (won|been selected)|claim your (prize|reward|gift)|free (iphone|gift|money)|"
      r'lucky (winner|draw)|double your (crypto|bitcoin|money)|guaranteed (profit|returns)|giveaway)',
      caseSensitive: false);
  static final RegExp _pay = RegExp(
      r'(gift ?card|itunes card|google play card|steam card|western union|moneygram|send (bitcoin|btc|usdt|crypto)|'
      r'pay (a )?(small )?(fee|delivery fee|customs fee)|processing fee|release (your )?(funds|package))',
      caseSensitive: false);
  static final RegExp _wallet = RegExp(r'\b(bc1[a-z0-9]{25,59}|[13][a-km-zA-HJ-NP-Z1-9]{25,34}|0x[a-fA-F0-9]{40}|T[A-Za-z1-9]{33})\b');
  static final RegExp _support = RegExp(
      r'(your (computer|pc) (is|has been) (infected|blocked|locked)|call (microsoft|apple|windows) support|virus (detected|alert)|'
      r'do not (close|restart) (this|your))',
      caseSensitive: false);

  static List<ScamReason> analyzePage(ScamPageSignals s, String host) {
    final out = <ScamReason>[];
    final text = '${s.title}\n${s.text}';
    final base = proBaseDomain(host);

    if (_support.hasMatch(text)) {
      out.add(const ScamReason(ProLevel.critical, 'Fake virus / tech-support warning',
          'Real companies never show pop-ups telling you to call them because your phone or computer is infected. Close the tab; don’t call any number.', 55));
    }
    if (_prize.hasMatch(text)) {
      out.add(const ScamReason(ProLevel.high, 'Promises prizes or easy money',
          '“You’ve won” and “double your money” offers are the most common way scams start.', 25));
    }
    if (_pay.hasMatch(text)) {
      out.add(const ScamReason(ProLevel.high, 'Asks for unusual payment',
          'Gift cards, crypto transfers or a small “release fee” are payment methods scammers prefer because they can’t be undone.', 30));
    }
    if (_urgent.hasMatch(text)) {
      out.add(const ScamReason(ProLevel.medium, 'Pressure to act fast',
          'Threats like “your account will be closed in 24 hours” push you to act before you think.', 15));
    }
    if (_wallet.hasMatch(s.text)) {
      out.add(const ScamReason(ProLevel.medium, 'Shows a crypto wallet address',
          'Money sent to a wallet can’t be taken back. Only pay people you know and trust.', 12));
    }
    if (s.hasSeed) {
      out.add(const ScamReason(ProLevel.critical, 'Asks for a wallet recovery phrase',
          'No real service ever asks for your 12/24-word recovery phrase. Anyone with it can empty your wallet.', 60));
    }
    if (s.countdown) {
      out.add(const ScamReason(ProLevel.low, 'Countdown timer', 'Timers are used to rush decisions.', 6));
    }
    if (s.chatLinks > 0) {
      out.add(const ScamReason(ProLevel.low, 'Moves you to WhatsApp or Telegram',
          'Scammers often ask to continue “privately” in a chat app, away from the website.', 6));
    }
    final otherForms = s.formHosts.where((h) => h.isNotEmpty && proBaseDomain(h) != base).toSet();
    if ((s.hasPassword || s.hasCard) && otherForms.isNotEmpty) {
      out.add(ScamReason(ProLevel.high, 'Your details go to another site',
          'The form on this page sends what you type to ${otherForms.take(2).join(', ')}, not to $host.', 30));
    }
    if (s.insecureForm && (s.hasPassword || s.hasCard)) {
      out.add(const ScamReason(ProLevel.high, 'Form sends data without encryption',
          'This form posts your password or card over plain HTTP.', 25));
    }
    if (s.hasCard) {
      out.add(const ScamReason(ProLevel.info, 'Asks for card details',
          'Only enter card details on shops you went to yourself, not from a message or an ad.', 4));
    }
    if (s.hasOtp) {
      out.add(const ScamReason(ProLevel.medium, 'Asks for a one-time code',
          'Never give a code sent to your phone to anyone — it’s how accounts get taken over.', 10));
    }
    if (s.hasPassword) {
      out.add(const ScamReason(ProLevel.info, 'Has a login form',
          'Check the address carefully before typing your password.', 2));
    }
    if (s.noRightClick) {
      out.add(const ScamReason(ProLevel.low, 'Blocks right-click', 'Some fake pages stop you from inspecting or copying them.', 4));
    }
    return out;
  }

  /// Reads the page's signals (runs in the page; returns JSON).
  static const String collectJs = r'''
(function(){
  try{
    var q=function(s){return Array.prototype.slice.call(document.querySelectorAll(s));};
    var ins=q('input');
    var attr=function(i){return ((i.name||'')+' '+(i.id||'')+' '+(i.placeholder||'')+' '+(i.getAttribute('autocomplete')||'')+' '+(i.getAttribute('aria-label')||'')).toLowerCase();};
    var hasPassword=ins.some(function(i){return i.type==='password';});
    var hasCard=ins.some(function(i){var a=attr(i);return /cc-number|card.?number|cardnum|cvv|cvc|cc-csc|expiry|cc-exp/.test(a);});
    var hasOtp=ins.some(function(i){var a=attr(i);return /one-time-code|otp|verification code|sms code|2fa|pin code/.test(a);});
    var body=(document.body&&document.body.innerText)||'';
    var hasSeed=/(recovery|seed|secret|mnemonic) (phrase|words)/i.test(body) && ins.filter(function(i){return i.type==='text'||i.type==='password'||i.tagName==='TEXTAREA';}).length>=1 && /(12|24)[ -]word/i.test(body);
    var formHosts=[], insecure=false;
    q('form').forEach(function(f){
      try{ var u=new URL(f.action||location.href, location.href); formHosts.push(u.hostname); if(u.protocol==='http:') insecure=true; }catch(_){}
    });
    var countdown=q('[class*="countdown" i],[id*="countdown" i],[class*="timer" i]').length>0;
    var chat=q('a[href*="wa.me/"],a[href*="api.whatsapp.com"],a[href*="t.me/"],a[href^="tg:"]').length;
    var noRc=false; try{ noRc=(document.oncontextmenu!==null)||(document.body&&document.body.oncontextmenu!==null); }catch(_){}
    return JSON.stringify({title:document.title||'',text:body.replace(/\s+/g,' ').slice(0,4000),hasPassword:hasPassword,hasCard:hasCard,
      hasOtp:hasOtp,hasSeed:hasSeed,formHosts:formHosts.slice(0,10),insecureForm:insecure,countdown:countdown,chatLinks:chat,
      iframes:q('iframe').length,noRightClick:noRc});
  }catch(e){ return JSON.stringify({error:String(e)}); }
})();''';

  static Future<ScamPageSignals?> collect(InAppWebViewController c) async {
    try {
      final r = await c.evaluateJavascript(source: collectJs);
      final d = r is String ? jsonDecode(r) : r;
      if (d is Map && d['error'] == null) return ScamPageSignals.fromJson(Map<String, dynamic>.from(d));
    } catch (_) {}
    return null;
  }

  static Future<ScamVerdict> check(String url, {InAppWebViewController? c}) async {
    final reasons = <ScamReason>[...analyzeUrl(url)];
    final host = Uri.tryParse(url)?.host ?? '';
    if (c != null) {
      final s = await collect(c);
      if (s != null) reasons.addAll(analyzePage(s, host));
    }
    String? threat;
    if (NovaShieldService.isEnabled && url.startsWith('http')) {
      try {
        final t = await NovaShieldService.checkDomain(url);
        if (t.isThreat) threat = t.threatType;
      } catch (_) {}
    }
    reasons.sort((a, b) => b.points.compareTo(a.points));
    return ScamVerdict(reasons, shieldThreat: threat);
  }

  /// Text sent to NOVA AI (kept short: the AI service limits message size).
  static String aiPrompt(String url, String title, ScamVerdict v, String pageText) {
    final lines = v.reasons.map((r) => '- ${r.title}: ${r.detail}').join('\n');
    final excerpt = pageText.length > 1400 ? pageText.substring(0, 1400) : pageText;
    final s = StringBuffer()
      ..writeln('You are NOVA X Scam Explainer. Explain to a non-technical person, in simple friendly words, whether this web page '
          'looks like a scam and what they should do. Use short sections: "Verdict", "Why", "What to do". Be honest when '
          'evidence is weak; do not invent facts.')
      ..writeln('Address: $url')
      ..writeln('Title: $title')
      ..writeln('Local risk score: ${v.score}/100 (${v.label})${v.shieldThreat != null ? '; NOVA Shield flagged it as ${v.shieldThreat}' : ''}')
      ..writeln('Signals found:')
      ..writeln(lines.isEmpty ? '- none' : lines)
      ..writeln('Start of the page text:')
      ..writeln(excerpt);
    final out = s.toString();
    return out.length > 3800 ? out.substring(0, 3800) : out;
  }
}

/// The Scam Explainer dialog for the active tab.
Future<void> showScamExplainer(BuildContext context, ProTab t) {
  return showProDialog<void>(context, (ctx) => _ScamDialog(tab: t));
}

class _ScamDialog extends StatefulWidget {
  const _ScamDialog({required this.tab});
  final ProTab tab;

  @override
  State<_ScamDialog> createState() => _ScamDialogState();
}

class _ScamDialogState extends State<_ScamDialog> {
  ScamVerdict? _v;
  String _pageText = '';
  String? _ai;
  bool _asking = false;
  String? _aiError;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final c = widget.tab.web;
    final v = await ScamAnalyzer.check(widget.tab.url, c: c);
    if (c != null) {
      final s = await ScamAnalyzer.collect(c);
      _pageText = s?.text ?? '';
    }
    if (mounted) setState(() => _v = v);
  }

  Future<void> _explain() async {
    final v = _v;
    if (v == null || _asking) return;
    setState(() {
      _asking = true;
      _aiError = null;
    });
    try {
      final reply = await NovaApiClient().chat(ScamAnalyzer.aiPrompt(widget.tab.url, widget.tab.title, v, _pageText), const []);
      if (mounted) setState(() => _ai = reply);
    } on NovaApiException catch (e) {
      if (mounted) setState(() => _aiError = e.userMessage);
    } catch (_) {
      if (mounted) setState(() => _aiError = 'NOVA AI couldn’t answer right now. Please try again.');
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  static Future<void> _leave(ProTab t) => t.leavePage();

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    final v = _v;
    final t = widget.tab;
    return ProDialog(
      icon: Icons.gpp_maybe_rounded,
      title: 'Scam Explainer',
      guide: 'scam_explainer',
      subtitle: t.host.isEmpty ? t.url : t.host,
      width: 720,
      actions: [
        if (v != null && v.score >= 25)
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _leave(t);
            },
            icon: Icon(Icons.exit_to_app_rounded, color: p.danger, size: 18),
            label: Text('Leave this page', style: TextStyle(color: p.danger)),
          ),
        if (v != null && !t.incognito)
          FilledButton.icon(
            onPressed: _asking ? null : _explain,
            icon: _asking
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text(_ai == null ? 'Explain with NOVA AI' : 'Ask again'),
          ),
      ],
      child: v == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(20), children: [
              Row(children: [
                ProScoreRing(score: v.score, label: v.score >= 55 ? '!' : (v.score >= 25 ? '?' : '✓'), color: v.level.color(p)),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(v.label, style: p.title(size: 22, color: v.level.color(p))),
                    const SizedBox(height: 6),
                    Text(
                      v.score >= 55
                          ? 'Several strong warning signs. Don’t type passwords, card numbers or codes here, and don’t pay.'
                          : v.score >= 25
                              ? 'Some warning signs. Make sure you opened this site yourself and the address is exactly right.'
                              : 'Nothing suspicious found by NOVA X’s checks. Still, only share details with sites you trust.',
                      style: p.ui(size: 13, color: p.textMuted, height: 1.4),
                    ),
                    if (v.shieldThreat != null) ...[
                      const SizedBox(height: 8),
                      ProChip('NOVA Shield: ${v.shieldThreat}', color: p.danger, icon: Icons.shield_rounded),
                    ],
                  ]),
                ),
              ]),
              const SizedBox(height: 18),
              ProCard(
                title: v.reasons.isEmpty ? 'No warning signs found' : 'What NOVA X noticed',
                icon: Icons.fact_check_outlined,
                child: v.reasons.isEmpty
                    ? Text('The address, the forms and the wording look normal.', style: p.ui(size: 12.5, color: p.textMuted))
                    : Column(children: [
                        for (final r in v.reasons) ProFindingRow(level: r.level, title: r.title, detail: r.detail),
                      ]),
              ),
              if (_ai != null)
                ProCard(
                  title: 'NOVA AI explains',
                  icon: Icons.auto_awesome_rounded,
                  child: SelectableText(_ai!, style: p.ui(size: 13, color: p.text, height: 1.5)),
                ),
              if (_aiError != null) Text(_aiError!, style: p.ui(size: 12.5, color: p.danger)),
              if (t.incognito)
                Text('NOVA AI isn’t used in incognito tabs, so nothing from them leaves this phone.',
                    style: p.ui(size: 12, color: p.textFaint)),
              const SizedBox(height: 6),
              Text('These checks look for common tricks. They can’t prove a site is safe or guarantee it is a scam.',
                  style: p.ui(size: 11.5, color: p.textFaint)),
            ]),
    );
  }
}
