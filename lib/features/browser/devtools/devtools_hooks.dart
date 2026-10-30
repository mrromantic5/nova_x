// lib/features/browser/devtools/devtools_hooks.dart
//
// Scripts for NOVA X Dev Tools.
//
// kDevtoolsHook runs at document start in every page of the browser (as the
// console/network hooks did before 3.11.0) and only forwards to the app:
//   console.* calls (with source location), uncaught errors and rejected
//   promises → 'novaxLog'; fetch() and XMLHttpRequest calls (method, URL,
//   status, timing, size, type) → 'novaxNet'.
// Request/response bodies and headers are recorded only after the developer
// opens Dev Tools on that tab (window.__nxdtArmed), and stay on the phone.
//
// The inspector agent (assets/devtools/nxdt_agent.js) is injected only when
// Dev Tools is opened.

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

const String kDevtoolsHook = r'''
(function(){
  if (window.__novax_hook3) return;
  window.__novax_hook3 = true; window.__novax_patched = true; window.__novax_net = true;
  var H = function(name, o){ try { window.flutter_inappwebview.callHandler(name, o); } catch(e){} };
  var MAXB = 200000;
  function clip(s, n){ s = String(s); return s.length > n ? s.slice(0, n) : s; }
  function fmt(a){
    try {
      if (a instanceof Error) return a.stack || (a.name + ': ' + a.message);
      if (typeof Element !== 'undefined' && a instanceof Element) return '<' + a.localName + (a.id ? '#' + a.id : '') + (a.className && typeof a.className === 'string' ? '.' + a.className.trim().split(/\s+/).join('.') : '') + '>';
      if (typeof a === 'function') return 'ƒ ' + (a.name || 'anonymous') + '()';
      if (typeof a === 'object' && a !== null) {
        var seen = new WeakSet();
        return JSON.stringify(a, function(k, v){ if (typeof v === 'object' && v !== null){ if (seen.has(v)) return '[Circular]'; seen.add(v); } if (typeof v === 'bigint') return v + 'n'; return v; }, 1);
      }
      return String(a);
    } catch(e){ return '[Object]'; }
  }
  function short(u){ var f = String(u).split('#')[0].split('?')[0]; return f.split('/').pop() || '(index)'; }
  function where(){
    try {
      var st = (new Error()).stack.split('\n');
      for (var i = 3; i < st.length; i++){
        var m = st[i].match(/(https?:\/\/[^\s)]+):(\d+):(\d+)/);
        if (m && m[1].indexOf('__nx') < 0) return short(m[1]) + ':' + m[2];
      }
    } catch(e){}
    return '';
  }
  function send(type, msg, src, stack){
    H('novaxLog', { type: type, msg: clip(msg, 8000), time: new Date().toLocaleTimeString(), ts: Date.now(), src: src || '', stack: stack ? clip(stack, 4000) : '' });
  }
  var counts = {}, timers = {}, groups = 0;
  ['log','warn','error','info','debug'].forEach(function(t){
    var orig = console[t] ? console[t].bind(console) : function(){};
    console[t] = function(){
      var args = Array.prototype.slice.call(arguments);
      var msg = args.map(fmt).join(' ');
      if (typeof args[0] === 'string' && /%[sdifoOc]/.test(args[0])) {
        var i = 1; msg = args[0].replace(/%([sdifoOc])/g, function(m, c){ if (c === 'c') { i++; return ''; } return i < args.length ? fmt(args[i++]) : m; });
        if (i < args.length) msg += ' ' + args.slice(i).map(fmt).join(' ');
      }
      send(t, (groups ? new Array(groups + 1).join('  ') : '') + msg, where(), t === 'error' ? (new Error()).stack : '');
      return orig.apply(console, arguments);
    };
  });
  var otable = console.table; console.table = function(d){ send('log', fmt(d), where()); return otable && otable.apply(console, arguments); };
  console.count = function(l){ l = l === undefined ? 'default' : l; counts[l] = (counts[l] || 0) + 1; send('log', l + ': ' + counts[l], where()); };
  console.countReset = function(l){ counts[l === undefined ? 'default' : l] = 0; };
  console.time = function(l){ timers[l === undefined ? 'default' : l] = performance.now(); };
  console.timeLog = function(l){ l = l === undefined ? 'default' : l; if (timers[l] != null) send('log', l + ': ' + (performance.now() - timers[l]).toFixed(1) + ' ms', where()); };
  console.timeEnd = function(l){ console.timeLog(l); delete timers[l === undefined ? 'default' : l]; };
  console.assert = function(c){ if (!c) send('error', 'Assertion failed: ' + Array.prototype.slice.call(arguments, 1).map(fmt).join(' '), where()); };
  var og = console.group, oge = console.groupEnd;
  console.group = console.groupCollapsed = function(){ send('log', '▼ ' + Array.prototype.map.call(arguments, fmt).join(' '), where()); groups++; };
  console.groupEnd = function(){ if (groups > 0) groups--; };
  window.addEventListener('error', function(e){
    if (e.target && e.target !== window && e.target.localName) {
      var u = e.target.src || e.target.href || '';
      send('error', 'Failed to load ' + e.target.localName + ': ' + u, '');
      return;
    }
    var m = e.message || 'Error';
    send('error', /^Uncaught/.test(m) ? m : 'Uncaught ' + m,
      e.filename ? short(e.filename) + ':' + e.lineno + ':' + e.colno : '', e.error && e.error.stack);
  }, true);
  window.addEventListener('unhandledrejection', function(e){
    var r = e.reason; send('error', 'Uncaught (in promise) ' + (r && r.message ? (r.name ? r.name + ': ' : '') + r.message : fmt(r)), '', r && r.stack);
  });
  document.addEventListener('securitypolicyviolation', function(e){
    send('error', 'CSP blocked ' + (e.blockedURI || 'inline') + ' (' + e.violatedDirective + ')', e.sourceFile ? short(e.sourceFile) + ':' + e.lineNumber : '');
  });

  // ── Network ──
  var seq = 0;
  function armed(){ return window.__nxdtArmed === true; }
  function hdrs(h){ var o = {}; try { if (h && h.forEach) h.forEach(function(v, k){ o[k] = v; }); else if (h && typeof h === 'object') for (var k in h) o[k.toLowerCase()] = String(h[k]); } catch(e){} return o; }
  function bodyText(b){
    if (b == null) return '';
    if (typeof b === 'string') return clip(b, MAXB);
    if (b instanceof URLSearchParams) return clip(b.toString(), MAXB);
    if (typeof FormData !== 'undefined' && b instanceof FormData){ var p = []; b.forEach(function(v, k){ p.push(k + '=' + (typeof v === 'string' ? v : '[file ' + (v.name || '') + ']')); }); return clip(p.join('&'), MAXB); }
    if (b instanceof Blob) return '[binary ' + b.size + ' bytes]';
    if (b instanceof ArrayBuffer || ArrayBuffer.isView(b)) return '[binary ' + b.byteLength + ' bytes]';
    return clip(String(b), MAXB);
  }
  function textual(ct){ return /json|text|javascript|xml|html|css|x-www-form-urlencoded|graphql/.test(ct || ''); }
  function abs(u){ try { return new URL(u, location.href).href; } catch(e){ return String(u); } }
  if (window.fetch) {
    var of = window.fetch;
    window.fetch = function(input, init){
      var id = 'f' + (++seq), t0 = performance.now(), start = Date.now();
      var url = abs(input && input.url ? input.url : input);
      var method = ((init && init.method) || (input && input.method) || 'GET').toUpperCase();
      var rec = { id: id, url: url, method: method, type: 'fetch', start: start };
      if (armed()) { rec.reqHeaders = hdrs((init && init.headers) || (input && input.headers)); rec.reqBody = bodyText(init && init.body); }
      H('novaxNet', Object.assign({ phase: 'start' }, rec));
      return of.apply(this, arguments).then(function(res){
        var out = Object.assign({}, rec, { phase: 'end', status: res.status, statusText: res.statusText, ms: Math.round(performance.now() - t0),
          mime: (res.headers.get('content-type') || '').split(';')[0], size: +(res.headers.get('content-length') || 0), redirected: res.redirected });
        if (armed()) {
          out.resHeaders = hdrs(res.headers);
          if (textual(res.headers.get('content-type'))) {
            res.clone().text().then(function(t){ out.resBody = clip(t, MAXB); out.size = out.size || t.length; H('novaxNet', out); }, function(){ H('novaxNet', out); });
            return res;
          }
        }
        H('novaxNet', out);
        return res;
      }, function(err){
        H('novaxNet', Object.assign({}, rec, { phase: 'end', status: 0, ms: Math.round(performance.now() - t0), error: String(err && err.message || err) }));
        throw err;
      });
    };
  }
  var OX = window.XMLHttpRequest;
  if (OX) {
    var oo = OX.prototype.open, os = OX.prototype.send, osh = OX.prototype.setRequestHeader;
    OX.prototype.open = function(m, u){ this.__nx = { id: 'x' + (++seq), method: String(m || 'GET').toUpperCase(), url: abs(u), reqHeaders: {} }; return oo.apply(this, arguments); };
    OX.prototype.setRequestHeader = function(k, v){ if (this.__nx) this.__nx.reqHeaders[String(k).toLowerCase()] = String(v); return osh.apply(this, arguments); };
    OX.prototype.send = function(body){
      var x = this, n = x.__nx, t0 = performance.now();
      if (n) {
        var rec = { id: n.id, url: n.url, method: n.method, type: 'xhr', start: Date.now() };
        if (armed()) { rec.reqHeaders = n.reqHeaders; rec.reqBody = bodyText(body); }
        H('novaxNet', Object.assign({ phase: 'start' }, rec));
        x.addEventListener('loadend', function(){
          var ct = x.getResponseHeader('content-type') || '';
          var out = Object.assign({}, rec, { phase: 'end', status: x.status, statusText: x.statusText, ms: Math.round(performance.now() - t0), mime: ct.split(';')[0] });
          try { out.size = (x.responseType === '' || x.responseType === 'text') ? (x.responseText || '').length : +(x.getResponseHeader('content-length') || 0); } catch(e){}
          if (x.status === 0) out.error = 'Network error or blocked (CORS)';
          if (armed()) {
            var hs = {}; (x.getAllResponseHeaders() || '').trim().split(/[\r\n]+/).forEach(function(l){ var i = l.indexOf(':'); if (i > 0) hs[l.slice(0, i).trim().toLowerCase()] = l.slice(i + 1).trim(); });
            out.resHeaders = hs;
            try { if ((x.responseType === '' || x.responseType === 'text') && textual(ct)) out.resBody = clip(x.responseText, MAXB); else if (x.responseType === 'json') out.resBody = clip(JSON.stringify(x.response), MAXB); } catch(e){}
          }
          H('novaxNet', out);
        });
      }
      return os.apply(this, arguments);
    };
  }
  // WebSockets are wrapped only on tabs where Dev Tools was opened.
  if (window.WebSocket && armed()) {
    var OW = window.WebSocket;
    var W = function(u, p){
      var ws = p === undefined ? new OW(u) : new OW(u, p);
      var id = 'w' + (++seq), t0 = Date.now();
      H('novaxNet', { phase: 'start', id: id, url: abs(u), method: 'GET', type: 'websocket', start: t0 });
      ws.addEventListener('open', function(){ H('novaxNet', { phase: 'end', id: id, url: abs(u), method: 'GET', type: 'websocket', status: 101, statusText: 'Switching Protocols', ms: Date.now() - t0, start: t0 }); });
      if (armed()) {
        var osend = ws.send;
        ws.send = function(d){ H('novaxNet', { phase: 'frame', id: id, dir: 'out', data: bodyText(d), time: Date.now() }); return osend.apply(ws, arguments); };
        ws.addEventListener('message', function(e){ H('novaxNet', { phase: 'frame', id: id, dir: 'in', data: bodyText(e.data), time: Date.now() }); });
      }
      ws.addEventListener('close', function(e){ H('novaxNet', { phase: 'frame', id: id, dir: 'close', data: 'closed ' + e.code + (e.reason ? ' ' + e.reason : ''), time: Date.now() }); });
      return ws;
    };
    W.prototype = OW.prototype; W.CONNECTING = 0; W.OPEN = 1; W.CLOSING = 2; W.CLOSED = 3;
    window.WebSocket = W;
  }
})();
''';

/// Marks the tab as "Dev Tools open": from now on request/response headers
/// and bodies are recorded for this tab (kept in the app's memory only).
const String kDevtoolsArm = 'window.__nxdtArmed = true;';

class DevtoolsScripts {
  DevtoolsScripts._();
  static String? _agent;

  static Future<String> agent() async => _agent ??= await rootBundle.loadString('assets/devtools/nxdt_agent.js');

  /// Injects the inspector agent (idempotent) and arms body capture.
  static Future<void> ensure(InAppWebViewController c) async {
    try {
      final ok = await c.evaluateJavascript(source: 'window.__nxdt && window.__nxdt.v === 3');
      if (ok != true) await c.evaluateJavascript(source: await agent());
      await c.evaluateJavascript(source: kDevtoolsArm);
    } catch (_) {}
  }
}
