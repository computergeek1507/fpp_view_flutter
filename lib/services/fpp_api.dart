import 'dart:convert';
import 'package:http/http.dart' as http;

/// Thin client over the FPP HTTP REST API.
///
/// Endpoints used (FPP 2.x–8.x):
///   GET  /api/system/info               -> device identity
///   GET  /api/system/status             -> playback status (FPP 5+)
///   GET  /fppjson.php?command=getFPPstatus  -> legacy status (FPP <5)
///   GET  /api/fppd/multiSyncSystems     -> peers known to this device
///   GET  /api/playlists                 -> playlist names
///   GET  /api/sequence                  -> sequence (.fseq) names
///   POST /api/command                   -> run a named FPP command
///   POST /api/testmode                  -> enable/disable test pattern
///   GET  /api/playlists/stop|stopgracefully
class FppApi {
  final http.Client _client;
  final Duration timeout;

  FppApi({http.Client? client, this.timeout = const Duration(seconds: 4)})
      : _client = client ?? http.Client();

  Uri _u(String ip, String path) => Uri.parse('http://$ip$path');

  Future<Map<String, dynamic>?> systemInfo(String ip) async {
    final body = await _getJson(_u(ip, '/api/system/info'));
    return body is Map<String, dynamic> ? body : null;
  }

  /// Returns a status map, falling back to the legacy endpoint for old FPP.
  Future<Map<String, dynamic>?> systemStatus(String ip, {int majorVersion = 99}) async {
    if (majorVersion >= 5 || majorVersion < 0) {
      final body = await _getJson(_u(ip, '/api/system/status'));
      if (body is Map<String, dynamic>) return body;
    }
    final legacy = await _getJson(_u(ip, '/fppjson.php?command=getFPPstatus'));
    return legacy is Map<String, dynamic> ? legacy : null;
  }

  /// Peers this device knows about via MultiSync. Shape: {"systems":[...]}.
  Future<List<Map<String, dynamic>>> multiSyncSystems(String ip) async {
    final body = await _getJson(_u(ip, '/api/fppd/multiSyncSystems'));
    if (body is Map && body['systems'] is List) {
      return (body['systems'] as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    return [];
  }

  Future<List<String>> playlists(String ip) async {
    final body = await _getJson(_u(ip, '/api/playlists'));
    if (body is List) return body.map((e) => e.toString()).toList();
    return [];
  }

  Future<List<String>> sequences(String ip) async {
    final body = await _getJson(_u(ip, '/api/sequence'));
    if (body is List) return body.map((e) => e.toString()).toList();
    return [];
  }

  /// Returns models as {name, startChannel, channelCount}. Used to test a
  /// single model's channel range (ports the POC's SetTestingModel/TestModel).
  Future<List<Map<String, dynamic>>> models(String ip) async {
    final body = await _getJson(_u(ip, '/api/models'));
    if (body is List) {
      return body.whereType<Map>().map((m) {
        return {
          'name': (m['Name'] ?? '').toString(),
          'startChannel': _toInt(m['StartChannel'], 1),
          'channelCount': _toInt(m['ChannelCount'], 1),
        };
      }).where((m) => (m['name'] as String).isNotEmpty).toList();
    }
    return [];
  }

  static int _toInt(dynamic v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  /// Fetch the channel-output config documents. The relevant pixel-string doc
  /// is platform-specific (BBB vs Pi), so we gather all three the POC used and
  /// let the parser merge them.
  Future<List<Map<String, dynamic>>> channelOutputDocs(String ip, {String platform = ''}) async {
    final pixelFile = platform.toLowerCase().contains('beagle') ? 'co-bbbStrings' : 'co-pixelStrings';
    final paths = [
      '/api/channel/output/$pixelFile',
      '/api/channel/output/co-other',
      '/api/channel/output/channelOutputsJSON',
    ];
    final docs = <Map<String, dynamic>>[];
    for (final p in paths) {
      final body = await _getJson(_u(ip, p));
      if (body is Map<String, dynamic>) docs.add(body);
    }
    return docs;
  }

  /// Start a playlist by name. `repeat` loops it; `ifNotRunning` won't restart
  /// if already playing. Matches the "Start Playlist" command arg order.
  Future<bool> startPlaylist(String ip, String name,
      {bool repeat = true, bool ifNotRunning = false}) {
    return runCommand(ip, 'Start Playlist', [
      name,
      repeat.toString(),
      ifNotRunning.toString(),
    ]);
  }

  Future<bool> stopGracefully(String ip) => _getOk(_u(ip, '/api/playlists/stopgracefully'));
  Future<bool> stopNow(String ip) => _getOk(_u(ip, '/api/playlists/stop'));

  /// Play a single sequence (.fseq). FPP's own UI uses this testing endpoint;
  /// `startSecond` is the offset to begin at.
  Future<bool> startSequence(String ip, String sequenceName, {int startSecond = 0}) {
    final path = '/api/sequence/${Uri.encodeComponent(sequenceName)}/start/$startSecond';
    return _getOk(_u(ip, path));
  }

  Future<bool> stopSequence(String ip) => _getOk(_u(ip, '/api/sequence/current/stop'));

  /// Enable/disable the RGB-chase test pattern over a channel range.
  Future<bool> setTestMode(String ip, {required bool enabled, String channelSet = '1-1048576'}) {
    final payload = jsonEncode({
      'cycleMS': 500,
      'enabled': enabled ? 1 : 0,
      'channelSet': channelSet,
      'channelSetType': 'channelRange',
      'mode': 'RGBChase',
      'subMode': 'RGBChase-RGB',
      'colorPattern': 'FF000000FF000000FF',
    });
    return _postOk(_u(ip, '/api/testmode'), payload);
  }

  /// Run a named FPP command via POST /api/command.
  Future<bool> runCommand(String ip, String command, List<String> args) {
    final payload = jsonEncode({'command': command, 'args': args});
    return _postOk(_u(ip, '/api/command'), payload);
  }

  // ---- low level helpers ----

  Future<dynamic> _getJson(Uri uri) async {
    try {
      final r = await _client.get(uri).timeout(timeout);
      if (r.statusCode == 200 && r.body.isNotEmpty) {
        return jsonDecode(r.body);
      }
    } catch (_) {/* unreachable / non-FPP / timeout */}
    return null;
  }

  Future<bool> _getOk(Uri uri) async {
    try {
      final r = await _client.get(uri).timeout(timeout);
      return r.statusCode >= 200 && r.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _postOk(Uri uri, String body) async {
    try {
      final r = await _client
          .post(uri, headers: {'Content-Type': 'application/json; charset=utf-8'}, body: body)
          .timeout(timeout);
      return r.statusCode >= 200 && r.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  void close() => _client.close();
}
