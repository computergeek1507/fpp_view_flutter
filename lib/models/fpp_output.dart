/// A single channel output row (pixel port, serial port, matrix, or other),
/// parsed from FPP's `/api/channel/output/*` responses. Ports the POC's
/// FPPOutput hierarchy (PixelOutput/SerialOutput/MatrixOutput/OtherOutput).
class FppOutput {
  final String portLabel;
  final String detail;

  FppOutput(this.portLabel, this.detail);

  /// Parse a `{channelOutputs:[...]}` document into a flat list of rows.
  static List<FppOutput> parseDocument(Map<String, dynamic> json) {
    final out = <FppOutput>[];
    final channelOutputs = json['channelOutputs'];
    if (channelOutputs is! List) return out;

    for (final co in channelOutputs.whereType<Map>()) {
      final type = (co['type'] ?? '').toString();
      final lower = type.toLowerCase();
      if (lower == 'bbb48string' || lower == 'rpiws281x') {
        final outputs = co['outputs'];
        if (outputs is List) {
          for (final o in outputs.whereType<Map>()) {
            out.add(_pixel(o.cast<String, dynamic>()));
          }
        }
      } else if (lower == 'bbbserial') {
        final outputs = co['outputs'];
        if (outputs is List) {
          for (final o in outputs.whereType<Map>()) {
            out.add(_serial(o.cast<String, dynamic>()));
          }
        }
      } else if (lower == 'ledpanelmatrix') {
        out.add(_matrix(co.cast<String, dynamic>()));
      } else {
        out.add(_other(co.cast<String, dynamic>()));
      }
    }
    return out;
  }

  static FppOutput _pixel(Map<String, dynamic> json) {
    final portNumber = _int(json['portNumber'], -1);
    final descriptions = <String>[];
    for (var i = 0; i < 6; i++) {
      final key = i == 0 ? 'virtualStrings' : 'virtualStrings$i';
      final vs = json[key];
      if (vs is! List) break;
      for (final s in vs.whereType<Map>()) {
        final desc = (s['description'] ?? '').toString();
        final remote = (s['smartRemote'] ?? '').toString();
        descriptions.add(remote.isNotEmpty ? '$desc:$remote' : desc);
      }
    }
    final detail = descriptions.where((d) => d.isNotEmpty).join(', ');
    return FppOutput('Pixel Port ${portNumber + 1}', detail.isEmpty ? '(empty)' : detail);
  }

  static FppOutput _serial(Map<String, dynamic> json) {
    final n = _int(json['outputNumber'], -1);
    final start = _int(json['startChannel'], -1);
    final count = _int(json['channelCount'], 0);
    return FppOutput('Serial Port ${n + 1}', 'Start Channel: $start, Channel Count: $count');
  }

  static FppOutput _matrix(Map<String, dynamic> json) {
    final subType = (json['subType'] ?? '').toString();
    final w = _int(json['panelWidth'], 0);
    final h = _int(json['panelHeight'], 0);
    final start = _int(json['startChannel'], -1);
    final count = _int(json['channelCount'], 0);
    final color = (json['colorOrder'] ?? '').toString();
    return FppOutput(
      'Panel Matrix',
      '$subType  H:${h}xW:$w  Start: $start  Count: $count  Color: $color',
    );
  }

  static FppOutput _other(Map<String, dynamic> json) {
    final type = (json['type'] ?? '').toString();
    final start = _int(json['startChannel'], -1);
    final count = _int(json['channelCount'], 0);
    return FppOutput(type.isEmpty ? 'Output' : type, 'Start Channel: $start, Channel Count: $count');
  }

  static int _int(dynamic v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }
}
