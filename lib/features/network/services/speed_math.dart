// lib/features/network/services/speed_math.dart
//
// NOVA Network — the numbers behind the speed test (pure Dart, unit-tested):
// latency statistics, throughput from timed byte counts, quality ratings,
// bufferbloat grade, the gauge scale and the text NOVA speaks.

import 'dart:math' as math;

/// Bytes received/sent so far at a moment of the test.
class ByteSample {
  const ByteSample(this.ms, this.bytes);

  /// Milliseconds since the phase started.
  final int ms;

  /// Total bytes so far.
  final int bytes;
}

/// One finished request: [bytes] moved between [startMs] and [endMs].
class Transfer {
  const Transfer(this.startMs, this.endMs, this.bytes, [this.stream = 0]);
  final int startMs;
  final int endMs;
  final int bytes;

  /// Which parallel connection sent it.
  final int stream;
}

class SpeedMath {
  SpeedMath._();

  // ── Latency ────────────────────────────────────────────────────────────────

  static double median(List<double> values) {
    if (values.isEmpty) return 0;
    final s = List<double>.of(values)..sort();
    final mid = s.length ~/ 2;
    return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
  }

  /// Average difference between consecutive latency samples (RFC 3550 style).
  static double jitter(List<double> values) {
    if (values.length < 2) return 0;
    var sum = 0.0;
    for (var i = 1; i < values.length; i++) {
      sum += (values[i] - values[i - 1]).abs();
    }
    return sum / (values.length - 1);
  }

  static double percentile(List<double> values, double p) {
    if (values.isEmpty) return 0;
    final s = List<double>.of(values)..sort();
    final rank = (p.clamp(0, 100) / 100) * (s.length - 1);
    final lo = rank.floor();
    final hi = rank.ceil();
    return s[lo] + (s[hi] - s[lo]) * (rank - lo);
  }

  // ── Throughput ─────────────────────────────────────────────────────────────

  static double mbps(int bytes, int ms) => ms <= 0 ? 0 : bytes * 8 / (ms / 1000) / 1e6;

  /// Speed over the last [windowMs] (the live gauge).
  static double liveMbps(List<ByteSample> samples, {int windowMs = 1000}) {
    if (samples.length < 2) return 0;
    final last = samples.last;
    var i = samples.length - 1;
    while (i > 0 && last.ms - samples[i - 1].ms <= windowMs) {
      i--;
    }
    if (i == samples.length - 1) i = samples.length - 2;
    final first = samples[i];
    return mbps(last.bytes - first.bytes, last.ms - first.ms);
  }

  /// The result: average speed after the connection has ramped up (the
  /// first 15 % of the time, at least 1.5 s, is not counted — TCP slow start
  /// would make every result too low).
  static double finalMbps(List<ByteSample> samples) {
    if (samples.length < 2) return 0;
    final end = samples.last;
    final warmup = math.max(1500, (end.ms * 0.15).round());
    if (end.ms < warmup * 1.5) {
      return mbps(end.bytes - samples.first.bytes, end.ms - samples.first.ms);
    }
    var start = samples.first;
    for (final s in samples) {
      if (s.ms >= warmup) {
        start = s;
        break;
      }
    }
    if (end.ms - start.ms <= 0) return mbps(end.bytes, end.ms);
    return mbps(end.bytes - start.bytes, end.ms - start.ms);
  }

  /// Fastest 1-second window of the phase.
  static double peakMbps(List<ByteSample> samples, {int windowMs = 1000}) {
    var peak = 0.0;
    var j = 0;
    for (var i = 0; i < samples.length; i++) {
      while (j < i && samples[i].ms - samples[j].ms > windowMs) {
        j++;
      }
      if (i > j && samples[i].ms - samples[j].ms >= windowMs * 0.6) {
        peak = math.max(peak, mbps(samples[i].bytes - samples[j].bytes, samples[i].ms - samples[j].ms));
      }
    }
    return peak;
  }

  /// Upload result from finished requests. Each request's bytes are spread
  /// evenly over the time it took. Every connection is measured from the end
  /// of the ramp-up until its own last finished request (so requests still
  /// on their way at the end don't lower the result), and the connections'
  /// speeds are added up.
  static double intervalMbps(List<Transfer> transfers) {
    if (transfers.isEmpty) return 0;
    final end = transfers.map((t) => t.endMs).reduce(math.max);
    final warmup = math.max(1500, (end * 0.15).round());
    final from = end < warmup * 1.5 ? 0 : warmup;
    final streams = <int, List<Transfer>>{};
    for (final t in transfers) {
      streams.putIfAbsent(t.stream, () => []).add(t);
    }
    var total = 0.0;
    for (final list in streams.values) {
      final streamEnd = list.map((t) => t.endMs).reduce(math.max);
      // A connection that finished nothing after the ramp-up: its whole time.
      final start = streamEnd > from ? from : list.map((t) => t.startMs).reduce(math.min);
      if (streamEnd - start <= 0) continue;
      var bytes = 0.0;
      for (final t in list) {
        final span = t.endMs - t.startMs;
        if (span <= 0) {
          if (t.endMs >= start) bytes += t.bytes;
          continue;
        }
        final overlap = math.min(t.endMs, streamEnd) - math.max(t.startMs, start);
        if (overlap > 0) bytes += t.bytes * overlap / span;
      }
      total += mbps(bytes.round(), streamEnd - start);
    }
    return total;
  }

  /// Finished requests as a byte count every [stepMs] (bytes spread over
  /// each request's time) — for the peak of the upload.
  static List<ByteSample> transfersToSamples(List<Transfer> transfers, {int stepMs = 100}) {
    if (transfers.isEmpty) return const [];
    final end = transfers.map((t) => t.endMs).reduce(math.max);
    final out = <ByteSample>[];
    for (var ms = 0; ms <= end + stepMs; ms += stepMs) {
      var bytes = 0.0;
      for (final t in transfers) {
        if (ms >= t.endMs) {
          bytes += t.bytes;
        } else if (ms > t.startMs) {
          bytes += t.bytes * (ms - t.startMs) / (t.endMs - t.startMs);
        }
      }
      out.add(ByteSample(ms, bytes.round()));
    }
    return out;
  }

  // ── Gauge ──────────────────────────────────────────────────────────────────

  static const List<double> ticks = [0, 5, 10, 50, 100, 250, 500, 750, 1000];
  static const List<double> fastTicks = [0, 10, 50, 100, 250, 500, 1000, 2500, 5000];

  static List<double> ticksFor(double maxSeen) => maxSeen > 1000 ? fastTicks : ticks;

  /// Position 0…1 on the gauge (equal space between the tick marks, like
  /// common speed test dials, so slow and fast speeds are both readable).
  static double gaugeFraction(double mbps, List<double> scale) {
    if (mbps <= 0) return 0;
    final segments = scale.length - 1;
    for (var i = 1; i < scale.length; i++) {
      if (mbps <= scale[i]) {
        final part = (mbps - scale[i - 1]) / (scale[i] - scale[i - 1]);
        return ((i - 1) + part) / segments;
      }
    }
    return 1;
  }

  // ── Ratings ────────────────────────────────────────────────────────────────

  /// 3 = great, 2 = good, 1 = fair, 0 = poor.
  static int streaming(double down, double latency) {
    if (down >= 25 && latency <= 150) return 3;
    if (down >= 8) return 2;
    if (down >= 3) return 1;
    return 0;
  }

  static String streamingLabel(int level) =>
      const ['Low quality', 'SD (480p)', 'Full HD (1080p)', '4K Ultra HD'][level.clamp(0, 3)];

  static int gaming(double latency, double jitter, double loaded, double down) {
    if (down < 3) return 0;
    if (latency <= 40 && jitter <= 10 && loaded <= 100) return 3;
    if (latency <= 70 && jitter <= 20 && loaded <= 200) return 2;
    if (latency <= 120 && jitter <= 40) return 1;
    return 0;
  }

  static int videoCalls(double down, double up, double latency, double jitter) {
    if (down >= 4 && up >= 3 && latency <= 100 && jitter <= 30) return 3;
    if (down >= 2 && up >= 1.5 && latency <= 150) return 2;
    if (down >= 1 && up >= 0.6) return 1;
    return 0;
  }

  static int browsing(double down, double latency) {
    if (down >= 15 && latency <= 100) return 3;
    if (down >= 5) return 2;
    if (down >= 1) return 1;
    return 0;
  }

  static String levelLabel(int level) => const ['Poor', 'Fair', 'Good', 'Great'][level.clamp(0, 3)];

  /// Bufferbloat: how much latency grows while the line is busy.
  static String bufferbloatGrade(double idle, double loadedDown, double loadedUp) {
    final loaded = math.max(loadedDown, loadedUp);
    if (idle <= 0 || loaded <= 0) return '—';
    final extra = loaded - idle;
    if (extra < 5) return 'A+';
    if (extra < 30) return 'A';
    if (extra < 60) return 'B';
    if (extra < 200) return 'C';
    if (extra < 400) return 'D';
    return 'F';
  }

  // ── Text ───────────────────────────────────────────────────────────────────

  /// "131.30" (the big number) — two decimals below 1000 Mbps.
  static String speedText(double mbps) {
    if (mbps <= 0) return '0.00';
    if (mbps >= 1000) return mbps.toStringAsFixed(0);
    return mbps.toStringAsFixed(2);
  }

  /// Short form for lists and speech: 7.4, 45, 131.
  static String shortSpeed(double mbps) {
    if (mbps <= 0) return '0';
    if (mbps < 10) return mbps.toStringAsFixed(1);
    return mbps.round().toString();
  }

  static String bytesText(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      final mb = bytes / (1024 * 1024);
      return '${mb < 10 ? mb.toStringAsFixed(1) : mb.toStringAsFixed(0)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// What NOVA says after a test (no Markdown; read aloud).
  static String spokenSummary({
    required double down,
    required double up,
    required double ping,
    required double jitter,
    double loaded = 0,
    String? isp,
  }) {
    final via = (isp == null || isp.trim().isEmpty) ? '' : ' on ${isp.trim()}';
    final stream = streaming(down, ping);
    final game = gaming(ping, jitter, loaded == 0 ? ping : loaded, down);
    final calls = videoCalls(down, up, ping, jitter);
    final good = <String>[
      if (stream == 3) '4K streaming' else if (stream == 2) 'HD streaming',
      if (game >= 2) 'online gaming',
      if (calls >= 2) 'video calls',
    ];
    final verdict = down < 1
        ? 'Your connection is very slow right now.'
        : good.isEmpty
            ? 'That is fine for browsing and messages, but streaming and calls may struggle.'
            : 'That is good for ${_joinWords(good)}.';
    return 'Your internet speed$via is ${shortSpeed(down)} megabits per second download and '
        '${shortSpeed(up)} upload, with a ping of ${ping.round()} milliseconds. $verdict';
  }

  static String _joinWords(List<String> items) {
    if (items.length == 1) return items.first;
    return '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
  }
}
