import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/controller_vendor.dart';
import 'controller_client.dart';

/// WLED: the `/json` API. Test mode = set every segment to effect 34 and turn
/// the strip on. Verified against the FPP controller plugin (wled_controller.cpp).
class WledClient extends ControllerClient {
  final http.Client _http;
  final Duration timeout;

  WledClient(super.ip, {http.Client? client, this.timeout = const Duration(seconds: 5)})
      : _http = client ?? http.Client();

  @override
  ControllerVendor get vendor => ControllerVendor.wled;
  @override
  bool get supportsOutputConfig => false;

  Future<dynamic> _get(String path) async {
    try {
      final r = await _http.get(Uri.parse('http://$ip$path')).timeout(timeout);
      if (r.statusCode == 200 && r.body.isNotEmpty) return jsonDecode(r.body);
    } catch (_) {}
    return null;
  }

  Future<bool> _postJson(String path, Map<String, dynamic> body) async {
    try {
      final r = await _http
          .post(Uri.parse('http://$ip$path'),
              headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(timeout);
      return r.statusCode >= 200 && r.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ControllerStatus> fetchStatus() async {
    final info = await _get('/json/info');
    final state = await _get('/json/state');
    if (info is! Map && state is! Map) return ControllerStatus.unreachable();
    final i = (info is Map) ? info : const {};
    final s = (state is Map) ? state : const {};
    final segs = (s['seg'] is List) ? (s['seg'] as List).length : 0;
    final extra = <String, String>{};
    if (i['leds'] is Map && (i['leds'] as Map)['count'] != null) {
      extra['LEDs'] = '${(i['leds'] as Map)['count']}';
    }
    return ControllerStatus(
      reachable: true,
      inTestMode: s['on'] == true,
      model: (i['arch'] ?? 'WLED').toString(),
      firmware: (i['ver'] ?? '').toString(),
      mode: (i['name'] ?? '').toString(),
      portCount: segs,
      extra: extra,
    );
  }

  @override
  Future<bool> testOn() async {
    final state = await _get('/json/state');
    final segCount = (state is Map && state['seg'] is List) ? (state['seg'] as List).length : 1;
    final segs = List.generate(segCount, (_) => {'fx': 34});
    final ok1 = await _postJson('/json', {'seg': segs});
    final ok2 = await _postJson('/json', {'on': true});
    return ok1 && ok2;
  }

  @override
  Future<bool> testOff() => _postJson('/json', {'on': false});
}
