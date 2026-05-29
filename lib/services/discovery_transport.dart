import 'discovery_transport_stub.dart'
    if (dart.library.io) 'discovery_transport_io.dart';

/// Low-level network transport for FPP discovery: UDP MultiSync ping +
/// broadcast/multicast listening, and mDNS browsing.
///
/// The native (dart:io) implementation does real sockets; the web stub is a
/// no-op so the app still compiles and runs in the browser (where raw UDP and
/// mDNS are unavailable). On web, discovery falls back to manual-IP + HTTP.
abstract class DiscoveryTransport {
  /// Whether this platform can actually do UDP/mDNS discovery.
  bool get supportsNetworkDiscovery;

  /// Open sockets and begin listening. [onPacket] receives raw UDP datagrams
  /// (the FPPD ping responses); [onMdnsHost] receives IPs found via mDNS.
  Future<void> start({
    required void Function(List<int> data) onPacket,
    required void Function(String ip) onMdnsHost,
  });

  /// Send the discovery ping via multicast + broadcast.
  void sendBroadcastPing(List<int> packet);

  /// Unicast a ping to a single host.
  void sendUnicastPing(List<int> packet, String ip);

  /// Kick off an mDNS browse that runs for [timeout].
  void browseMdns(Duration timeout);

  void dispose();

  /// Factory resolved at compile time via conditional import.
  factory DiscoveryTransport() => createTransport();
}
