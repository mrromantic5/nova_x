// lib/features/network/models/network_models.dart
//
// NOVA Network data: server/IP information, a finished speed test, and the
// phone's own device + connection details (read on the phone).

/// Who the internet sees: public IP, provider and approximate place (from the
/// IP address — no GPS), plus the test server location.
class NetworkMeta {
  const NetworkMeta({
    this.ip = '',
    this.ipVersion = 4,
    this.isp,
    this.asn,
    this.city,
    this.region,
    this.country,
    this.timezone,
    this.latitude,
    this.longitude,
    this.serverColo,
    this.serverCity,
    this.serverCountry,
    this.httpProtocol,
    this.tlsVersion,
    this.rttMs,
  });

  factory NetworkMeta.fromJson(Map<String, dynamic> j) {
    String? s(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
    double? d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    final server = j['server'] is Map ? Map<String, dynamic>.from(j['server'] as Map) : const <String, dynamic>{};
    return NetworkMeta(
      ip: s(j['ip']) ?? '',
      ipVersion: (j['ipVersion'] is num) ? (j['ipVersion'] as num).toInt() : 4,
      isp: s(j['isp']),
      asn: j['asn'] is num ? (j['asn'] as num).toInt() : null,
      city: s(j['city']),
      region: s(j['region']),
      country: s(j['country']),
      timezone: s(j['timezone']),
      latitude: d(j['latitude']),
      longitude: d(j['longitude']),
      serverColo: s(server['colo']),
      serverCity: s(server['city']),
      serverCountry: s(server['country']),
      httpProtocol: s(j['httpProtocol']),
      tlsVersion: s(j['tlsVersion']),
      rttMs: d(j['rttMs']),
    );
  }

  final String ip;
  final int ipVersion;
  final String? isp;
  final int? asn;
  final String? city;
  final String? region;
  final String? country;
  final String? timezone;
  final double? latitude;
  final double? longitude;
  final String? serverColo;
  final String? serverCity;
  final String? serverCountry;
  final String? httpProtocol;
  final String? tlsVersion;
  final double? rttMs;

  /// "Dubai, AE"
  String get place {
    final parts = [city, country].whereType<String>().toList();
    return parts.isEmpty ? 'Unknown' : parts.join(', ');
  }

  /// "Fujairah (FJR)"
  String get serverName {
    if (serverCity != null && serverColo != null) return '$serverCity ($serverColo)';
    return serverColo ?? 'Nearest server';
  }
}

/// One finished speed test (saved in the history on the phone).
class SpeedTestResult {
  const SpeedTestResult({
    required this.time,
    required this.downloadMbps,
    required this.uploadMbps,
    required this.pingMs,
    required this.jitterMs,
    this.loadedDownMs = 0,
    this.loadedUpMs = 0,
    this.peakDownMbps = 0,
    this.peakUpMbps = 0,
    this.bytesUsed = 0,
    this.connections = 1,
    this.connection = '',
    this.isp,
    this.ip,
    this.server,
    this.mode = 'full',
  });

  factory SpeedTestResult.fromJson(Map<String, dynamic> j) {
    double d(String k) => (j[k] is num) ? (j[k] as num).toDouble() : 0;
    int i(String k) => (j[k] is num) ? (j[k] as num).toInt() : 0;
    String? s(String k) => j[k] is String && (j[k] as String).isNotEmpty ? j[k] as String : null;
    return SpeedTestResult(
      time: DateTime.fromMillisecondsSinceEpoch(i('time')),
      downloadMbps: d('down'),
      uploadMbps: d('up'),
      pingMs: d('ping'),
      jitterMs: d('jitter'),
      loadedDownMs: d('loadedDown'),
      loadedUpMs: d('loadedUp'),
      peakDownMbps: d('peakDown'),
      peakUpMbps: d('peakUp'),
      bytesUsed: i('bytes'),
      connections: i('connections') == 0 ? 1 : i('connections'),
      connection: s('connection') ?? '',
      isp: s('isp'),
      ip: s('ip'),
      server: s('server'),
      mode: s('mode') ?? 'full',
    );
  }

  final DateTime time;
  final double downloadMbps;
  final double uploadMbps;
  final double pingMs;
  final double jitterMs;

  /// Latency while downloading / uploading (bufferbloat).
  final double loadedDownMs;
  final double loadedUpMs;
  final double peakDownMbps;
  final double peakUpMbps;
  final int bytesUsed;
  final int connections;

  /// "Wi-Fi", "Mobile data", "Ethernet"…
  final String connection;
  final String? isp;
  final String? ip;
  final String? server;

  /// "full", "light" or "quick" (NOVA voice).
  final String mode;

  Map<String, dynamic> toJson() => {
        'time': time.millisecondsSinceEpoch,
        'down': downloadMbps,
        'up': uploadMbps,
        'ping': pingMs,
        'jitter': jitterMs,
        'loadedDown': loadedDownMs,
        'loadedUp': loadedUpMs,
        'peakDown': peakDownMbps,
        'peakUp': peakUpMbps,
        'bytes': bytesUsed,
        'connections': connections,
        'connection': connection,
        if (isp != null) 'isp': isp,
        if (ip != null) 'ip': ip,
        if (server != null) 'server': server,
        'mode': mode,
      };
}

/// The phone and its connection (from Android; nothing leaves the phone).
class DeviceSnapshot {
  const DeviceSnapshot(this.raw);

  factory DeviceSnapshot.fromMap(Map<Object?, Object?>? m) =>
      DeviceSnapshot(m == null ? const {} : m.map((k, v) => MapEntry('$k', v)));

  final Map<String, Object?> raw;

  Map<String, Object?> _map(String k) {
    final v = raw[k];
    return v is Map ? v.map((key, value) => MapEntry('$key', value)) : const {};
  }

  String? _s(Map<String, Object?> m, String k) {
    final v = m[k];
    return v is String && v.trim().isNotEmpty ? v.trim() : null;
  }

  num? _n(Map<String, Object?> m, String k) => m[k] is num ? m[k] as num : null;
  bool _b(Map<String, Object?> m, String k) => m[k] == true;

  Map<String, Object?> get _device => _map('device');
  Map<String, Object?> get _battery => _map('battery');
  Map<String, Object?> get _network => _map('network');
  Map<String, Object?> get _system => _map('system');

  // Device
  String get deviceName => _s(_device, 'name') ?? '${manufacturer ?? ''} ${model ?? ''}'.trim();
  String? get manufacturer => _s(_device, 'manufacturer');
  String? get model => _s(_device, 'model');
  String? get androidVersion => _s(_device, 'android');
  int? get sdk => _n(_device, 'sdk')?.toInt();

  // Battery
  int? get batteryPercent => _n(_battery, 'level')?.toInt();
  bool get charging => _b(_battery, 'charging');
  String? get chargeSource => _s(_battery, 'plugged');
  double? get batteryTempC => _n(_battery, 'temperature')?.toDouble();
  String? get batteryHealth => _s(_battery, 'health');
  bool get powerSave => _b(_battery, 'powerSave');

  // Network
  String get transport => _s(_network, 'transport') ?? 'none';
  bool get connected => transport != 'none';
  bool get metered => _b(_network, 'metered');
  bool get vpn => _b(_network, 'vpn');
  bool get validated => _b(_network, 'validated');
  int? get wifiLinkMbps => _n(_network, 'wifiLinkMbps')?.toInt();
  int? get wifiFrequencyMhz => _n(_network, 'wifiFrequency')?.toInt();
  int? get wifiRssi => _n(_network, 'wifiRssi')?.toInt();
  String? get wifiStandard => _s(_network, 'wifiStandard');
  int? get signalLevel => _n(_network, 'signalLevel')?.toInt();
  int? get signalDbm => _n(_network, 'signalDbm')?.toInt();
  String? get carrier => _s(_network, 'carrier');
  int? get downKbpsEstimate => _n(_network, 'downKbps')?.toInt();
  int? get upKbpsEstimate => _n(_network, 'upKbps')?.toInt();
  int? get mtu => _n(_network, 'mtu')?.toInt();
  bool get privateDns => _b(_network, 'privateDns');
  String? get privateDnsServer => _s(_network, 'privateDnsServer');
  bool get hasIpv6 => _b(_network, 'ipv6');
  List<String> get localIps => _list(_network['localIps']);
  List<String> get dnsServers => _list(_network['dnsServers']);

  // System
  int? get ramTotalMb => _n(_system, 'ramTotalMb')?.toInt();
  int? get ramFreeMb => _n(_system, 'ramFreeMb')?.toInt();
  int? get storageTotalMb => _n(_system, 'storageTotalMb')?.toInt();
  int? get storageFreeMb => _n(_system, 'storageFreeMb')?.toInt();
  int? get cpuCores => _n(_system, 'cpuCores')?.toInt();
  String? get cpuAbi => _s(_system, 'abi');
  String? get screen => _s(_system, 'screen');
  int? get refreshRate => _n(_system, 'refreshRate')?.round();

  static List<String> _list(Object? v) =>
      v is List ? v.whereType<String>().where((s) => s.isNotEmpty).toList() : const [];

  /// "Wi-Fi", "Mobile data", "Ethernet", "VPN", "Offline"
  String get connectionLabel => switch (transport) {
        'wifi' => 'Wi-Fi',
        'cellular' => 'Mobile data',
        'ethernet' => 'Ethernet',
        'vpn' => 'VPN',
        'bluetooth' => 'Bluetooth tether',
        'none' => 'Offline',
        _ => 'Connected',
      };

  /// "5 GHz" for Wi-Fi.
  String? get wifiBand {
    final f = wifiFrequencyMhz;
    if (f == null || f <= 0) return null;
    if (f >= 5925) return '6 GHz';
    if (f >= 4900) return '5 GHz';
    return '2.4 GHz';
  }
}
