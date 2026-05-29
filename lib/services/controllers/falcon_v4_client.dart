import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../models/controller_vendor.dart';
import 'controller_client.dart';

/// Falcon V4/V5: single `POST /api` JSON endpoint with a {T,M,B,E,I,P} envelope.
/// Test-mode command shapes verified against the FPP controller plugin
/// (falconV4_controller.cpp). String count comes from the `/status.xml` np tag.
class FalconV4Client extends ControllerClient {
  final http.Client _http;
  final Duration timeout;

  FalconV4Client(super.ip, {http.Client? client, this.timeout = const Duration(seconds: 5)})
      : _http = client ?? http.Client();

  @override
  ControllerVendor get vendor => ControllerVendor.falconV4;
  @override
  bool get supportsPerPortTest => true;
  @override
  bool get supportsOutputConfig => true;

  Uri get _api => Uri.parse('http://$ip/api');

  Future<Map<String, dynamic>?> _post(Map<String, dynamic> body) async {
    try {
      final r = await _http
          .post(_api, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(timeout);
      if (r.statusCode == 200 && r.body.isNotEmpty) {
        final j = jsonDecode(r.body);
        if (j is Map<String, dynamic>) return j;
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic> _query(String method) =>
      {'T': 'Q', 'M': method, 'B': 0, 'E': 0, 'I': 0, 'P': {}};

  @override
  Future<ControllerStatus> fetchStatus() async {
    final res = await _post(_query('ST'));
    if (res == null) return ControllerStatus.unreachable();
    final p = (res['P'] is Map) ? (res['P'] as Map).cast<String, dynamic>() : <String, dynamic>{};
    // "TS" present and != 0 means a test is running.
    bool? test;
    if (p.containsKey('TS')) test = _asInt(p['TS']) != 0;
    final extra = <String, String>{};
    void add(String key, String label, {String suffix = ''}) {
      if (p[key] != null) extra[label] = '${p[key]}$suffix';
    }
    add('U', 'Uptime', suffix: 's');
    add('C', 'MAC');
    if (p['T1'] != null) extra['Temp'] = '${p['T1']}';
    if (p['V1'] != null) extra['Voltage'] = '${p['V1']}';
    return ControllerStatus(
      reachable: true,
      inTestMode: test,
      model: _model(p),
      firmware: (p['V'] ?? '').toString(),
      mode: _mode(_asInt(p['O'])),
      portCount: _asInt(p['P']) > 0 ? _asInt(p['P']) : await _stringCount(),
      extra: extra,
    );
  }

  String _model(Map<String, dynamic> p) {
    final br = _asInt(p['BR']);
    return br > 0 ? 'F$br' : (p['N'] ?? 'Falcon').toString();
  }

  String _mode(int o) {
    switch (o) {
      case 0:
        return 'E1.31/ArtNet';
      case 2:
        return 'DDP';
      case 3:
        return 'remote';
      case 4:
        return 'master';
      case 5:
        return 'player';
      default:
        return '';
    }
  }

  @override
  Future<List<ControllerOutput>> fetchOutputs() async {
    final out = <ControllerOutput>[];
    // Strings come in batches; loop until F==1 (final).
    var batch = 0;
    var guard = 0;
    while (guard++ < 32) {
      final res = await _post({'T': 'Q', 'M': 'SP', 'B': batch, 'E': 0, 'I': 0, 'P': {}});
      if (res == null) break;
      final p = (res['P'] is Map) ? res['P'] as Map : const {};
      final arr = (p['A'] is List) ? p['A'] as List : const [];
      for (final s in arr.whereType<Map>()) {
        final port = _asInt(s['p']) + 1;
        final pixels = _asInt(s['n']);
        final uni = _asInt(s['u']);
        final name = (s['nm'] ?? '').toString();
        out.add(ControllerOutput(
          'Port $port${name.isNotEmpty ? ' — $name' : ''}',
          '$pixels px${uni > 0 ? '  •  U$uni' : ''}  •  ${_colourOrder(_asInt(s['o']))}',
        ));
      }
      if (_asInt(res['F']) == 1 || arr.isEmpty) break;
      batch++;
    }
    return out;
  }

  String _colourOrder(int o) {
    const orders = ['RGB', 'RBG', 'GRB', 'GBR', 'BRG', 'BGR'];
    return (o >= 0 && o < orders.length) ? orders[o] : 'RGB';
  }

  Future<int> _stringCount() async {
    try {
      final r = await _http.get(Uri.parse('http://$ip/status.xml')).timeout(timeout);
      if (r.statusCode == 200) {
        final m = RegExp(r'<np>(\d+)</np>').firstMatch(r.body);
        if (m != null) return int.tryParse(m.group(1)!) ?? 16;
      }
    } catch (_) {}
    return 16;
  }

  @override
  Future<bool> testOn() async {
    final outputs = await _stringCount();
    const perCall = 5;
    final calls = (outputs / perCall).ceil();
    var ok = true;
    for (var j = 0; j < calls; j++) {
      final start = j * perCall;
      final a = <Map<String, int>>[];
      for (var i = 0; i < perCall && (start + i) < outputs; i++) {
        a.add({'P': start + i, 'R': 0, 'S': 0});
      }
      final body = {
        'T': 'S', 'M': 'TS', 'B': j, 'E': 16, 'I': start,
        'P': {'E': 'Y', 'D': 'Y', 'S': 20, 'Y': 1, 'A': a},
      };
      ok = (await _post(body)) != null && ok;
    }
    return ok;
  }

  @override
  Future<bool> testOff() async {
    final body = {
      'T': 'S', 'M': 'TS', 'B': 0, 'E': 16, 'I': 0,
      'P': {'E': 'N', 'D': 'Y', 'S': 20, 'Y': 1, 'A': []},
    };
    return (await _post(body)) != null;
  }

  @override
  Future<bool> testPort(int port) async {
    // Prime, then enable just this port (port is 1-based; controller is 0-based).
    await _post({
      'T': 'S', 'M': 'TS', 'B': 0, 'E': 0, 'I': 0,
      'P': {'E': 'Y', 'D': 'N', 'S': 20, 'Y': 1, 'A': []},
    });
    final body = {
      'T': 'S', 'M': 'TS', 'B': 0, 'E': 1, 'I': 0,
      'P': {
        'E': 'Y', 'D': 'N', 'S': 20, 'Y': 1,
        'A': [{'P': math.max(0, port - 1), 'R': 0, 'S': 0}],
      },
    };
    return (await _post(body)) != null;
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}
