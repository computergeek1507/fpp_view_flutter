import 'dart:async';
import 'dart:typed_data';

import '../models/fpp_device.dart';
import 'discovery_transport.dart';
import 'fpp_api.dart';

/// Discovers FPP devices via the native MultiSync UDP ping, mDNS, and by
/// pulling the peer list from any device that answers. Emits [FppDevice]
/// objects as they are found; the caller is responsible for merge/dedupe.
///
/// The actual socket work is delegated to a [DiscoveryTransport] that is
/// platform-split: native sockets on desktop/mobile, a no-op on web. On web,
/// only manual-IP add + HTTP enrichment function.
class FppDiscovery {
  final FppApi api;
  final DiscoveryTransport _transport;
  bool _started = false;

  final _controller = StreamController<FppDevice>.broadcast();

  /// Tracks IPs we've already kicked an HTTP enrichment for this session, to
  /// avoid hammering the same device on every repeated ping.
  final Set<String> _enriched = {};

  FppDiscovery({FppApi? api, DiscoveryTransport? transport})
      : api = api ?? FppApi(),
        _transport = transport ?? DiscoveryTransport();

  Stream<FppDevice> get devices => _controller.stream;

  /// Whether this platform can do zero-config UDP/mDNS discovery.
  bool get supportsNetworkDiscovery => _transport.supportsNetworkDiscovery;

  /// Run one discovery sweep: ensure the listener is up, send the ping, and
  /// kick off mDNS. Safe to call repeatedly. No-op transport on web.
  Future<void> discover({Duration listenFor = const Duration(seconds: 5)}) async {
    if (!_started) {
      await _transport.start(
        onPacket: _handlePacket,
        onMdnsHost: _onMdnsHost,
      );
      _started = true;
    }
    _transport.sendBroadcastPing(_buildDiscoveryPing());
    _transport.browseMdns(listenFor);
  }

  void _onMdnsHost(String ip) {
    if (!_enriched.contains(ip)) {
      _enriched.add(ip);
      unawaited(enrichAndPullPeers(ip));
    }
  }

  /// Build the 207-byte v2 discovery ping (see xLights FPP.cpp).
  static Uint8List _buildDiscoveryPing() {
    final b = Uint8List(207);
    b[0] = 0x46; // 'F'
    b[1] = 0x50; // 'P'
    b[2] = 0x50; // 'P'
    b[3] = 0x44; // 'D'
    b[4] = 0x04; // Ping packet
    b[5] = 207 - 7; // ExtraDataLen (MSB); fits in one byte
    b[6] = 0;
    b[7] = 2; // ping version 2
    b[8] = 1; // subtype 1 = discover request
    b[9] = 0xC0; // hardware type: not a real FPP, so devices don't track us
    // version major/minor (cosmetic), mode 0, IP 0.0.0.0 -> nobody contacts us.
    return b;
  }

  /// Parse an incoming FPPD ping (0x04) response packet.
  void _handlePacket(List<int> data) {
    if (data.length < 19) return;
    if (data[0] != 0x46 || data[1] != 0x50 || data[2] != 0x50 || data[3] != 0x44) return;
    if (data[4] != 0x04) return;

    final ip = '${data[15]}.${data[16]}.${data[17]}.${data[18]}';
    if (ip == '0.0.0.0') return; // our own discover packet echoed back

    final d = FppDevice(ip: ip, discoverySource: 'udp');
    d.typeId = data[9];
    d.majorVersion = (data[10] << 8) + data[11];
    d.minorVersion = (data[12] << 8) + data[13];
    switch (data[14]) {
      case 1:
        d.mode = 'bridge';
        break;
      case 2:
        d.mode = 'player';
        break;
      case 4:
      case 6:
        d.mode = 'master';
        break;
      case 8:
        d.mode = 'remote';
        break;
    }
    d.hostname = _cString(data, 19, 65);
    d.version = _cString(data, 84, 41);
    if (data.length > 125) d.platform = _cString(data, 125, 41);

    _controller.add(d);

    // For real FPP instances, enrich over HTTP and pull their peer list once.
    if (data[9] < 0x80 && !_enriched.contains(ip)) {
      _enriched.add(ip);
      enrichAndPullPeers(ip);
    }
  }

  static String _cString(List<int> data, int start, int maxLen) {
    if (start >= data.length) return '';
    final end = (start + maxLen).clamp(0, data.length);
    final bytes = <int>[];
    for (var i = start; i < end; i++) {
      if (data[i] == 0) break;
      bytes.add(data[i]);
    }
    return String.fromCharCodes(bytes).trim();
  }

  /// HTTP-enrich a known IP (system/info) and emit its MultiSync peers.
  Future<void> enrichAndPullPeers(String ip) async {
    final info = await api.systemInfo(ip);
    if (info != null) {
      final d = FppDevice.fromSysInfo(info, source: 'http');
      if (d.ip.isEmpty) d.ip = ip;
      _controller.add(d);
    }
    final peers = await api.multiSyncSystems(ip);
    for (final p in peers) {
      final pd = FppDevice.fromSysInfo(p, source: 'peer');
      if (pd.ip.isNotEmpty) {
        _controller.add(pd);
        if (!_enriched.contains(pd.ip)) {
          _enriched.add(pd.ip);
          // Light enrich of peers without recursing into their peer lists.
          unawaited(_enrichOnly(pd.ip));
        }
      }
    }
  }

  Future<void> _enrichOnly(String ip) async {
    final info = await api.systemInfo(ip);
    if (info != null) {
      final d = FppDevice.fromSysInfo(info, source: 'http');
      if (d.ip.isEmpty) d.ip = ip;
      _controller.add(d);
    }
  }

  /// Manually add a host by IP/hostname: ping it (native) and probe over HTTP.
  Future<void> addManual(String host) async {
    _transport.sendUnicastPing(_buildDiscoveryPing(), host);
    _enriched.add(host);
    await enrichAndPullPeers(host);
  }

  /// Clear the per-session enrichment cache so a fresh scan re-probes peers.
  void resetEnrichmentCache() => _enriched.clear();

  void dispose() {
    _transport.dispose();
    _controller.close();
  }
}
