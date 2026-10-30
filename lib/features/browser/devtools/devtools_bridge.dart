// lib/features/browser/devtools/devtools_bridge.dart
//
// Calls into the inspector agent running in the page. Arguments are passed
// as data (callAsyncJavaScript arguments), never pasted into script text.

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'devtools_hooks.dart';

class DtResult {
  const DtResult(this.value, [this.error]);
  final Object? value;
  final String? error;
  bool get ok => error == null;

  Map<String, dynamic> get map => value is Map ? Map<String, dynamic>.from(value as Map) : const {};
  List<dynamic> get items => map['items'] is List ? map['items'] as List : const [];
}

class DevtoolsBridge {
  DevtoolsBridge(this.wvc);
  final InAppWebViewController? wvc;

  bool get attached => wvc != null;

  Future<DtResult> call(String fn, [Object? arg]) async {
    final c = wvc;
    if (c == null) return const DtResult(null, 'The page is not available.');
    try {
      await DevtoolsScripts.ensure(c);
      final r = await c.callAsyncJavaScript(
        functionBody: 'if (!window.__nxdt) return {error: "agent"}; return await window.__nxdt[fn](arg);',
        arguments: {'fn': fn, 'arg': arg},
      );
      if (r == null) return const DtResult(null, 'No answer from the page.');
      if (r.error != null) return DtResult(null, r.error);
      final v = r.value;
      if (v is Map && v['error'] is String && v.length <= 3) return DtResult(v, v['error'] as String);
      return DtResult(v);
    } catch (e) {
      return DtResult(null, '$e');
    }
  }

  /// Runs console input in the page (top-level await supported) and returns a
  /// preview {type, text, handle?, path?} or an error preview.
  Future<Map<String, dynamic>> evaluate(String code) async {
    final c = wvc;
    if (c == null) return {'type': 'error', 'text': 'The page is not available.'};
    await DevtoolsScripts.ensure(c);
    try {
      final r = await c.callAsyncJavaScript(
        functionBody: r'''
var v;
try {
  if (code.trim() === 'clear()') return {type: 'clear', text: ''};
  var AF = Object.getPrototypeOf(async function () {}).constructor;
  var isAwait = /\bawait\b/.test(code), isExpr = true;
  // Parse first (nothing runs) to know whether it's an expression.
  try { if (isAwait) new AF('return (' + code + '\n)'); else new Function('return (' + code + '\n)'); } catch (e) { isExpr = false; }
  var body = null;
  if (isAwait && !isExpr) {
    // "a; b" → return the value of the last expression, like Chrome does
    var i = code.lastIndexOf(';'), head = code.slice(0, i + 1), tail = code.slice(i + 1).trim();
    if (i > 0 && tail) { try { new AF(head + '\nreturn (' + tail + '\n)'); body = head + '\nreturn (' + tail + '\n)'; } catch (e) {} }
  }
  if (isAwait) v = await (0, eval)(isExpr ? '(async () => (' + code + '\n))()' : '(async () => {' + (body || code) + '\n})()');
  else v = (0, eval)(isExpr ? '(' + code + '\n)' : code);
  if (v && typeof v.then === 'function') { try { v = await v; } catch (e) { return {type: 'error', text: 'Uncaught (in promise) ' + (e && e.stack || e)}; } }
  return window.__nxdt.preview(v);
} catch (e) {
  var st = e && e.stack ? String(e.stack).split('\n').filter(function (l, k) { return k === 0 || !/eval at|<anonymous>/.test(l); }).slice(0, 5).join('\n') : String(e);
  return {type: 'error', text: 'Uncaught ' + st};
}
''',
        arguments: {'code': code},
      );
      if (r == null) return {'type': 'error', 'text': 'No answer from the page.'};
      if (r.error != null) return {'type': 'error', 'text': r.error};
      final v = r.value;
      return v is Map ? Map<String, dynamic>.from(v) : {'type': 'undefined', 'text': 'undefined'};
    } catch (e) {
      return {'type': 'error', 'text': '$e'};
    }
  }
}
