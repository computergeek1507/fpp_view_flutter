import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/controller_vendor.dart';
import 'controller_client.dart';

/// Genius (HolidayCoro / "Experience"): JSON `/api/state` + `/api/config`,
/// test via `/api/test_mode_enable|disable` + `/api/set_test_elements`.
/// Verified against the FPP controller plugin (genius_controller.cpp) and
/// xLights Experience.cpp.
class GeniusClient extends ControllerClient {
  final http.Client _http;
  final Duration timeout;

  GeniusClient(super.ip, {http.Client? client, this.timeout = const Duration(seconds: 5)})
      : _http = client ?? http.Client();

  @override
  ControllerVendor get vendor => ControllerVendor.genius;
  @override
  bool get supportsPerPortTest => true;
  @override
  bool get supportsOutputConfig => true;

  Future<dynamic> _get(String path) async {
    try {
      final r = await _http
          .get(Uri.parse('http://$ip$path'), headers: {'Content-Type': 'application/json'})
          .timeout(timeout);
      if (r.statusCode == 200 && r.body.isNotEmpty) return jsonDecode(r.body);
    } catch (_) {}
    return null;
  }

  @override
  Future<ControllerStatus> fetchStatus() async {
    final state = await _get('/api/state');
    if (state is! Map) return ControllerStatus.unreachable();
    final sys = (state['system'] is Map) ? state['system'] as Map : const {};
    final localOut = _asInt(sys['number_of_local_outputs']);
    final lrPix = _asInt(sys['number_of_long_range_pixel_ports']);
    final lrDmx = _asInt(sys['number_of_long_range_dmx_ports']);
    final extra = <String, String>{};
    if (lrPix > 0) extra['Long-range pixel ports'] = '$lrPix';
    if (lrDmx > 0) extra['Long-range DMX ports'] = '$lrDmx';
    return ControllerStatus(
      reachable: true,
      inTestMode: sys['test_mode_enabled'] == true,
      model: (sys['controller_model_name'] ?? 'Genius').toString(),
      firmware: (sys['firmware_version'] ?? '').toString(),
      mode: (sys['controller_line'] ?? '').toString(),
      portCount: localOut,
      extra: extra,
    );
  }

  @override
  Future<List<ControllerOutput>> fetchOutputs() async {
    final cfg = await _get('/api/config');
    if (cfg is! Map) return const [];
    final out = <ControllerOutput>[];
    final outputs = (cfg['outputs'] is List) ? cfg['outputs'] as List : const [];
    var idx = 0;
    for (final o in outputs.whereType<Map>()) {
      idx++;
      final disabled = o['disabled'] == true;
      final vs = (o['virtual_strings'] is List) ? o['virtual_strings'] as List : const [];
      if (disabled && vs.isEmpty) continue;
      final total = vs.whereType<Map>().fold<int>(0, (sum, s) {
        final sc = _asInt(s['sc']);
        final ec = _asInt(s['ec']);
        return sum + (ec >= sc ? (ec - sc + 1) : _asInt(s['ec']));
      });
      out.add(ControllerOutput(
        'Output $idx',
        disabled ? 'disabled' : '${vs.length} string(s)${total > 0 ? '  •  ~$total ch' : ''}',
      ));
    }
    return out;
  }

  @override
  Future<bool> testOn() async {
    final a = await _get('/api/test_mode_enable');
    final b = await _get('/api/set_test_elements?selected_elements={elements:["all"]}');
    return a != null && b != null;
  }

  @override
  Future<bool> testOff() async => (await _get('/api/test_mode_disable')) != null;

  @override
  Future<bool> testPort(int port) async {
    final a = await _get('/api/test_mode_enable');
    final b = await _get(
        '/api/set_test_elements?selected_elements={elements:[["o","${port - 1}"]]}');
    return a != null && b != null;
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}
