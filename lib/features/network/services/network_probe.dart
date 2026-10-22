// lib/features/network/services/network_probe.dart
//
// What the NOVA assistant uses to answer connection questions in the
// background ("Hey NOVA, what's my internet speed?"). The real
// implementation runs the NOVA Network speed test and saves the result in
// the NOVA Network history; tests use a fake.

import '../models/network_models.dart';
import 'network_services.dart';
import 'speed_math.dart';
import 'speed_test_engine.dart';

abstract class NovaNetworkProbe {
  Future<SpeedTestResult> speedTest({void Function(SpeedProgress)? onProgress});

  /// Median latency to the nearest server (ms).
  Future<double> ping();

  Future<NetworkMeta> meta();

  Future<DeviceSnapshot> device();

  void cancel();
}

class NovaNetworkProbeImpl implements NovaNetworkProbe {
  SpeedTestEngine? _engine;

  @override
  Future<SpeedTestResult> speedTest({void Function(SpeedProgress)? onProgress}) async {
    final engine = SpeedTestEngine();
    _engine = engine;
    try {
      final device = await DeviceInfoService.read();
      final result = await engine.run(
        SpeedTestOptions.quick,
        onProgress: onProgress,
        connection: device.connected ? device.connectionLabel : '',
      );
      await SpeedHistory.add(result);
      return result;
    } finally {
      if (identical(_engine, engine)) _engine = null;
    }
  }

  @override
  Future<double> ping() async {
    final engine = SpeedTestEngine();
    _engine = engine;
    try {
      return SpeedMath.median(await engine.measureLatency(8));
    } finally {
      if (identical(_engine, engine)) _engine = null;
    }
  }

  @override
  Future<NetworkMeta> meta() async {
    final engine = SpeedTestEngine();
    _engine = engine;
    try {
      return await engine.fetchMeta();
    } finally {
      if (identical(_engine, engine)) _engine = null;
    }
  }

  @override
  Future<DeviceSnapshot> device() => DeviceInfoService.read();

  @override
  void cancel() => _engine?.cancel();
}
