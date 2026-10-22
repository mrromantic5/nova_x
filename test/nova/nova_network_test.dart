// test/nova/nova_network_test.dart
//
// NOVA Network: speed maths, quality ratings, NOVA's connection questions,
// saved results and device details.

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/network/models/network_models.dart';
import 'package:nova_x/features/network/services/network_intents.dart';
import 'package:nova_x/features/network/services/network_services.dart';
import 'package:nova_x/features/network/services/speed_math.dart';

List<ByteSample> _link(double mbps, {int seconds = 10, int slowStartMs = 2000}) {
  final out = <ByteSample>[];
  var bytes = 0.0;
  for (var ms = 0; ms <= seconds * 1000; ms += 100) {
    final rate = ms < slowStartMs ? mbps * 1e6 * ms / slowStartMs : mbps * 1e6;
    if (ms > 0) bytes += rate / 8 * 0.1;
    out.add(ByteSample(ms, bytes.round()));
  }
  return out;
}

void main() {
  group('SpeedMath', () {
    test('latency statistics', () {
      expect(SpeedMath.median([5, 1, 3]), 3);
      expect(SpeedMath.median([4, 1, 3, 2]), 2.5);
      expect(SpeedMath.median([]), 0);
      expect(SpeedMath.jitter([10, 12, 11, 15]), closeTo(7 / 3, 1e-9));
      expect(SpeedMath.percentile([1, 2, 3, 4, 5], 50), 3);
    });

    test('result leaves out the slow start', () {
      final s = _link(100);
      expect(SpeedMath.finalMbps(s), closeTo(100, 2));
      expect(SpeedMath.mbps(s.last.bytes, s.last.ms), lessThan(91));
      expect(SpeedMath.liveMbps(s), closeTo(100, 2));
      expect(SpeedMath.peakMbps(s), closeTo(100, 2));
    });

    test('upload: confirmed requests per connection add up to the line speed', () {
      // 4 connections share 25 Mbps; each sends 1-second requests, started at different times.
      final transfers = <Transfer>[];
      for (var stream = 0; stream < 4; stream++) {
        for (var start = stream * 250; start + 1000 <= 6000; start += 1000) {
          transfers.add(Transfer(start, start + 1000, (25e6 / 4 / 8).round(), stream));
        }
      }
      expect(SpeedMath.intervalMbps(transfers), closeTo(25, 0.5));
      // A very slow line: one request per connection, longer than the ramp-up.
      final slow = [for (var i = 0; i < 4; i++) Transfer(200, 4200, 64 * 1024, i)];
      expect(SpeedMath.intervalMbps(slow), closeTo(4 * 64 * 1024 * 8 / 4 / 1e6, 0.01));
      expect(SpeedMath.intervalMbps(const []), 0);
      expect(SpeedMath.peakMbps(SpeedMath.transfersToSamples(transfers)), closeTo(25, 1.5));
    });

    test('a short phase (data cap) uses the plain average', () {
      expect(SpeedMath.finalMbps(const [ByteSample(0, 0), ByteSample(1000, 12500000)]), 100);
      expect(SpeedMath.finalMbps(const [ByteSample(0, 0)]), 0);
    });

    test('gauge scale', () {
      expect(SpeedMath.gaugeFraction(0, SpeedMath.ticks), 0);
      expect(SpeedMath.gaugeFraction(100, SpeedMath.ticks), 0.5);
      expect(SpeedMath.gaugeFraction(1000, SpeedMath.ticks), 1);
      expect(SpeedMath.gaugeFraction(131.3, SpeedMath.ticks), closeTo((4 + 31.3 / 150) / 8, 1e-9));
      expect(SpeedMath.ticksFor(1200), SpeedMath.fastTicks);
    });

    test('quality ratings and bufferbloat', () {
      expect(SpeedMath.streaming(131, 37), 3);
      expect(SpeedMath.streamingLabel(3), '4K Ultra HD');
      expect(SpeedMath.streaming(2, 37), 0);
      expect(SpeedMath.gaming(25, 4, 60, 50), 3);
      expect(SpeedMath.gaming(25, 4, 60, 1), 0);
      expect(SpeedMath.videoCalls(10, 5, 40, 5), 3);
      expect(SpeedMath.browsing(0.5, 40), 0);
      expect(SpeedMath.bufferbloatGrade(37, 553, 0), 'F');
      expect(SpeedMath.bufferbloatGrade(37, 40, 39), 'A+');
      expect(SpeedMath.bufferbloatGrade(0, 0, 0), '—');
    });

    test('text', () {
      expect(SpeedMath.speedText(131.3), '131.30');
      expect(SpeedMath.speedText(1234.5), '1235');
      expect(SpeedMath.shortSpeed(7.44), '7.4');
      expect(SpeedMath.shortSpeed(131.3), '131');
      expect(SpeedMath.bytesText(312 * 1024 * 1024), '312 MB');
      final said = SpeedMath.spokenSummary(down: 131.3, up: 45.2, ping: 37, jitter: 3, isp: 'Zenlayer');
      expect(said, startsWith('Your internet speed on Zenlayer is 131 megabits per second download and 45 upload'));
      expect(said, contains('4K streaming'));
      expect(said, isNot(contains('*')));
    });
  });

  group('NetworkIntents', () {
    test('speed questions', () {
      for (final q in [
        "Hey NOVA, what's my internet speed?",
        'what is my network speed',
        'How fast is my wifi',
        'run a speed test',
        'test my internet',
        'my wifi is so slow',
        'what is my download speed',
      ]) {
        expect(NetworkIntents.parse(q), NetworkIntent.speedTest, reason: q);
      }
    });

    test('ping, IP, battery, open', () {
      expect(NetworkIntents.parse("what's my ping"), NetworkIntent.ping);
      expect(NetworkIntents.parse('Hey NOVA what is my IP address'), NetworkIntent.ip);
      expect(NetworkIntents.parse("what's my battery percentage"), NetworkIntent.battery);
      expect(NetworkIntents.parse('open NOVA Network'), NetworkIntent.open);
    });

    test('other requests are left alone', () {
      for (final q in ['search internet speed tips', 'open youtube', 'what is the speed of light', 'how to improve battery life', '']) {
        expect(NetworkIntents.parse(q), NetworkIntent.none, reason: q);
      }
    });
  });

  group('models and history', () {
    test('server info', () {
      final m = NetworkMeta.fromJson({
        'ip': '31.57.228.94',
        'ipVersion': 4,
        'isp': 'Zenlayer',
        'asn': 21859,
        'city': 'Dubai',
        'country': 'AE',
        'server': {'colo': 'FJR', 'city': 'Fujairah', 'country': 'AE'},
      });
      expect(m.place, 'Dubai, AE');
      expect(m.serverName, 'Fujairah (FJR)');
      expect(NetworkMeta.fromJson(const {}).place, 'Unknown');
    });

    test('results survive saving and loading', () {
      final r = SpeedTestResult(
        time: DateTime.fromMillisecondsSinceEpoch(1790000000000),
        downloadMbps: 131.3,
        uploadMbps: 45.2,
        pingMs: 37,
        jitterMs: 3,
        loadedDownMs: 553,
        bytesUsed: 1000,
        connections: 4,
        connection: 'Wi-Fi',
        isp: 'Zenlayer',
        server: 'Fujairah (FJR)',
      );
      final back = SpeedHistory.decode(SpeedHistory.encode([r])).single;
      expect(back.downloadMbps, 131.3);
      expect(back.loadedDownMs, 553);
      expect(back.isp, 'Zenlayer');
      expect(back.time, r.time);
      expect(SpeedHistory.decode('not json'), isEmpty);
      expect(SpeedHistory.decode(null), isEmpty);
    });

    test('device details from Android', () {
      final d = DeviceSnapshot.fromMap({
        'device': {'name': 'Kobby\'s phone', 'model': 'X6871', 'android': '15'},
        'battery': {'level': 76, 'charging': true, 'plugged': 'USB'},
        'network': {'transport': 'wifi', 'wifiFrequency': 5180, 'signalLevel': 4, 'localIps': ['192.168.1.4'], 'dnsServers': []},
      });
      expect(d.deviceName, "Kobby's phone");
      expect(d.batteryPercent, 76);
      expect(d.charging, isTrue);
      expect(d.connectionLabel, 'Wi-Fi');
      expect(d.wifiBand, '5 GHz');
      expect(d.localIps, ['192.168.1.4']);
      expect(DeviceSnapshot.fromMap(null).connected, isFalse);
    });

    test('latency monitor summary', () {
      final s = NetworkTools.summarize(const [LatencySample(0, 30), LatencySample(1, null), LatencySample(2, 50)]);
      expect(s.avg, 40);
      expect(s.min, 30);
      expect(s.max, 50);
      expect(s.loss, closeTo(33.3, 0.1));
    });
  });
}
