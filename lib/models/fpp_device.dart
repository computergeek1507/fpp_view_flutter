import 'dart:convert';

/// A discovered Falcon Player (FPP) instance and its last-known playback status.
///
/// Field population is version-aware: `/api/system/info` (FPP 2+) and the
/// older `fppjson.php?command=getSysInfo` use different key casing, and the
/// UDP MultiSync ping packet supplies a subset of these directly.
class FppDevice {
  String ip;
  String hostname;
  String version;
  String mode;
  String platform;
  String variant;
  int majorVersion;
  int minorVersion;

  /// Hardware type id from the ping packet / sysinfo. Values < 0x80 are real
  /// FPP instances; >= 0x80 are remote controllers (Falcon, ESPixelStick...).
  int typeId;

  /// How this device was found, for display/debugging.
  String discoverySource;

  // Live playback status (from /api/system/status).
  String statusName;
  String currentPlaylist;
  String currentSequence;
  String currentSong;
  int secondsPlayed;
  int secondsRemaining;
  int volume;
  bool reachable;
  DateTime? lastSeen;

  FppDevice({
    this.ip = '',
    this.hostname = '',
    this.version = '',
    this.mode = '',
    this.platform = '',
    this.variant = '',
    this.majorVersion = -1,
    this.minorVersion = -1,
    this.typeId = 0,
    this.discoverySource = '',
    this.statusName = '',
    this.currentPlaylist = '',
    this.currentSequence = '',
    this.currentSong = '',
    this.secondsPlayed = 0,
    this.secondsRemaining = 0,
    this.volume = -1,
    this.reachable = false,
    this.lastSeen,
  });

  /// A device is uniquely identified by its IP on the local network.
  String get key => ip;

  bool get isFppDevice {
    if (typeId != 0) return typeId < 0x7F;
    final p = platform.toLowerCase();
    return p.contains('beaglebone') || p.contains('raspberry') || p.contains('fpp');
  }

  bool get isPlayer {
    final m = mode.toLowerCase();
    return m == 'player' || m == 'master';
  }

  String get prettyVersion {
    if (version.isNotEmpty) return version;
    if (majorVersion >= 0) return '$majorVersion.$minorVersion';
    return '';
  }

  /// Merge newer data into this device without clobbering known values with blanks.
  void mergeFrom(FppDevice other) {
    if (other.hostname.isNotEmpty) hostname = other.hostname;
    if (other.version.isNotEmpty) version = other.version;
    if (other.mode.isNotEmpty) mode = other.mode;
    if (other.platform.isNotEmpty) platform = other.platform;
    if (other.variant.isNotEmpty) variant = other.variant;
    if (other.majorVersion >= 0) majorVersion = other.majorVersion;
    if (other.minorVersion >= 0) minorVersion = other.minorVersion;
    if (other.typeId != 0) typeId = other.typeId;
    if (other.discoverySource.isNotEmpty) discoverySource = other.discoverySource;
  }

  /// Build from `/api/system/info` JSON (or legacy getSysInfo).
  factory FppDevice.fromSysInfo(Map<String, dynamic> json, {String source = ''}) {
    final d = FppDevice(discoverySource: source);
    d.hostname = _firstString(json, ['HostName', 'hostname']);
    d.version = _firstString(json, ['Version', 'version']);
    d.mode = _firstString(json, ['fppModeString', 'Mode', 'mode']);
    d.platform = _firstString(json, ['Platform', 'type']);
    d.variant = _firstString(json, ['Variant', 'variant']);
    d.majorVersion = _firstInt(json, ['majorVersion'], -1);
    d.minorVersion = _firstInt(json, ['minorVersion'], -1);
    d.typeId = _firstInt(json, ['typeId'], 0);

    // IP can arrive as a single "address" or an "IPs" array.
    final addr = _firstString(json, ['address', 'IP']);
    if (addr.isNotEmpty) {
      d.ip = addr;
    } else if (json['IPs'] is List && (json['IPs'] as List).isNotEmpty) {
      d.ip = (json['IPs'] as List).first.toString();
    }
    return d;
  }

  /// Apply `/api/system/status` JSON onto this device.
  void applyStatus(Map<String, dynamic> json) {
    statusName = _firstString(json, ['status_name']);
    volume = _firstInt(json, ['volume'], volume);
    currentSequence = _firstString(json, ['current_sequence']);
    currentSong = _firstString(json, ['current_song']);
    secondsPlayed = _asInt(json['seconds_played'], 0);
    secondsRemaining = _asInt(json['seconds_remaining'], 0);
    final cp = json['current_playlist'];
    if (cp is Map) {
      currentPlaylist = (cp['playlist'] ?? '').toString();
    }
    if (mode.isEmpty) {
      mode = _firstString(json, ['mode_name']);
    }
    reachable = true;
    lastSeen = DateTime.now();
  }

  static String _firstString(Map<String, dynamic> json, List<String> keys) {
    for (final k in keys) {
      final v = json[k];
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return '';
  }

  static int _firstInt(Map<String, dynamic> json, List<String> keys, int fallback) {
    for (final k in keys) {
      if (json.containsKey(k)) return _asInt(json[k], fallback);
    }
    return fallback;
  }

  static int _asInt(dynamic v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  // Persistence: we only save the IP list; everything else is re-fetched live.
  static String encodeIpList(Iterable<String> ips) => jsonEncode(ips.toList());
  static List<String> decodeIpList(String? s) {
    if (s == null || s.isEmpty) return [];
    try {
      final list = jsonDecode(s);
      if (list is List) return list.map((e) => e.toString()).toList();
    } catch (_) {}
    return [];
  }
}
