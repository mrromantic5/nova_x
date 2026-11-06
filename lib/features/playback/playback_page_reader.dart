// lib/features/playback/playback_page_reader.dart
//
// AI Playback (3.12.0): reads the open page's readable text — title, language,
// description, headings and the main text — the way "Listen to this page"
// does. Menus, footers, forms, cookie banners and hidden elements are skipped.
// Nothing leaves the phone here; the text is only sent when the user taps ▶.

import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// The page as AI Playback sees it.
class PageSnapshot {
  const PageSnapshot({
    required this.url,
    required this.title,
    required this.lang,
    required this.description,
    required this.text,
    required this.headings,
    required this.words,
    required this.sensitive,
  });

  final String url;
  final String title;
  final String lang;
  final String description;
  final String text;
  final List<String> headings;
  final int words;

  /// Password, card or one-time-code fields on the page: AI Playback is off.
  final bool sensitive;

  /// Enough to talk about (the Worker needs at least 400 characters).
  bool get playable => !sensitive && text.length >= PlaybackPageReader.minChars;

  String get host => Uri.tryParse(url)?.host.replaceFirst(RegExp(r'^www\.'), '') ?? '';

  static PageSnapshot? fromJson(String url, Object? raw) {
    Object? j = raw;
    if (j is String) {
      try {
        j = jsonDecode(j);
      } catch (_) {
        return null;
      }
    }
    if (j is! Map || j['ok'] != true) return null;
    String s(String k) => j[k] is String ? j[k] as String : '';
    return PageSnapshot(
      url: url,
      title: s('title').trim(),
      lang: s('lang').trim(),
      description: s('description').trim(),
      text: s('text').trim(),
      headings: j['headings'] is List ? (j['headings'] as List).whereType<String>().toList() : const [],
      words: j['words'] is num ? (j['words'] as num).toInt() : 0,
      sensitive: j['sensitive'] == true,
    );
  }
}

class PlaybackPageReader {
  PlaybackPageReader._();

  static const int minChars = 400;

  /// Only normal web pages (not nova://, file:, data:, about:…).
  static bool isWebPage(String url) => url.startsWith('https://') || url.startsWith('http://');

  /// Quick check after each page load: is there enough text, and no
  /// password/card fields? Returns false when the page can't be read.
  static Future<bool> quickCheck(InAppWebViewController c) async {
    try {
      final r = await c.evaluateJavascript(source: kPlaybackQuickCheckJs);
      return r == true || r == 'true';
    } catch (_) {
      return false;
    }
  }

  static Future<PageSnapshot?> read(InAppWebViewController c, String url) async {
    try {
      return PageSnapshot.fromJson(url, await c.evaluateJavascript(source: kPlaybackReaderJs));
    } catch (_) {
      return null;
    }
  }
}

const String _kSensitiveSelector =
    "input[type=password],input[autocomplete^=cc-],input[autocomplete=one-time-code],"
    "input[name*=card i],input[name*=cvv i],input[name*=cvc i],input[id*=cardnumber i]";

/// true when the page has ≥ 400 characters of text and no sensitive fields.
const String kPlaybackQuickCheckJs = '''
(function(){try{
  var d=document,b=d.body; if(!b) return false;
  if(d.querySelector("$_kSensitiveSelector")) return false;
  return (b.innerText||'').replace(/\\s+/g,' ').length >= 600;
}catch(e){return false;}})();
''';

/// Returns a JSON string: { ok, title, lang, description, text, headings, words, sensitive }.
const String kPlaybackReaderJs = '''
(function(){try{
  var d=document,b=d.body; if(!b) return JSON.stringify({ok:false});
  var sensitive=!!d.querySelector("$_kSensitiveSelector");
  function clean(s){return (s||'').replace(/\\s+/g,' ').trim();}
  function txt(el){return clean(el.innerText||el.textContent);}
  function visible(el){return !!(el.offsetWidth||el.offsetHeight||el.getClientRects().length);}
  var SKIP='nav,footer,aside,script,style,noscript,template,svg,canvas,iframe,form,button,select,textarea,'+
    '[role=navigation],[role=contentinfo],[role=dialog],[aria-hidden=true],[hidden],'+
    '[class*=cookie i],[id*=cookie i],[class*=consent i],[class*=newsletter i],[class*=advert i],[id*=advert i],.ad,.ads';
  var root=d.querySelector('article,main,[role=main]');
  if(!root||txt(root).split(' ').length<120) root=b;
  var nodes=root.querySelectorAll('h1,h2,h3,h4,p,li,blockquote,figcaption,td,th,dt,dd,summary,pre');
  var out=[],heads=[],seen={},total=0;
  for(var i=0;i<nodes.length;i++){
    var n=nodes[i];
    if(n.closest(SKIP)||!visible(n)) continue;
    if(n.matches('li,td,th,dd,blockquote')&&n.querySelector('p,li,h1,h2,h3,h4')) continue;
    var t=txt(n); if(t.length<2||seen[t]) continue; seen[t]=1;
    if(/^H[1-4]\$/.test(n.tagName)){ if(heads.length<40) heads.push(t.slice(0,120)); out.push('\\n## '+t); }
    else out.push(t);
    total+=t.length; if(total>24000) break;
  }
  var text=out.join('\\n').trim();
  // Sites built only with <div>s: fall back to the page's visible text.
  if(text.length<400) text=txt(root===b?b:root).slice(0,24000);
  var m=d.querySelector('meta[name=description],meta[property="og:description"]');
  return JSON.stringify({ok:true,title:clean(d.title).slice(0,200),
    lang:((d.documentElement.getAttribute('lang')||'')+'').slice(0,12),
    description:clean(m&&m.content).slice(0,500),text:text,headings:heads,
    words:text?text.split(/\\s+/).length:0,sensitive:sensitive});
}catch(e){return JSON.stringify({ok:false});}})();
''';
