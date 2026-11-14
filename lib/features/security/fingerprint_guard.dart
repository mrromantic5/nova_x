// lib/features/security/fingerprint_guard.dart
//
// Fingerprint protection ("farbling"): every site sees slightly different
// canvas, audio and (strict) WebGL / hardware values, so a fingerprint taken
// on one site can't be matched on another — while each site sees the SAME
// values for the whole session, so nothing flickers or breaks.
//
// The values come from a secret made fresh each time NOVA X starts and the
// top-level site (eTLD+1-like), so after a restart every site sees new
// values. This replaces the old approach (only setting Do-Not-Track), which
// did nothing against fingerprinting.
//
// Levels: off · standard (canvas + audio noise) · strict (+ generic WebGL
// vendor/renderer, rounded hardware values). Set per site in the Site
// Control Center; default in the Security Center.
// Android (3.13.0): the same script as NOVA X for PC, injected at document
// start in NOVA X's own WebView only (never in other apps).

import 'dart:convert';
import 'dart:math';

import 'site_controls.dart';

class FingerprintGuard {
  FingerprintGuard._();

  /// Secret for this run of NOVA X (never sent to pages as a value they can read).
  static final String sessionKey = _newKey();

  static String _newKey() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  /// The document-start script for a tab (null when protection is off everywhere).
  static String? script() {
    final sc = SiteControls.instance;
    final overrides = sc.fingerprintOverrides();
    final def = sc.fingerprintDefault.name;
    if (def == 'off' && overrides.values.every((v) => v == 'off')) return null;
    return build(key: sessionKey, defaultLevel: def, overrides: overrides);
  }

  /// Pure: the script text (public for tests).
  static String build({required String key, required String defaultLevel, required Map<String, String> overrides}) {
    return _template
        .replaceFirst('__KEY__', key)
        .replaceFirst('__DEF__', defaultLevel)
        .replaceFirst('__LEVELS__', jsonEncode(overrides));
  }

  static const String _template = r'''
(function(){
  'use strict';
  if (window.__novaFp) return;
  try { Object.defineProperty(window, '__novaFp', { value: 1 }); } catch (e) { return; }
  var KEY = '__KEY__', DEF = '__DEF__', LEVELS = __LEVELS__;

  function topHost() {
    try { var ao = location.ancestorOrigins; if (ao && ao.length) return new URL(ao[ao.length - 1]).hostname; } catch (e) {}
    try { return window.top.location.hostname; } catch (e) {}
    return location.hostname;
  }
  function site(h) {
    h = (h || '').toLowerCase().replace(/\.$/, '');
    if (/^\d+\.\d+\.\d+\.\d+$/.test(h) || h.indexOf(':') >= 0) return h;
    var p = h.split('.');
    if (p.length <= 2) return h;
    var two = { co:1, com:1, net:1, org:1, gov:1, edu:1, ac:1, or:1, ne:1, go:1 };
    if (two[p[p.length - 2]] && p[p.length - 1].length === 2) return p.slice(-3).join('.');
    return p.slice(-2).join('.');
  }
  var SITE = site(topHost());
  var level = LEVELS[SITE] || DEF;
  if (level === 'off') return;

  function fnv(s) { var h = 2166136261 >>> 0; for (var i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619) >>> 0; } return h >>> 0; }
  var SEED = fnv(KEY + '|' + SITE);
  function mix(i) { var x = (SEED ^ Math.imul((i + 1) >>> 0, 2654435761)) >>> 0; x ^= x >>> 15; x = Math.imul(x, 2246822519) >>> 0; x ^= x >>> 13; x = Math.imul(x, 3266489917) >>> 0; x ^= x >>> 16; return x >>> 0; }

  // Wrappers look native to toString().
  var nativeNames = new WeakMap();
  var fnToString = Function.prototype.toString;
  function hide(fn, name) { nativeNames.set(fn, name); return fn; }
  try {
    var ts = hide(function toString() { var n = nativeNames.get(this); return n ? 'function ' + n + '() { [native code] }' : fnToString.call(this); }, 'toString');
    Function.prototype.toString = ts;
  } catch (e) {}
  function wrap(obj, name, make) {
    try {
      var orig = obj[name]; if (typeof orig !== 'function') return;
      var w = make(orig); hide(w, name);
      Object.defineProperty(obj, name, { value: w, writable: true, configurable: true, enumerable: false });
    } catch (e) {}
  }

  // ── Canvas: flip the lowest bit of a few pixels, the same way every time ──
  function farbleData(data) {
    for (var i = 0, px = 0; i < data.length; i += 4, px++) {
      if ((mix(px) & 255) < 6) { var c = (mix(px + 7) % 3); data[i + c] = data[i + c] ^ 1; }
    }
  }
  var getImageData = CanvasRenderingContext2D.prototype.getImageData;
  wrap(CanvasRenderingContext2D.prototype, 'getImageData', function (orig) {
    return function getImageData() { var img = orig.apply(this, arguments); try { farbleData(img.data); } catch (e) {} return img; };
  });
  function farbledCopy(canvas) {
    var w = canvas.width, h = canvas.height;
    if (!w || !h || w * h > 16777216) return null;
    var copy = document.createElement('canvas'); copy.width = w; copy.height = h;
    var ctx = copy.getContext('2d'); if (!ctx) return null;
    ctx.drawImage(canvas, 0, 0);
    var img = getImageData.call(ctx, 0, 0, w, h); farbleData(img.data); ctx.putImageData(img, 0, 0);
    return copy;
  }
  wrap(HTMLCanvasElement.prototype, 'toDataURL', function (orig) {
    return function toDataURL() { try { var c = farbledCopy(this); if (c) return orig.apply(c, arguments); } catch (e) {} return orig.apply(this, arguments); };
  });
  wrap(HTMLCanvasElement.prototype, 'toBlob', function (orig) {
    return function toBlob() { try { var c = farbledCopy(this); if (c) return orig.apply(c, arguments); } catch (e) {} return orig.apply(this, arguments); };
  });

  // ── Audio: inaudible, stable noise on rendered audio ──
  var touched = new WeakSet();
  if (window.AudioBuffer) {
    wrap(AudioBuffer.prototype, 'getChannelData', function (orig) {
      return function getChannelData() {
        var d = orig.apply(this, arguments);
        try { if (!touched.has(d)) { touched.add(d); for (var i = 0; i < d.length; i += 97) { d[i] = d[i] + ((mix(i) / 4294967296) - 0.5) * 1e-7; } } } catch (e) {}
        return d;
      };
    });
  }
  if (window.AnalyserNode) {
    wrap(AnalyserNode.prototype, 'getFloatFrequencyData', function (orig) {
      return function getFloatFrequencyData(arr) {
        var r = orig.apply(this, arguments);
        try { for (var i = 0; i < arr.length; i += 7) { arr[i] = arr[i] + ((mix(i + 3) / 4294967296) - 0.5) * 1e-4; } } catch (e) {}
        return r;
      };
    });
  }

  if (level !== 'strict') return;

  // ── Strict: generic GPU strings, rounded hardware values ──
  function glParam(proto) {
    wrap(proto, 'getParameter', function (orig) {
      return function getParameter(p) {
        if (p === 37445) return 'Google Inc.';
        if (p === 37446) return 'ANGLE (Generic, OpenGL ES)';
        return orig.apply(this, arguments);
      };
    });
  }
  if (window.WebGLRenderingContext) glParam(WebGLRenderingContext.prototype);
  if (window.WebGL2RenderingContext) glParam(WebGL2RenderingContext.prototype);
  try { Object.defineProperty(Navigator.prototype, 'hardwareConcurrency', { get: hide(function hardwareConcurrency() { return 4; }, 'get hardwareConcurrency'), configurable: true }); } catch (e) {}
  try { if ('deviceMemory' in Navigator.prototype) Object.defineProperty(Navigator.prototype, 'deviceMemory', { get: hide(function deviceMemory() { return 8; }, 'get deviceMemory'), configurable: true }); } catch (e) {}
})();''';
}
