// lib/features/network/services/speed_test_engine.dart
//
// NOVA Network speed test — real measurements against the NOVA speed server
// (Cloudflare Worker backend/nova-speed-worker, on the Cloudflare location
// nearest to the user):
//
//   1. Latency  — 1 warm-up + N tiny requests on a kept-alive connection;
//                 ping = median, jitter = mean change between samples.
//   2. Download — several parallel connections stream random data for a
//                 fixed time; bytes are counted as they arrive. The ramp-up
//                 (TCP slow start) is left out of the result. A second
//                 connection keeps measuring latency (loaded latency).
//   3. Upload   — parallel connections send random data; only bytes the
//                 server confirmed are counted. Request sizes grow with the
//                 connection speed.
//
// Works in both Flutter engines (NOVA X and the floating NOVA assistant).
// A data cap stops a phase early (Light mode / mobile data).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/network_models.dart';
import 'speed_math.dart';

/// Where the speed test server runs. Change at build time with
///   --dart-define=NOVA_SPEED_BASE=https://your-worker.example
class NetworkConfig {
  NetworkConfig._();

  static const String speedBaseUrl = String.fromEnvironment(
    'NOVA_SPEED_BASE',
    defaultValue: 'https://nova-speed.techlyfeteam.workers.dev',
  );
}

enum SpeedPhase { idle, connecting, latency, download, upload, done, error }

class SpeedTestOptions {
  const SpeedTestOptions({
    required this.mode,
    required this.downloadTime,
    required this.uploadTime,
    required this.streams,
    required this.pingCount,
    this.downloadCapBytes,
    this.uploadCapBytes,
  });

  /// Up to 10 s per direction, 4 connections, no data cap (≈ speed × 20 s).
  static const full = SpeedTestOptions(
    mode: 'full',
    downloadTime: Duration(seconds: 10),
    uploadTime: Duration(seconds: 10),
    streams: 4,
    pingCount: 20,
    downloadCapBytes: 1500 * 1024 * 1024,
    uploadCapBytes: 600 * 1024 * 1024,
  );

  /// Data saver: at most ≈ 50 MB in all.
  static const light = SpeedTestOptions(
    mode: 'light',
    downloadTime: Duration(seconds: 7),
    uploadTime: Duration(seconds: 6),
    streams: 3,
    pingCount: 12,
    downloadCapBytes: 35 * 1024 * 1024,
    uploadCapBytes: 15 * 1024 * 1024,
  );

  /// "Hey NOVA, what's my internet speed?" — shorter, capped.
  static const quick = SpeedTestOptions(
    mode: 'quick',
    downloadTime: Duration(seconds: 7),
    uploadTime: Duration(seconds: 6),
    streams: 4,
    pingCount: 10,
    downloadCapBytes: 120 * 1024 * 1024,
    uploadCapBytes: 40 * 1024 * 1024,
  );

  final String mode;
  final Duration downloadTime;
  final Duration uploadTime;
  final int streams;
  final int pingCount;
  final int? downloadCapBytes;
  final int? uploadCapBytes;
}

/// Live state for the gauge and charts (sent about 10 times a second).
class SpeedProgress {
  const SpeedProgress({
    required this.phase,
    this.liveMbps = 0,
    this.progress = 0,
    this.pingMs,
    this.jitterMs,
    this.downloadMbps,
    this.uploadMbps,
    this.loadedMs,
    this.downChart = const [],
    this.upChart = const [],
    this.bytesUsed = 0,
  });

  final SpeedPhase phase;
  final double liveMbps;

  /// Whole test, 0…1.
  final double progress;
  final double? pingMs;
  final double? jitterMs;
  final double? downloadMbps;
  final double? uploadMbps;

  /// Latency while the line is busy (current phase).
  final double? loadedMs;
  final List<double> downChart;
  final List<double> upChart;
  final int bytesUsed;
}

class SpeedTestException implements Exception {
  const SpeedTestException(this.message);
  final String message;

  @override
  String toString() => message;
}

class SpeedTestEngine {
  SpeedTestEngine({String? baseUrl}) : _base = Uri.parse(baseUrl ?? NetworkConfig.speedBaseUrl);

  final Uri _base;
  final math.Random _random = math.Random();
  final Set<HttpClient> _clients = {};
  bool _cancelled = false;
  bool _running = false;

  bool get isRunning => _running;

  static final Uint8List _block = _randomBlock();

  static Uint8List _randomBlock() {
    final r = math.Random.secure();
    return Uint8List.fromList(List<int>.generate(64 * 1024, (_) => r.nextInt(256)));
  }

  Uri _uri(String path, [Map<String, String> query = const {}]) => _base.replace(
        path: '${_base.path.replaceAll(RegExp(r'/+$'), '')}$path',
        queryParameters: {...query, 'r': '${DateTime.now().microsecondsSinceEpoch}${_random.nextInt(1 << 20)}'},
      );

  HttpClient _newClient() {
    final c = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 20)
      ..autoUncompress = false
      ..userAgent = 'NOVA-X-Network/1.0';
    _clients.add(c);
    return c;
  }

  void _closeClient(HttpClient c) {
    _clients.remove(c);
    try {
      c.close(force: true);
    } catch (_) {}
  }

  /// Stops a running test (the result future completes with an error).
  void cancel() {
    _cancelled = true;
    for (final c in List<HttpClient>.of(_clients)) {
      _closeClient(c);
    }
  }

  void _checkCancelled() {
    if (_cancelled) throw const SpeedTestException('Speed test stopped.');
  }

  // ── Server info ──────────────────────────────────────────────────────────

  Future<NetworkMeta> fetchMeta({Duration timeout = const Duration(seconds: 8)}) async {
    final client = _newClient();
    try {
      final req = await client.getUrl(_uri('/meta')).timeout(timeout);
      final res = await req.close().timeout(timeout);
      final body = await res.transform(utf8.decoder).join().timeout(timeout);
      if (res.statusCode == 404) {
        throw const SpeedTestException("The NOVA Network speed test server isn't set up yet.");
      }
      if (res.statusCode != 200) throw SpeedTestException('Speed test server error (${res.statusCode}).');
      final data = jsonDecode(body);
      if (data is! Map) throw const SpeedTestException('Speed test server sent an unexpected reply.');
      return NetworkMeta.fromJson(Map<String, dynamic>.from(data));
    } on SpeedTestException {
      rethrow;
    } on TimeoutException {
      throw const SpeedTestException('The speed test server is not answering. Check your connection.');
    } on SocketException {
      throw const SpeedTestException("Can't reach the internet. Check Wi-Fi or mobile data.");
    } on HandshakeException {
      throw const SpeedTestException('A secure connection could not be made (check the date/time or Wi-Fi login page).');
    } on HttpException {
      throw const SpeedTestException("Can't reach the speed test server.");
    } finally {
      _closeClient(client);
    }
  }

  // ── Latency ──────────────────────────────────────────────────────────────

  Future<double> _pingOnce(HttpClient client) async {
    final sw = Stopwatch()..start();
    final req = await client.getUrl(_uri('/ping')).timeout(const Duration(seconds: 5));
    req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    final res = await req.close().timeout(const Duration(seconds: 5));
    await res.drain<void>();
    sw.stop();
    if (res.statusCode >= 400) throw SpeedTestException('Speed test server error (${res.statusCode}).');
    return sw.elapsedMicroseconds / 1000;
  }

  /// Ping samples (ms). The first request opens the connection and is not counted.
  Future<List<double>> measureLatency(int count, {void Function(List<double>)? onSample}) async {
    final client = _newClient();
    final samples = <double>[];
    try {
      await _pingOnce(client);
      for (var i = 0; i < count; i++) {
        _checkCancelled();
        try {
          samples.add(await _pingOnce(client));
          onSample?.call(samples);
        } on TimeoutException {
          // a lost request: skip it
        }
      }
    } on SocketException {
      throw const SpeedTestException("Can't reach the internet. Check Wi-Fi or mobile data.");
    } on TimeoutException {
      throw const SpeedTestException('The speed test server is not answering. Check your connection.');
    } on HttpException {
      _checkCancelled();
      throw const SpeedTestException("Can't reach the speed test server.");
    } finally {
      _closeClient(client);
    }
    if (samples.isEmpty) throw const SpeedTestException('The speed test server is not answering.');
    return samples;
  }

  /// Latency measured every 400 ms while [running] (loaded latency).
  Future<List<double>> _loadedLatency(bool Function() running) async {
    final client = _newClient();
    final out = <double>[];
    try {
      while (running() && !_cancelled) {
        try {
          out.add(await _pingOnce(client));
        } catch (_) {
          // busy line: a ping may fail; keep going
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    } finally {
      _closeClient(client);
    }
    return out;
  }

  // ── Download ─────────────────────────────────────────────────────────────

  Future<_PhaseResult> _download(SpeedTestOptions o, _Tick tick) async {
    final client = _newClient();
    final sw = Stopwatch()..start();
    final samples = <ByteSample>[const ByteSample(0, 0)];
    var total = 0;
    var stop = false;
    Object? firstError;
    final done = Completer<void>();
    final chunk = o.mode == 'light' ? 8 * 1024 * 1024 : 25 * 1024 * 1024;

    Future<void> worker() async {
      while (!stop && !_cancelled) {
        try {
          final req = await client.getUrl(_uri('/down', {'bytes': '$chunk'}));
          req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
          req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
          final res = await req.close();
          if (res.statusCode != 200) {
            await res.drain<void>();
            throw SpeedTestException(res.statusCode == 404
                ? "The NOVA Network speed test server isn't set up yet."
                : 'Speed test server error (${res.statusCode}).');
          }
          await for (final data in res) {
            total += data.length;
            if (stop || _cancelled) break;
          }
        } catch (e) {
          if (stop || _cancelled) return;
          firstError ??= e;
          if (total == 0) return; // can't connect at all
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
    }

    double? loaded;
    final pings = <double>[];
    final latencyLoop = _loadedLatency(() => !stop).then((v) => pings.addAll(v));
    final timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      samples.add(ByteSample(sw.elapsedMilliseconds, total));
      if (pings.isNotEmpty) loaded = SpeedMath.median(pings);
      tick(sw.elapsedMilliseconds, total, SpeedMath.liveMbps(samples), loaded);
      final cap = o.downloadCapBytes;
      if (sw.elapsed >= o.downloadTime || (cap != null && total >= cap) || _cancelled) {
        stop = true;
        if (!done.isCompleted) done.complete();
      }
    });
    final workers = Future.wait([for (var i = 0; i < o.streams; i++) worker()]);
    await Future.any([done.future, workers.then((_) {})]);
    stop = true;
    timer.cancel();
    _closeClient(client); // ends downloads still in flight
    await workers.timeout(const Duration(seconds: 3), onTimeout: () => const []);
    await latencyLoop.timeout(const Duration(seconds: 6), onTimeout: () {});
    _checkCancelled();
    samples.add(ByteSample(sw.elapsedMilliseconds, total));
    if (total == 0) throw _asException(firstError);
    return _PhaseResult(samples, pings, total);
  }

  // ── Upload ───────────────────────────────────────────────────────────────

  Future<_PhaseResult> _upload(SpeedTestOptions o, _Tick tick) async {
    final client = _newClient();
    final sw = Stopwatch()..start();
    final samples = <ByteSample>[const ByteSample(0, 0)];
    final transfers = <Transfer>[];
    var confirmed = 0; // bytes the server has acknowledged
    var sent = 0; // bytes handed to the network (live gauge and data cap)
    var stop = false;
    Object? firstError;
    final done = Completer<void>();
    const maxSize = 16 * 1024 * 1024;

    Future<void> worker(int stream) async {
      var size = 64 * 1024;
      while (!stop && !_cancelled) {
        final started = sw.elapsedMilliseconds;
        try {
          final req = await client.postUrl(_uri('/up'));
          req.headers.contentType = ContentType.binary;
          req.contentLength = size;
          var written = 0;
          while (written < size) {
            if (stop || _cancelled) {
              req.abort();
              return;
            }
            final n = math.min(_block.length, size - written);
            req.add(n == _block.length ? _block : Uint8List.sublistView(_block, 0, n));
            written += n;
            sent += n;
            if (written % (1024 * 1024) == 0 || written == size) await req.flush();
          }
          final res = await req.close();
          await res.drain<void>();
          if (res.statusCode == 404) {
            throw const SpeedTestException("The NOVA Network speed test server isn't set up yet.");
          }
          if (res.statusCode != 200) throw SpeedTestException('Speed test server error (${res.statusCode}).');
          if (stop || _cancelled) return;
          confirmed += size;
          transfers.add(Transfer(started, sw.elapsedMilliseconds, size, stream));
          // Bigger requests on fast connections (fewer round trips), but
          // short enough (< ~1 s) to keep the result precise.
          if (sw.elapsedMilliseconds - started < 500) size = math.min(size * 2, maxSize);
        } catch (e) {
          if (stop || _cancelled) return;
          firstError ??= e;
          if (confirmed == 0 && sw.elapsedMilliseconds > 8000) return;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
    }

    double? loaded;
    final pings = <double>[];
    final latencyLoop = _loadedLatency(() => !stop).then((v) => pings.addAll(v));
    final timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      samples.add(ByteSample(sw.elapsedMilliseconds, sent));
      if (pings.isNotEmpty) loaded = SpeedMath.median(pings);
      // Live speed from data the server confirmed (not the phone's send buffer).
      final confirmedSamples = SpeedMath.transfersToSamples(transfers);
      tick(sw.elapsedMilliseconds, sent, confirmedSamples.isEmpty ? 0 : SpeedMath.liveMbps(confirmedSamples), loaded);
      final cap = o.uploadCapBytes;
      if (sw.elapsed >= o.uploadTime || (cap != null && sent >= cap) || _cancelled) {
        stop = true;
        if (!done.isCompleted) done.complete();
      }
    });
    final workers = Future.wait([for (var i = 0; i < o.streams; i++) worker(i)]);
    await Future.any([done.future, workers.then((_) {})]);
    stop = true;
    timer.cancel();
    _closeClient(client);
    await workers.timeout(const Duration(seconds: 3), onTimeout: () => const []);
    await latencyLoop.timeout(const Duration(seconds: 6), onTimeout: () {});
    _checkCancelled();
    // Nothing confirmed: a server/connection error, unless the line is just
    // too slow for one request to finish in time.
    if (confirmed == 0 && (sent == 0 || firstError != null)) throw _asException(firstError);
    return _PhaseResult(samples, pings, sent, transfers);
  }

  SpeedTestException _asException(Object? e) {
    if (e is SpeedTestException) return e;
    if (e is SocketException || e is HttpException) {
      return const SpeedTestException("Can't reach the speed test server. Check your connection.");
    }
    if (e is HandshakeException) {
      return const SpeedTestException('A secure connection could not be made.');
    }
    return const SpeedTestException('The speed test could not finish. Please try again.');
  }

  // ── Full test ────────────────────────────────────────────────────────────

  /// Runs latency → download → upload. [onProgress] gets live updates.
  Future<SpeedTestResult> run(
    SpeedTestOptions o, {
    void Function(SpeedProgress)? onProgress,
    NetworkMeta? meta,
    String connection = '',
  }) async {
    if (_running) throw const SpeedTestException('A speed test is already running.');
    _running = true;
    _cancelled = false;
    try {
      onProgress?.call(const SpeedProgress(phase: SpeedPhase.connecting, progress: 0.01));
      final info = meta ?? await fetchMeta();
      _checkCancelled();

      // 1. Latency
      final pings = await measureLatency(o.pingCount, onSample: (s) {
        onProgress?.call(SpeedProgress(
          phase: SpeedPhase.latency,
          progress: 0.02 + 0.08 * (s.length / o.pingCount),
          pingMs: SpeedMath.median(s),
          jitterMs: SpeedMath.jitter(s),
        ));
      });
      final ping = SpeedMath.median(pings);
      final jitter = SpeedMath.jitter(pings);

      // 2. Download
      final downChart = <double>[];
      final down = await _download(o, (ms, bytes, live, loaded) {
        downChart.add(live);
        final t = ms / o.downloadTime.inMilliseconds;
        onProgress?.call(SpeedProgress(
          phase: SpeedPhase.download,
          liveMbps: live,
          progress: 0.10 + 0.45 * t.clamp(0, 1),
          pingMs: ping,
          jitterMs: jitter,
          loadedMs: loaded,
          downChart: List.unmodifiable(downChart),
          bytesUsed: bytes,
        ));
      });
      final downMbps = SpeedMath.finalMbps(down.samples);

      // 3. Upload
      final upChart = <double>[];
      final up = await _upload(o, (ms, bytes, live, loaded) {
        upChart.add(live);
        final t = ms / o.uploadTime.inMilliseconds;
        onProgress?.call(SpeedProgress(
          phase: SpeedPhase.upload,
          liveMbps: live,
          progress: 0.55 + 0.45 * t.clamp(0, 1),
          pingMs: ping,
          jitterMs: jitter,
          downloadMbps: downMbps,
          loadedMs: loaded,
          downChart: List.unmodifiable(downChart),
          upChart: List.unmodifiable(upChart),
          bytesUsed: down.bytes + bytes,
        ));
      });
      // Only data the server confirmed counts (bytes still in the phone's
      // network buffer would make the result too high).
      final upMbps = up.transfers.isEmpty
          ? SpeedMath.finalMbps(up.samples) // extremely slow line: nothing finished in time
          : SpeedMath.intervalMbps(up.transfers);

      final result = SpeedTestResult(
        time: DateTime.now(),
        downloadMbps: downMbps,
        uploadMbps: upMbps,
        pingMs: ping,
        jitterMs: jitter,
        loadedDownMs: down.pings.isEmpty ? 0 : SpeedMath.median(down.pings),
        loadedUpMs: up.pings.isEmpty ? 0 : SpeedMath.median(up.pings),
        peakDownMbps: SpeedMath.peakMbps(down.samples),
        peakUpMbps: SpeedMath.peakMbps(SpeedMath.transfersToSamples(up.transfers)),
        bytesUsed: down.bytes + up.bytes,
        connections: o.streams,
        connection: connection,
        isp: info.isp,
        ip: info.ip.isEmpty ? null : info.ip,
        server: info.serverName,
        mode: o.mode,
      );
      onProgress?.call(SpeedProgress(
        phase: SpeedPhase.done,
        progress: 1,
        pingMs: ping,
        jitterMs: jitter,
        downloadMbps: downMbps,
        uploadMbps: upMbps,
        downChart: List.unmodifiable(downChart),
        upChart: List.unmodifiable(upChart),
        bytesUsed: result.bytesUsed,
      ));
      return result;
    } finally {
      _running = false;
      for (final c in List<HttpClient>.of(_clients)) {
        _closeClient(c);
      }
    }
  }
}

/// Live update from a phase: elapsed ms, bytes so far, live Mbps, loaded latency.
typedef _Tick = void Function(int ms, int bytes, double live, double? loaded);

class _PhaseResult {
  const _PhaseResult(this.samples, this.pings, this.bytes, [this.transfers = const []]);
  final List<ByteSample> samples;
  final List<double> pings;
  final int bytes;

  /// Upload: finished requests (for the result).
  final List<Transfer> transfers;
}
