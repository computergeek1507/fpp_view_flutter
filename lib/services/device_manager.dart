import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/fpp_device.dart';
import 'fpp_api.dart';
import 'fpp_discovery.dart';

/// Owns the live device list: drives discovery, merges results, persists known
/// IPs, and polls playback status on a timer. UI listens via [ChangeNotifier].
class DeviceManager extends ChangeNotifier {
  static const _prefsKey = 'known_fpp_ips';

  final FppApi api;
  final FppDiscovery discovery;

  final Map<String, FppDevice> _devices = {};
  StreamSubscription<FppDevice>? _discoverySub;
  Timer? _statusTimer;
  bool _scanning = false;

  DeviceManager({FppApi? api, FppDiscovery? discovery})
      : api = api ?? FppApi(),
        discovery = discovery ?? FppDiscovery(api: api ?? FppApi());

  List<FppDevice> get devices {
    final list = _devices.values.toList();
    list.sort((a, b) {
      // Real FPP players first, then by hostname/IP.
      final byType = (b.isFppDevice ? 1 : 0) - (a.isFppDevice ? 1 : 0);
      if (byType != 0) return byType;
      final an = a.hostname.isNotEmpty ? a.hostname : a.ip;
      final bn = b.hostname.isNotEmpty ? b.hostname : b.ip;
      return an.toLowerCase().compareTo(bn.toLowerCase());
    });
    return list;
  }

  bool get scanning => _scanning;

  /// Whether this platform supports zero-config UDP/mDNS discovery. False on
  /// web, where only manual-IP add + HTTP polling are available.
  bool get supportsNetworkDiscovery => discovery.supportsNetworkDiscovery;

  Future<void> init() async {
    _discoverySub = discovery.devices.listen(_onDeviceFound);
    final prefs = await SharedPreferences.getInstance();
    final ips = FppDevice.decodeIpList(prefs.getString(_prefsKey));
    for (final ip in ips) {
      _devices.putIfAbsent(ip, () => FppDevice(ip: ip, discoverySource: 'saved'));
      unawaited(discovery.enrichAndPullPeers(ip));
    }
    notifyListeners();
    await refreshAllStatus();
    await scan();
    _startStatusPolling();
  }

  void _onDeviceFound(FppDevice incoming) {
    if (incoming.ip.isEmpty) return;
    final existing = _devices[incoming.ip];
    if (existing == null) {
      _devices[incoming.ip] = incoming;
      unawaited(_refreshStatus(incoming));
      unawaited(_persist());
    } else {
      existing.mergeFrom(incoming);
    }
    notifyListeners();
  }

  Future<void> scan() async {
    _scanning = true;
    notifyListeners();
    discovery.resetEnrichmentCache();
    await discovery.discover(listenFor: const Duration(seconds: 5));
    // Let late UDP/mDNS replies trickle in, then drop the scanning flag.
    Timer(const Duration(seconds: 5), () {
      _scanning = false;
      notifyListeners();
    });
  }

  Future<void> addManual(String host) async {
    final h = host.trim();
    if (h.isEmpty) return;
    await discovery.addManual(h);
  }

  void removeDevice(String ip) {
    _devices.remove(ip);
    _persist();
    notifyListeners();
  }

  /// Enable/disable the RGB-chase test on every reachable FPP device at once
  /// (ports the POC's "Start/Stop Testing All").
  Future<int> setTestAll(bool enabled) async {
    final targets = _devices.values.where((d) => d.isFppDevice).toList();
    final results = await Future.wait(
      targets.map((d) => api.setTestMode(d.ip, enabled: enabled)),
    );
    await refreshAllStatus();
    return results.where((ok) => ok).length;
  }

  Future<void> clearKnownIps() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  Future<void> refreshAllStatus() async {
    await Future.wait(_devices.values.map(_refreshStatus));
    notifyListeners();
  }

  Future<void> _refreshStatus(FppDevice d) async {
    if (d.ip.isEmpty) return;
    final status = await api.systemStatus(d.ip, majorVersion: d.majorVersion);
    if (status != null) {
      d.applyStatus(status);
    } else {
      d.reachable = false;
    }
  }

  /// Refresh one device's status now and notify (used after a control action).
  Future<void> refreshOne(FppDevice d) async {
    await _refreshStatus(d);
    notifyListeners();
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) => refreshAllStatus());
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, FppDevice.encodeIpList(_devices.keys));
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _discoverySub?.cancel();
    discovery.dispose();
    api.close();
    super.dispose();
  }
}
