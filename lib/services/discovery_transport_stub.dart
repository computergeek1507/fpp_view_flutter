import 'discovery_transport.dart';

/// Web (and any non-dart:io) fallback: discovery transport is unavailable.
/// All methods are no-ops; the app uses manual-IP + HTTP instead.
class WebDiscoveryTransport implements DiscoveryTransport {
  @override
  bool get supportsNetworkDiscovery => false;

  @override
  Future<void> start({
    required void Function(List<int> data) onPacket,
    required void Function(String ip) onMdnsHost,
  }) async {}

  @override
  void sendBroadcastPing(List<int> packet) {}

  @override
  void sendUnicastPing(List<int> packet, String ip) {}

  @override
  void browseMdns(Duration timeout) {}

  @override
  void dispose() {}
}

DiscoveryTransport createTransport() => WebDiscoveryTransport();
