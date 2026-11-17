// lib/features/devhub/devhub_net.dart
//
// NOVA X Developer Hub — network tools (Android port of the Windows
// Developer Hub, 3.14.0). Everything goes straight from the phone to the
// site (no NOVA server in between), and only when the user taps Run.
//
//  • Request timeline: each hop is made by hand on a raw socket so every
//    phase is really measured — DNS lookup, TCP connect, TLS handshake,
//    waiting for the first byte, download — plus the certificate, the
//    redirect chain, and whether the server offers HTTP/2 (ALPN).
//  • DNS over HTTPS (two public resolvers, compared) and RDAP domain
//    registration data. (No local port scanning on Android.)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../cyber/engine/cyber_context.dart' show registrableDomain;

const String kDevHubUserAgent = 'NOVA-X-DevHub/1.0 (+https://nova-x.t-lyfe.com.ng)';

// ── Request timeline ────────────────────────────────────────────────────────

class CertInfo {
  const CertInfo({
    required this.subject,
    required this.issuer,
    required this.validFrom,
    required this.validTo,
    required this.sha1,
    required this.trusted,
  });
  final String subject;
  final String issuer;
  final DateTime validFrom;
  final DateTime validTo;
  final String sha1;

  /// the device's certificate store accepted it.
  final bool trusted;

  int daysLeft([DateTime? now]) => validTo.difference(now ?? DateTime.now()).inDays;
}

class Hop {
  Hop(this.url);
  final Uri url;
  String method = 'GET';
  String? ip;
  int? status;
  String reason = '';
  String httpVersion = '';

  /// Response headers in order (name as sent).
  final List<(String, String)> headers = [];
  Duration? dns, connect, tls, ttfb, download;
  int transferred = 0; // bytes on the wire (headers + body)
  Uint8List body = Uint8List(0); // decoded (de-chunked, decompressed)
  int bodyWire = 0; // body bytes before decompression
  bool truncated = false;
  CertInfo? cert;
  String? error;
  Uri? location;

  Duration get total =>
      [dns, connect, tls, ttfb, download].whereType<Duration>().fold(Duration.zero, (a, b) => a + b);

  /// All values of header [name] (case-insensitive).
  List<String> all(String name) {
    final n = name.toLowerCase();
    return [for (final h in headers) if (h.$1.toLowerCase() == n) h.$2];
  }

  String? header(String name) {
    final v = all(name);
    return v.isEmpty ? null : v.join(', ');
  }

  bool get isRedirect => status != null && const {301, 302, 303, 307, 308}.contains(status) && location != null;
}

class TimelineResult {
  final List<Hop> hops = [];

  /// The server offers HTTP/2 (null: not checked / plain HTTP).
  bool? http2;
  Hop? get last => hops.isEmpty ? null : hops.last;
}

class RequestTimeline {
  RequestTimeline._();

  static const int maxHops = 10;
  static const int maxBody = 8 * 1024 * 1024;
  static const Duration hopTimeout = Duration(seconds: 25);

  /// Runs [method] on [url], following redirects when [follow].
  static Future<TimelineResult> run(Uri url,
      {String method = 'GET', bool follow = true, Map<String, String> extraHeaders = const {}}) async {
    final r = TimelineResult();
    var u = url;
    var m = method;
    for (var i = 0; i < maxHops; i++) {
      final hop = Hop(u)..method = m;
      r.hops.add(hop);
      try {
        await _hop(hop, extraHeaders).timeout(hopTimeout);
      } on TimeoutException {
        hop.error = 'No complete answer within ${hopTimeout.inSeconds} seconds.';
      } catch (e) {
        hop.error ??= _friendly(e);
      }
      if (hop.error != null || !follow || !hop.isRedirect) break;
      // 303 (and 301/302 after POST, like browsers) continue as GET.
      if (hop.status == 303) m = 'GET';
      u = hop.location!;
    }
    // HTTP/2 support of the final https host.
    final last = r.last;
    if (last != null && last.url.scheme == 'https' && last.error == null) {
      r.http2 = await alpnH2(last.url.host, last.url.hasPort ? last.url.port : 443);
    }
    return r;
  }

  static String _friendly(Object e) {
    if (e is SocketException) {
      final msg = e.osError?.message ?? e.message;
      if (msg.toLowerCase().contains('host') || msg.toLowerCase().contains('lookup')) {
        return 'The address couldn\'t be found (DNS): $msg';
      }
      return 'Couldn\'t connect: $msg';
    }
    if (e is HandshakeException) return 'TLS handshake failed: ${e.osError?.message ?? e.message}';
    return '$e';
  }

  static Future<void> _hop(Hop hop, Map<String, String> extra) async {
    final u = hop.url;
    if (u.scheme != 'http' && u.scheme != 'https') {
      hop.error = 'Only http:// and https:// addresses can be timed.';
      return;
    }
    final secure = u.scheme == 'https';
    final port = u.hasPort ? u.port : (secure ? 443 : 80);
    final sw = Stopwatch()..start();

    // DNS
    final List<InternetAddress> addrs;
    final literal = InternetAddress.tryParse(u.host);
    if (literal != null) {
      addrs = [literal];
      hop.dns = Duration.zero;
    } else {
      addrs = await InternetAddress.lookup(u.host);
      hop.dns = sw.elapsed;
    }
    if (addrs.isEmpty) {
      hop.error = 'The address couldn\'t be found (DNS).';
      return;
    }
    // Prefer IPv4 (what most networks route best), like browsers' happy eyeballs fallback.
    final addr = addrs.firstWhere((a) => a.type == InternetAddressType.IPv4, orElse: () => addrs.first);
    hop.ip = addr.address;

    // TCP
    sw.reset();
    final raw = await Socket.connect(addr, port, timeout: const Duration(seconds: 10));
    hop.connect = sw.elapsed;

    Socket sock = raw;
    if (secure) {
      sw.reset();
      var trusted = true;
      X509Certificate? bad;
      final s = await SecureSocket.secure(raw, host: u.host, supportedProtocols: const ['http/1.1'], onBadCertificate: (c) {
        trusted = false;
        bad = c;
        return true; // still show the response; marked as untrusted
      });
      hop.tls = sw.elapsed;
      final c = s.peerCertificate ?? bad;
      if (c != null) {
        hop.cert = CertInfo(
          subject: c.subject,
          issuer: c.issuer,
          validFrom: c.startValidity,
          validTo: c.endValidity,
          sha1: c.sha1.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase(),
          trusted: trusted,
        );
      }
      sock = s;
    }

    // Request
    final path = (u.path.isEmpty ? '/' : u.path) + (u.hasQuery ? '?${u.query}' : '');
    final hostHeader = u.hasPort ? '${u.host}:${u.port}' : u.host;
    final req = StringBuffer()
      ..write('${hop.method} $path HTTP/1.1\r\n')
      ..write('Host: $hostHeader\r\n')
      ..write('User-Agent: $kDevHubUserAgent\r\n')
      ..write('Accept: */*\r\n')
      ..write('Accept-Encoding: gzip, deflate\r\n')
      ..write('Connection: close\r\n');
    extra.forEach((k, v) {
      if (k.trim().isEmpty || k.contains('\n') || v.contains('\n')) return;
      req.write('${k.trim()}: ${v.trim()}\r\n');
    });
    req.write('\r\n');

    sw.reset();
    sock.add(latin1.encode(req.toString()));
    await sock.flush();

    final buf = BytesBuilder(copy: false);
    final done = Completer<void>();
    var headerEnd = -1;
    Duration? first;
    int? contentLength;
    var chunked = false;
    var noBody = false;
    late final StreamSubscription<Uint8List> sub;

    void finish() {
      if (!done.isCompleted) done.complete();
    }

    sub = sock.listen((data) {
      first ??= sw.elapsed;
      buf.add(data);
      if (buf.length > maxBody) {
        hop.truncated = true;
        finish();
        return;
      }
      if (headerEnd < 0) {
        final bytes = buf.toBytes();
        headerEnd = _indexOf(bytes, const [13, 10, 13, 10]);
        if (headerEnd >= 0) {
          _parseHead(hop, latin1.decode(bytes.sublist(0, headerEnd), allowInvalid: true));
          contentLength = int.tryParse(hop.header('content-length') ?? '');
          chunked = (hop.header('transfer-encoding') ?? '').toLowerCase().contains('chunked');
          final st = hop.status ?? 0;
          noBody = hop.method == 'HEAD' || st == 204 || st == 304 || (st >= 100 && st < 200);
        }
      }
      if (headerEnd >= 0) {
        final bodyLen = buf.length - headerEnd - 4;
        if (noBody) return finish();
        if (contentLength != null && bodyLen >= contentLength!) return finish();
        if (chunked && _endsWithLastChunk(buf.toBytes())) return finish();
      }
    }, onError: (Object e) {
      hop.error ??= 'Connection error: $e';
      finish();
    }, onDone: finish, cancelOnError: true);

    await done.future;
    final elapsed = sw.elapsed;
    await sub.cancel();
    sock.destroy();

    hop.ttfb = first ?? elapsed;
    hop.download = first == null ? Duration.zero : elapsed - first!;
    final all = buf.toBytes();
    hop.transferred = all.length;
    if (headerEnd < 0) {
      hop.error ??= all.isEmpty ? 'The server closed the connection without answering.' : 'Incomplete HTTP response.';
      return;
    }
    var body = all.sublist(headerEnd + 4);
    if (chunked) body = dechunk(body);
    hop.bodyWire = body.length;
    final enc = (hop.header('content-encoding') ?? '').toLowerCase();
    try {
      if (enc.contains('gzip')) {
        body = Uint8List.fromList(gzip.decode(body));
      } else if (enc.contains('deflate')) {
        body = Uint8List.fromList(zlib.decode(body));
      }
    } catch (_) {
      // Truncated or not really compressed: keep the bytes as received.
    }
    hop.body = body;
    final loc = hop.header('location');
    if (loc != null && loc.isNotEmpty) hop.location = hop.url.resolve(loc.trim());
  }

  static void _parseHead(Hop hop, String head) {
    final lines = head.split('\r\n');
    final status = RegExp(r'^(HTTP/\d(?:\.\d)?)\s+(\d{3})\s*(.*)$').firstMatch(lines.first);
    if (status != null) {
      hop.httpVersion = status.group(1)!;
      hop.status = int.parse(status.group(2)!);
      hop.reason = status.group(3)!.trim();
    }
    for (final l in lines.skip(1)) {
      final i = l.indexOf(':');
      if (i <= 0) continue;
      hop.headers.add((l.substring(0, i).trim(), l.substring(i + 1).trim()));
    }
  }

  static int _indexOf(Uint8List hay, List<int> needle) {
    outer:
    for (var i = 0; i + needle.length <= hay.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (hay[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  static bool _endsWithLastChunk(Uint8List b) {
    // "...0\r\n\r\n" (no trailers), the usual end of a chunked body.
    if (b.length < 5) return false;
    final tail = latin1.decode(b.sublist(b.length - 7 < 0 ? 0 : b.length - 7));
    return tail.endsWith('\r\n0\r\n\r\n') || tail == '0\r\n\r\n';
  }

  /// Joins a chunked transfer-encoded body (RFC 9112 §7.1).
  static Uint8List dechunk(Uint8List b) {
    final out = BytesBuilder(copy: false);
    var i = 0;
    while (i < b.length) {
      var lineEnd = -1;
      for (var j = i; j + 1 < b.length; j++) {
        if (b[j] == 13 && b[j + 1] == 10) {
          lineEnd = j;
          break;
        }
      }
      if (lineEnd < 0) break;
      final sizeText = latin1.decode(b.sublist(i, lineEnd)).split(';').first.trim();
      final size = int.tryParse(sizeText, radix: 16);
      if (size == null) break;
      if (size == 0) break;
      final start = lineEnd + 2;
      final end = start + size;
      if (end > b.length) {
        out.add(b.sublist(start));
        break;
      }
      out.add(b.sublist(start, end));
      i = end + 2;
    }
    return out.toBytes();
  }

  /// Does the server offer HTTP/2? (ALPN in a separate TLS handshake.)
  static Future<bool?> alpnH2(String host, int port) async {
    try {
      final s = await SecureSocket.connect(host, port,
          supportedProtocols: const ['h2', 'http/1.1'], timeout: const Duration(seconds: 8), onBadCertificate: (_) => true);
      final p = s.selectedProtocol;
      s.destroy();
      return p == 'h2';
    } catch (_) {
      return null;
    }
  }

  /// The same request as a cURL command.
  static String curl(Uri url, {String method = 'GET', Map<String, String> headers = const {}}) {
    String q(String s) => "'${s.replaceAll("'", "'\\''")}'";
    final b = StringBuffer('curl');
    if (method == 'HEAD') {
      b.write(' -I');
    } else if (method != 'GET') {
      b.write(' -X $method');
    }
    headers.forEach((k, v) => b.write(' -H ${q('$k: $v')}'));
    b.write(' --compressed -sS -D - ${q(url.toString())}');
    return b.toString();
  }
}

// ── Header analysis ─────────────────────────────────────────────────────────

class HeaderCheck {
  const HeaderCheck(this.name, this.ok, this.detail);
  final String name;
  final bool ok;
  final String detail;
}

class HeaderAnalysis {
  HeaderAnalysis._();

  static List<HeaderCheck> security(Hop h) {
    final https = h.url.scheme == 'https';
    final hsts = h.header('strict-transport-security');
    final csp = h.header('content-security-policy');
    final xfo = h.header('x-frame-options');
    final xcto = h.header('x-content-type-options');
    final rp = h.header('referrer-policy');
    final pp = h.header('permissions-policy');
    final frameOk = xfo != null || (csp ?? '').contains('frame-ancestors');
    return [
      HeaderCheck('HTTPS', https, https ? 'Encrypted connection' : 'Plain HTTP: anyone on the network can read or change it'),
      HeaderCheck('Strict-Transport-Security', hsts != null,
          hsts ?? (https ? 'Missing: browsers may still try http:// first' : 'Only meaningful over HTTPS')),
      HeaderCheck('Content-Security-Policy', csp != null, csp == null ? 'Missing: no second line of defence against XSS' : _short(csp)),
      HeaderCheck('Clickjacking protection', frameOk,
          xfo != null ? 'X-Frame-Options: $xfo' : (frameOk ? 'CSP frame-ancestors' : 'Missing: the page can be framed by other sites')),
      HeaderCheck('X-Content-Type-Options', (xcto ?? '').toLowerCase() == 'nosniff', xcto ?? 'Missing: browsers may guess file types'),
      HeaderCheck('Referrer-Policy', rp != null, rp ?? 'Missing: the browser default applies'),
      HeaderCheck('Permissions-Policy', pp != null, pp == null ? 'Missing: optional, limits camera / mic / location use' : _short(pp)),
    ];
  }

  static String _short(String s) => s.length > 140 ? '${s.substring(0, 140)}…' : s;

  /// What the caching headers mean, in plain words.
  static List<String> caching(Hop h) {
    final out = <String>[];
    final cc = (h.header('cache-control') ?? '').toLowerCase();
    if (cc.isEmpty) {
      out.add('No Cache-Control: browsers and CDNs decide how long to keep it (heuristic caching).');
    } else {
      if (cc.contains('no-store')) out.add('no-store: never stored, fetched again every time.');
      if (cc.contains('no-cache')) out.add('no-cache: stored, but checked with the server before each use.');
      if (cc.contains('private')) out.add('private: only the browser may keep it, not shared caches/CDNs.');
      if (cc.contains('public')) out.add('public: shared caches (CDNs, proxies) may keep it.');
      final ma = RegExp(r'(?:^|,)\s*max-age=(\d+)').firstMatch(cc);
      if (ma != null) out.add('max-age: fresh for ${_dur(int.parse(ma.group(1)!))} in the browser.');
      final sm = RegExp(r's-maxage=(\d+)').firstMatch(cc);
      if (sm != null) out.add('s-maxage: fresh for ${_dur(int.parse(sm.group(1)!))} in shared caches.');
      if (cc.contains('immutable')) out.add('immutable: never revalidated while fresh (ideal for hashed assets).');
      final swr = RegExp(r'stale-while-revalidate=(\d+)').firstMatch(cc);
      if (swr != null) out.add('stale-while-revalidate: may be served stale for ${_dur(int.parse(swr.group(1)!))} while refreshing.');
    }
    final etag = h.header('etag');
    final lm = h.header('last-modified');
    if (etag != null) out.add('ETag $etag: revalidation can answer 304 Not Modified.');
    if (lm != null) out.add('Last-Modified $lm.');
    final age = h.header('age');
    if (age != null) out.add('Age ${age}s: served from a shared cache (CDN).');
    for (final k in ['cf-cache-status', 'x-cache', 'x-vercel-cache', 'x-nf-request-id', 'x-served-by']) {
      final v = h.header(k);
      if (v != null) out.add('$k: $v');
    }
    return out;
  }

  static String _dur(int s) {
    if (s < 120) return '$s s';
    if (s < 7200) return '${(s / 60).round()} min';
    if (s < 172800) return '${(s / 3600).round()} h';
    return '${(s / 86400).round()} days';
  }

  static List<String> cors(Hop h) => [
        for (final k in [
          'access-control-allow-origin',
          'access-control-allow-credentials',
          'access-control-allow-methods',
          'access-control-allow-headers',
          'access-control-expose-headers',
          'access-control-max-age',
          'vary',
        ])
          if (h.header(k) != null) '$k: ${h.header(k)}',
      ];

  /// Set-Cookie lines with their missing protections.
  static List<(String, List<String>)> cookies(Hop h) {
    final out = <(String, List<String>)>[];
    for (final c in h.all('set-cookie')) {
      final name = c.split('=').first.trim();
      final lower = c.toLowerCase();
      final miss = <String>[
        if (!lower.contains('; secure') && h.url.scheme == 'https') 'Secure',
        if (!lower.contains('httponly')) 'HttpOnly',
        if (!lower.contains('samesite')) 'SameSite',
      ];
      out.add((name, miss));
    }
    return out;
  }
}

// ── DNS over HTTPS ──────────────────────────────────────────────────────────

class DnsRecord {
  const DnsRecord(this.name, this.type, this.ttl, this.data);
  final String name;
  final String type;
  final int ttl;
  final String data;
}

class DnsAnswer {
  DnsAnswer(this.resolver);
  final String resolver;
  final Map<String, List<DnsRecord>> byType = {};
  final Map<String, String> errors = {};
  bool nxdomain = false;
}

class DevDns {
  DevDns._();

  static const List<String> types = ['A', 'AAAA', 'CNAME', 'MX', 'NS', 'TXT', 'CAA', 'SOA'];
  static const Map<int, String> _typeNames = {
    1: 'A', 2: 'NS', 5: 'CNAME', 6: 'SOA', 15: 'MX', 16: 'TXT', 28: 'AAAA', 257: 'CAA', 65: 'HTTPS', 46: 'RRSIG',
  };

  static Future<DnsAnswer> lookup(String name, {bool google = false}) async {
    final a = DnsAnswer(google ? 'Resolver B' : 'Resolver A'); // providers aren't named in the UI
    await Future.wait(types.map((t) async {
      try {
        final uri = google
            ? Uri.https('dns.google', '/resolve', {'name': name, 'type': t})
            : Uri.https('cloudflare-dns.com', '/dns-query', {'name': name, 'type': t});
        final j = await getJson(uri, headers: {'accept': 'application/dns-json'});
        if (j is! Map) throw const FormatException('bad answer');
        if (j['Status'] == 3) a.nxdomain = true;
        final list = <DnsRecord>[];
        for (final r in (j['Answer'] as List? ?? const [])) {
          if (r is! Map) continue;
          final type = _typeNames[r['type']] ?? '${r['type']}';
          // Only records of the asked type (CNAME chains also appear under A).
          if (type != t && !(t != 'CNAME' && type == 'CNAME')) continue;
          list.add(DnsRecord('${r['name']}', type, (r['TTL'] as num?)?.toInt() ?? 0, '${r['data']}'));
        }
        a.byType[t] = list;
      } catch (e) {
        a.errors[t] = 'Lookup failed';
      }
    }));
    return a;
  }

  /// Record types whose answers differ between the two resolvers (ignores TTLs and order).
  static List<String> differences(DnsAnswer x, DnsAnswer y) {
    final out = <String>[];
    for (final t in types) {
      Set<String> s(DnsAnswer a) => {for (final r in a.byType[t] ?? const <DnsRecord>[]) if (r.type == t) r.data.toLowerCase()};
      if (s(x).difference(s(y)).isNotEmpty || s(y).difference(s(x)).isNotEmpty) out.add(t);
    }
    return out;
  }
}

// ── RDAP (domain registration) ──────────────────────────────────────────────

class DomainInfo {
  String domain = '';
  String? registrar;
  DateTime? created, expires, updated;
  final List<String> nameservers = [];
  final List<String> status = [];
  bool? dnssec;

  int? daysLeft([DateTime? now]) => expires?.difference(now ?? DateTime.now()).inDays;
}

class DevRdap {
  DevRdap._();

  static Future<DomainInfo?> lookup(String host) async {
    final domain = registrableDomain(host.toLowerCase());
    final j = await getJson(Uri.https('rdap.org', '/domain/$domain'), headers: {'accept': 'application/rdap+json'});
    if (j is! Map) return null;
    final info = DomainInfo()..domain = '${j['ldhName'] ?? domain}'.toLowerCase();
    for (final e in (j['events'] as List? ?? const [])) {
      if (e is! Map) continue;
      final d = DateTime.tryParse('${e['eventDate']}');
      switch ('${e['eventAction']}') {
        case 'registration':
          info.created = d;
        case 'expiration':
          info.expires = d;
        case 'last changed':
          info.updated = d;
      }
    }
    for (final ent in (j['entities'] as List? ?? const [])) {
      if (ent is! Map || !((ent['roles'] as List?) ?? const []).contains('registrar')) continue;
      info.registrar = _vcardName(ent['vcardArray']) ?? '${ent['handle'] ?? ''}';
    }
    for (final ns in (j['nameservers'] as List? ?? const [])) {
      if (ns is Map && ns['ldhName'] != null) info.nameservers.add('${ns['ldhName']}'.toLowerCase());
    }
    for (final s in (j['status'] as List? ?? const [])) {
      info.status.add('$s');
    }
    final sd = j['secureDNS'];
    if (sd is Map && sd['delegationSigned'] is bool) info.dnssec = sd['delegationSigned'] as bool;
    return info;
  }

  static String? _vcardName(Object? v) {
    if (v is! List || v.length < 2 || v[1] is! List) return null;
    for (final f in v[1] as List) {
      if (f is List && f.length >= 4 && f[0] == 'fn') return '${f[3]}';
    }
    return null;
  }
}

// ── Shared ──────────────────────────────────────────────────────────────────

/// GET [uri] and decode JSON (follows redirects; 12 s).
Future<Object?> getJson(Uri uri, {Map<String, String> headers = const {}}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.getUrl(uri).timeout(const Duration(seconds: 10));
    req.headers.set(HttpHeaders.userAgentHeader, kDevHubUserAgent);
    headers.forEach(req.headers.set);
    final res = await req.close().timeout(const Duration(seconds: 12));
    final text = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 12));
    if (res.statusCode == 404) return null;
    if (res.statusCode >= 400) throw HttpException('HTTP ${res.statusCode}');
    return jsonDecode(text);
  } finally {
    client.close(force: true);
  }
}
