// lib/features/xcoder/run/preview_server.dart
//
// Serves a project folder on http://127.0.0.1:<port>/ (this phone only) so
// HTML, CSS, JS, images and fetch() calls between files work like on a real
// web server. HTML pages get a tiny script that sends console messages and
// errors to the X Coder preview console. Nothing is reachable from other
// devices (bound to the loopback address).

import 'dart:async';
import 'dart:io';

class PreviewServer {
  PreviewServer._();
  static final PreviewServer instance = PreviewServer._();

  HttpServer? _server;
  String? _root;

  int? get port => _server?.port;
  bool get running => _server != null;

  /// Starts (or re-roots) the server and returns the base URL.
  Future<String> start(String rootDir) async {
    _root = rootDir;
    if (_server == null) {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      s.listen(_handle, onError: (_) {});
      _server = s;
    }
    return 'http://127.0.0.1:${_server!.port}/';
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  static const Map<String, String> mime = {
    'html': 'text/html; charset=utf-8', 'htm': 'text/html; charset=utf-8',
    'css': 'text/css; charset=utf-8', 'js': 'text/javascript; charset=utf-8', 'mjs': 'text/javascript; charset=utf-8',
    'json': 'application/json; charset=utf-8', 'map': 'application/json; charset=utf-8',
    'svg': 'image/svg+xml', 'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'gif': 'image/gif',
    'webp': 'image/webp', 'ico': 'image/x-icon', 'avif': 'image/avif',
    'woff': 'font/woff', 'woff2': 'font/woff2', 'ttf': 'font/ttf', 'otf': 'font/otf',
    'mp3': 'audio/mpeg', 'wav': 'audio/wav', 'ogg': 'audio/ogg', 'mp4': 'video/mp4', 'webm': 'video/webm',
    'txt': 'text/plain; charset=utf-8', 'md': 'text/plain; charset=utf-8', 'xml': 'application/xml; charset=utf-8',
    'wasm': 'application/wasm', 'pdf': 'application/pdf', 'csv': 'text/csv; charset=utf-8',
    'webmanifest': 'application/manifest+json',
  };

  /// Console bridge added to HTML pages (sent to the 'xcPreview' handler).
  static const String consoleBridge = r'''<script>(function(){
if(window.__xcp)return;window.__xcp=1;
function s(l,a){try{var t=Array.prototype.map.call(a,function(x){try{return typeof x==='object'&&x!==null?(x instanceof Error?(x.stack||x.message):JSON.stringify(x)):String(x)}catch(e){return String(x)}}).join(' ');
window.flutter_inappwebview&&window.flutter_inappwebview.callHandler('xcPreview',{level:l,text:t.slice(0,4000)})}catch(e){}}
['log','info','warn','error','debug'].forEach(function(l){var o=console[l];console[l]=function(){s(l,arguments);return o&&o.apply(console,arguments)}});
addEventListener('error',function(e){s('error',[(e.message||'Error')+(e.filename?' ('+e.filename.replace(location.origin+'/','')+':'+e.lineno+')':'')])},true);
addEventListener('unhandledrejection',function(e){s('error',['Uncaught (in promise) '+(e.reason&&e.reason.message||e.reason)])});
})();</script>''';

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final root = _root;
      if (root == null) {
        res.statusCode = HttpStatus.serviceUnavailable;
        await res.close();
        return;
      }
      var path = Uri.decodeComponent(req.uri.path);
      if (path.contains('..') || path.contains('\x00')) {
        res.statusCode = HttpStatus.forbidden;
        await res.close();
        return;
      }
      if (path.endsWith('/')) path = '${path}index.html';
      var file = File('$root$path');
      if (!await file.exists() && await Directory('$root$path').exists()) {
        file = File('$root$path/index.html');
      }
      res.headers
        ..set('Cache-Control', 'no-store')
        ..set('Access-Control-Allow-Origin', '*')
        ..set('X-Content-Type-Options', 'nosniff');
      if (!await file.exists()) {
        res.statusCode = HttpStatus.notFound;
        res.headers.contentType = ContentType.html;
        res.write('<!doctype html><meta name=viewport content="width=device-width"><body style="font-family:sans-serif;padding:24px;background:#0b1424;color:#e8f1ff">'
            '<h2>404 · Not found</h2><p><code>${_esc(path)}</code> isn’t in this project.</p>$consoleBridge');
        await res.close();
        return;
      }
      final name = file.path.split('/').last;
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
      if (ext == 'php') {
        res.headers.contentType = ContentType.html;
        res.write('<!doctype html><meta name=viewport content="width=device-width"><body style="font-family:sans-serif;padding:24px;background:#0b1424;color:#e8f1ff">'
            '<h2>PHP can’t run on the phone</h2><p>Upload <code>${_esc(name)}</code> to a PHP server to run it. '
            'You can still preview HTML, CSS and JavaScript here.</p>');
        await res.close();
        return;
      }
      final type = mime[ext] ?? 'application/octet-stream';
      res.headers.set(HttpHeaders.contentTypeHeader, type);
      if (ext == 'html' || ext == 'htm') {
        var html = await file.readAsString();
        final i = html.toLowerCase().indexOf('<head>');
        html = i >= 0 ? '${html.substring(0, i + 6)}$consoleBridge${html.substring(i + 6)}' : '$consoleBridge$html';
        res.write(html);
      } else {
        await res.addStream(file.openRead());
      }
      await res.close();
    } catch (_) {
      try {
        res.statusCode = HttpStatus.internalServerError;
        await res.close();
      } catch (_) {}
    }
  }

  static String _esc(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
}
