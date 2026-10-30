// lib/features/xcoder/run/js_runner.dart
//
// Runs JavaScript on the phone, offline, in the V8 engine of Android System
// WebView (a hidden page). Used by the terminal's `node` command and by ▶ Run
// for .js files.
//
// Honest limits (shown in `help`): it's a browser JavaScript engine, not
// Node.js — console, timers, Promises/async, fetch, JSON, Intl, classes and
// modern syntax work; `require`, `fs`, `process.exit`, npm packages don't.
// A run is stopped after the time limit; the hidden page is then destroyed,
// which also ends endless loops.

import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class JsRunLine {
  const JsRunLine(this.level, this.text);
  final String level; // log | info | warn | error | debug | result
  final String text;
}

class JsRunner {
  JsRunner._();

  static const Duration defaultLimit = Duration(seconds: 15);

  /// Runs [code] and streams console output. Completes when the script (and
  /// its pending promises and timers, up to [limit]) are done.
  static Stream<JsRunLine> run(String code, {String fileName = 'main.js', List<String> args = const [],
      Duration limit = defaultLimit}) {
    final out = StreamController<JsRunLine>();
    HeadlessInAppWebView? hv;
    Timer? timer;
    var finished = false;

    Future<void> finish([JsRunLine? last]) async {
      if (finished) return;
      finished = true;
      timer?.cancel();
      if (last != null) out.add(last);
      try {
        await hv?.dispose();
      } catch (_) {}
      await out.close();
    }

    hv = HeadlessInAppWebView(
      initialData: InAppWebViewInitialData(data: '<!doctype html><html><head><meta charset="utf-8"></head><body></body></html>',
          baseUrl: WebUri('https://xcoder.run/')),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        allowFileAccess: false,
        allowContentAccess: false,
        cacheEnabled: false,
        clearCache: true,
      ),
      onWebViewCreated: (c) {
        c.addJavaScriptHandler(handlerName: 'xcRun', callback: (a) {
          if (a.isEmpty || a.first is! Map) return null;
          final m = a.first as Map;
          final line = JsRunLine(m['level']?.toString() ?? 'log', m['text']?.toString() ?? '');
          if (!finished) out.add(line);
          if (m['done'] == true) finish();
          return null;
        });
      },
      onLoadStop: (c, _) async {
        timer = Timer(limit, () => finish(JsRunLine('error',
            'Stopped after ${limit.inSeconds} s (time limit). Endless loop or a timer that never ends?')));
        try {
          await c.callAsyncJavaScript(functionBody: _harness, arguments: {'code': code, 'file': fileName, 'args': args});
        } catch (e) {
          finish(JsRunLine('error', 'Could not start: $e'));
        }
      },
      onReceivedError: (c, r, e) => finish(JsRunLine('error', 'Runner error: ${e.description}')),
    );
    hv.run().catchError((Object e) => finish(JsRunLine('error', 'Runner unavailable: $e')));
    out.onCancel = () => finish();
    return out.stream;
  }

  /// The script is passed as data (an argument), never pasted into script text.
  static const String _harness = r'''
var send = function(level, text, done){
  try { window.flutter_inappwebview.callHandler('xcRun', {level: level, text: String(text), done: !!done}); } catch(e){}
};
var fmt = function(v, depth){
  depth = depth || 0;
  try {
    if (typeof v === 'string') return depth ? JSON.stringify(v) : v;
    if (v instanceof Error){
      var ls = String(v.stack || '').split('\n');
      var keep = ls.slice(1).filter(function(l){ return l.indexOf(file + ':') >= 0; }).map(function(l){ return l.replace(/\(?eval at[^,]*,\s*/, '').replace(/^\s*at eval \((.*)\)$/, '    at $1'); });
      return (v.name + ': ' + v.message) + (keep.length ? '\n' + keep.join('\n') : '');
    }
    if (typeof v === 'function') return '[Function ' + (v.name || 'anonymous') + ']';
    if (typeof v === 'symbol' || typeof v === 'bigint') return v.toString() + (typeof v === 'bigint' ? 'n' : '');
    if (v === undefined) return 'undefined';
    if (v instanceof Map) return 'Map(' + v.size + ') ' + JSON.stringify(Object.fromEntries(v), null, 2);
    if (v instanceof Set) return 'Set(' + v.size + ') ' + JSON.stringify(Array.from(v));
    var seen = new WeakSet();
    return JSON.stringify(v, function(k, x){
      if (typeof x === 'object' && x !== null){ if (seen.has(x)) return '[Circular]'; seen.add(x); }
      if (typeof x === 'bigint') return x.toString() + 'n';
      if (typeof x === 'function') return '[Function ' + (x.name || 'anonymous') + ']';
      if (x === undefined) return '[undefined]';
      return x;
    }, 2);
  } catch(e){ return String(v); }
};
var line = function(args){ return Array.prototype.map.call(args, function(a){ return fmt(a); }).join(' '); };
var active = 0, idleTimer = null, ended = false;
var rawST = window.setTimeout.bind(window), rawCT = window.clearTimeout.bind(window);
var checkIdle = function(){
  rawCT(idleTimer);
  idleTimer = rawST(function(){ if (active <= 0 && !ended){ ended = true; send('info', '', true); } }, 60);
};
['log','info','warn','error','debug'].forEach(function(l){
  console[l] = function(){ send(l, line(arguments)); };
});
console.table = function(d){
  try {
    var rows = Array.isArray(d) ? d : Object.keys(d).map(function(k){ var r = d[k]; return (typeof r === 'object' && r) ? Object.assign({'(index)': k}, r) : {'(index)': k, Value: r}; });
    if (Array.isArray(d)) rows = rows.map(function(r, i){ return (typeof r === 'object' && r) ? Object.assign({'(index)': i}, r) : {'(index)': i, Value: r}; });
    var cols = []; rows.forEach(function(r){ Object.keys(r).forEach(function(k){ if (cols.indexOf(k) < 0) cols.push(k); }); });
    var cell = function(v){ return v === undefined ? '' : (typeof v === 'object' ? JSON.stringify(v) : String(v)); };
    var w = cols.map(function(c){ return Math.max(c.length, Math.max.apply(null, rows.map(function(r){ return cell(r[c]).length; }).concat([0]))); });
    var sep = '┼' ;
    var fmtRow = function(vals){ return '│ ' + vals.map(function(v, i){ return (v + ' '.repeat(w[i])).slice(0, w[i]); }).join(' │ ') + ' │'; };
    var out = [fmtRow(cols), '├' + w.map(function(n){ return '─'.repeat(n + 2); }).join(sep) + '┤'];
    rows.forEach(function(r){ out.push(fmtRow(cols.map(function(c){ return cell(r[c]); }))); });
    send('log', out.join('\n'));
  } catch(e){ send('log', fmt(d)); }
};
var counts = {}, timers = {};
console.count = function(l){ l = l || 'default'; counts[l] = (counts[l] || 0) + 1; send('log', l + ': ' + counts[l]); };
console.time = function(l){ timers[l || 'default'] = performance.now(); };
console.timeEnd = function(l){ l = l || 'default'; if (timers[l] != null){ send('log', l + ': ' + (performance.now() - timers[l]).toFixed(3) + ' ms'); delete timers[l]; } };
console.assert = function(c){ if (!c) send('error', 'Assertion failed: ' + line(Array.prototype.slice.call(arguments, 1))); };
console.dir = function(o){ send('log', fmt(o)); };
console.group = function(){ if (arguments.length) send('log', '▼ ' + line(arguments)); };
console.groupEnd = function(){};
console.clear = function(){};
// track timers so the run ends when nothing is left to do
var oST = rawST, oCT = rawCT, live = new Set();
window.setTimeout = function(fn, ms){
  active++;
  var id = oST(function(){ live.delete(id); active--; try { typeof fn === 'function' ? fn() : (0, eval)(fn); } catch(e){ send('error', 'Uncaught ' + fmt(e)); } checkIdle(); }, ms);
  live.add(id); return id;
};
window.clearTimeout = function(id){ if (live.delete(id)) active--; oCT(id); checkIdle(); };
var oSI = window.setInterval, oCI = window.clearInterval, intervals = new Set();
window.setInterval = function(fn, ms){ active++; var id = oSI(function(){ try { fn(); } catch(e){ send('error', 'Uncaught ' + fmt(e)); } }, ms); intervals.add(id); return id; };
window.clearInterval = function(id){ if (intervals.delete(id)) active--; oCI(id); checkIdle(); };
window.addEventListener('unhandledrejection', function(e){ send('error', 'Uncaught (in promise) ' + fmt(e.reason)); });
window.addEventListener('error', function(e){ send('error', 'Uncaught ' + (e.error ? fmt(e.error) : e.message)); });
// Node-ish globals
window.global = window;
window.process = { argv: ['node', file].concat(args || []), env: {}, platform: 'android', version: 'v-xcoder',
  exit: function(c){ ended = true; send('info', 'process.exit(' + (c || 0) + ')', true); throw new Error('__xc_exit'); },
  stdout: { write: function(s){ send('log', s); return true; } }, stderr: { write: function(s){ send('error', s); return true; } },
  nextTick: function(f){ Promise.resolve().then(f); }, hrtime: { bigint: function(){ return BigInt(Math.round(performance.now() * 1e6)); } } };
window.module = { exports: {} }; window.exports = window.module.exports;
window.require = function(name){
  throw new Error("require('" + name + "') isn't available: X Coder runs JavaScript in the phone's V8 engine, not Node.js. Built-ins like console, fetch, JSON, Promise and timers work.");
};
active++;
try {
  var r = (0, eval)(code + '\n//# sourceURL=' + file);
  if (r && typeof r.then === 'function'){
    r.then(function(){ active--; checkIdle(); }, function(e){ active--; send('error', 'Uncaught (in promise) ' + fmt(e)); checkIdle(); });
  } else { active--; checkIdle(); }
} catch(e){
  active--;
  if (String(e && e.message) !== '__xc_exit') send('error', 'Uncaught ' + fmt(e));
  checkIdle();
}
''';
}
