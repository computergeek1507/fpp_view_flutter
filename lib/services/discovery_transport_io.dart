import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

import 'discovery_transport.dart';

const String _kFppMulticastAddr = '239.70.80.80';
const int _kFppCtrlPort = 32320;
const String _kFppMdnsService = '_fppd._udp';

/// Native UDP/mDNS transport (Windows, Android, iOS, macOS, Linux).
class IoDiscoveryTransport implements DiscoveryTransport {
  RawDatagramSocket? _socket;
  StreamSubscription? _socketSub;
  void Function(String ip)? _onMdnsHost;

  @override
  bool get supportsNetworkDiscovery => true;

  @override
  Future<void> start({
    required void Function(List<int> data) onPacket,
    required void Function(String ip) onMdnsHost,
  }) async {
    _onMdnsHost = onMdnsHost;
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
          if (dg != null) onPacket(dg.data);
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
          if (dg != null) onPacket(dg.data);
        }
      });
    }
  }

  @override
  void sendBroadcastPing(List<int> packet) {
    final socket = _socket;
    if (socket == null) return;
    final targets = <InternetAddress>[
      InternetAddress(_kFppMulticastAddr),
      InternetAddress('255.255.255.255'),
    ];
    for (final addr in targets) {
      try {
        socket.send(packet, addr, _kFppCtrlPort);
      } catch (_) {/* interface may not support this target */}
    }
  }

  @override
  void sendUnicastPing(List<int> packet, String ip) {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.send(packet, InternetAddress(ip), _kFppCtrlPort);
    } catch (_) {}
  }

  @override
  void browseMdns(Duration timeout) {
    final onHost = _onMdnsHost;
    if (onHost == null) return;
    // mDNS is best-effort. On Windows the multicast join on 0.0.0.0:5353 can
    // fail asynchronously (errno 1232) from inside the client's socket
    // listener, which a try/catch around start() can't catch. runZonedGuarded
    // contains any such uncaught async error so it never crashes the app.
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
              onHost(ip.address.address);
            }
          }
        }
      } catch (_) {/* mDNS unavailable on this network/platform */} finally {
        client.stop();
      }
    }, (error, stack) {/* swallow async mDNS socket errors (e.g. Windows errno 1232) */});
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    _socket?.close();
    _socket = null;
  }
}

DiscoveryTransport createTransport() => IoDiscoveryTransport();
