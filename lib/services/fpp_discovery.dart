import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:multicast_dns/multicast_dns.dart';

import '../models/fpp_device.dart';
import 'fpp_api.dart';

/// FPP MultiSync control protocol constants.
const String _kFppMulticastAddr = '239.70.80.80';
const int _kFppCtrlPort = 32320;
const String _kFppMdnsService = '_fppd._udp';

/// Discovers FPP devices via the native MultiSync UDP ping, mDNS, and by
/// pulling the peer list from any device that answers. Emits [FppDevice]
/// objects as they are found; the caller is responsible for merge/dedupe.
class FppDiscovery {
  final FppApi api;

  RawDatagramSocket? _socket;
  StreamSubscription? _socketSub;
  final _controller = StreamController<FppDevice>.broadcast();

  /// Tracks IPs we've already kicked an HTTP enrichment for this session, to
  /// avoid hammering the same device on every repeated ping.
  final Set<String> _enriched = {};

  FppDiscovery({FppApi? api}) : api = api ?? FppApi();

  Stream<FppDevice> get devices => _controller.stream;

  /// Run one discovery sweep: open the UDP listener, send the ping three ways,
  /// kick off mDNS, and keep listening for [listenFor]. Safe to call repeatedly.
  Future<void> discover({Duration listenFor = const Duration(seconds: 5)}) async {
    await _ensureSocket();
    _sendPing();
    _runMdns(listenFor);
    // The socket keeps receiving responses in the background via _socketSub.
  }

  Future<void> _ensureSocket() async {
    if (_socket != null) return;
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _kFppCtrlPort,
          reuseAddress: true, reusePort: false);
      socket.broadcastEnabled = true;
      socket.readEventsEnabled = true;
      try {
        socket.joinMulticast(InternetAddress(_kFppMulticastAddr));
      } catch (_) {/* some interfaces reject join; broadcast still works */}
      _socket = socket;
      _socketSub = socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket.receive();
          if (dg != null) _handlePacket(dg.data);
        }
      });
    } on SocketException {
      // Port busy (another FPP/xLights tool on this host). Bind ephemeral so we
      // can still send pings and receive unicast replies, just not the group.
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      _socket = socket;
      _socketSub = socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket.receive();
          if (dg != null) _handlePacket(dg.data);
        }
      });
    }
  }

  /// Build and send the 207-byte v2 discovery ping (see xLights FPP.cpp).
  void _sendPing() {
    final socket = _socket;
    if (socket == null) return;
    final pkt = _buildDiscoveryPing();
    final targets = <InternetAddress>[
      InternetAddress(_kFppMulticastAddr),
      InternetAddress('255.255.255.255'),
    ];
    for (final addr in targets) {
      try {
        socket.send(pkt, addr, _kFppCtrlPort);
      } catch (_) {/* interface may not support this target */}
    }
  }

  /// Unicast a ping to a specific host (used for manual add / known IPs).
  void pingHost(String ip) {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.send(_buildDiscoveryPing(), InternetAddress(ip), _kFppCtrlPort);
    } catch (_) {}
  }

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

  /// Manually add a host by IP/hostname: ping it and probe over HTTP.
  Future<void> addManual(String host) async {
    pingHost(host);
    _enriched.add(host);
    await enrichAndPullPeers(host);
  }

  void _runMdns(Duration timeout) {
    // mDNS is a best-effort, supplementary path. On Windows the multicast join
    // on 0.0.0.0:5353 can fail asynchronously (errno 1232) from inside the
    // client's socket listener, which a plain try/catch around start() cannot
    // catch. runZonedGuarded contains any such uncaught async error so it can
    // never crash the app; UDP ping + broadcast + peer-pull remain the primary
    // discovery paths.
    runZonedGuarded(() async {
      // The default socket factory binds with reusePort:true, which Windows
      // rejects outright. Force reusePort:false so the bind succeeds.
      final client = MDnsClient(
        rawDatagramSocketFactory: (dynamic host, int port,
            {bool reuseAddress = true, bool reusePort = true, int ttl = 1}) {
          return RawDatagramSocket.bind(host, port,
              reuseAddress: reuseAddress, reusePort: false, ttl: ttl);
        },
      );
      try {
        await client.start();
        await for (final ptr in client
            .lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(_kFppMdnsService))
            .timeout(timeout, onTimeout: (sink) => sink.close())) {
          await for (final srv in client.lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(ptr.domainName))) {
            await for (final ip in client.lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(srv.target))) {
              final addr = ip.address.address;
              if (!_enriched.contains(addr)) {
                _enriched.add(addr);
                unawaited(enrichAndPullPeers(addr));
              }
            }
          }
        }
      } catch (_) {/* mDNS unavailable on this network/platform */} finally {
        client.stop();
      }
    }, (error, stack) {/* swallow async mDNS socket errors (e.g. Windows errno 1232) */});
  }

  /// Clear the per-session enrichment cache so a fresh scan re-probes peers.
  void resetEnrichmentCache() => _enriched.clear();

  void dispose() {
    _socketSub?.cancel();
    _socket?.close();
    _controller.close();
  }
}
