import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:controller_viewer/models/controller_vendor.dart';
import 'package:controller_viewer/models/fpp_device.dart';

/// Build a synthetic FPPD ping (0x04) response packet for parse testing.
Uint8List _pingPacket({
  required List<int> ip,
  required String hostname,
  required String version,
  required String platform,
  int typeId = 0x01,
  int major = 8,
  int minor = 4,
  int mode = 2,
}) {
  final b = Uint8List(207);
  b[0] = 0x46; // F
  b[1] = 0x50; // P
  b[2] = 0x50; // P
  b[3] = 0x44; // D
  b[4] = 0x04; // ping
  b[7] = 2;
  b[8] = 0; // response subtype
  b[9] = typeId;
  b[10] = (major >> 8) & 0xFF;
  b[11] = major & 0xFF;
  b[12] = (minor >> 8) & 0xFF;
  b[13] = minor & 0xFF;
  b[14] = mode;
  b[15] = ip[0];
  b[16] = ip[1];
  b[17] = ip[2];
  b[18] = ip[3];
  _writeC(b, 19, hostname);
  _writeC(b, 84, version);
  _writeC(b, 125, platform);
  return b;
}

void _writeC(Uint8List b, int offset, String s) {
  final bytes = s.codeUnits;
  for (var i = 0; i < bytes.length && offset + i < b.length; i++) {
    b[offset + i] = bytes[i];
  }
}

/// Mirror of FppDiscovery's C-string reader for test purposes.
String readC(List<int> data, int start, int maxLen) {
  final end = (start + maxLen).clamp(0, data.length);
  final out = <int>[];
  for (var i = start; i < end; i++) {
    if (data[i] == 0) break;
    out.add(data[i]);
  }
  return String.fromCharCodes(out).trim();
}

void main() {
  group('FppDevice sysinfo parsing', () {
    test('parses modern /api/system/info keys', () {
      final d = FppDevice.fromSysInfo({
        'HostName': 'show-pi',
        'Version': '8.4',
        'fppModeString': 'player',
        'Platform': 'Raspberry Pi',
        'majorVersion': 8,
        'minorVersion': 4,
        'typeId': 0x01,
        'IPs': ['192.168.1.50'],
      });
      expect(d.hostname, 'show-pi');
      expect(d.ip, '192.168.1.50');
      expect(d.isFppDevice, isTrue);
      expect(d.isPlayer, isTrue);
      expect(d.prettyVersion, '8.4');
    });

    test('a remote controller (high typeId) is not treated as a player', () {
      final d = FppDevice.fromSysInfo({
        'hostname': 'falcon',
        'address': '192.168.1.99',
        'typeId': 0x91,
        'mode': 'remote',
      });
      expect(d.isFppDevice, isFalse);
      expect(d.isPlayer, isFalse);
    });

    test('applyStatus reads playback fields', () {
      final d = FppDevice(ip: '192.168.1.50');
      d.applyStatus({
        'status_name': 'playing',
        'volume': 70,
        'current_sequence': 'Carol.fseq',
        'seconds_played': '12',
        'seconds_remaining': '48',
        'current_playlist': {'playlist': 'MainShow'},
      });
      expect(d.statusName, 'playing');
      expect(d.volume, 70);
      expect(d.currentSequence, 'Carol.fseq');
      expect(d.currentPlaylist, 'MainShow');
      expect(d.secondsPlayed, 12);
      expect(d.reachable, isTrue);
    });
  });

  group('FPPD ping packet decode', () {
    test('decodes IP, version words, mode and strings at correct offsets', () {
      final pkt = _pingPacket(
        ip: [192, 168, 1, 50],
        hostname: 'show-pi',
        version: '8.4',
        platform: 'Raspberry Pi',
        major: 8,
        minor: 4,
        mode: 2,
      );
      final ip = '${pkt[15]}.${pkt[16]}.${pkt[17]}.${pkt[18]}';
      expect(ip, '192.168.1.50');
      expect((pkt[10] << 8) + pkt[11], 8);
      expect((pkt[12] << 8) + pkt[13], 4);
      expect(pkt[14], 2);
      expect(readC(pkt, 19, 65), 'show-pi');
      expect(readC(pkt, 84, 41), '8.4');
      expect(readC(pkt, 125, 41), 'Raspberry Pi');
    });
  });

  group('IP list persistence', () {
    test('round-trips through encode/decode', () {
      final ips = ['192.168.1.50', '192.168.1.51'];
      final encoded = FppDevice.encodeIpList(ips);
      expect(FppDevice.decodeIpList(encoded), ips);
      expect(FppDevice.decodeIpList(''), isEmpty);
      expect(FppDevice.decodeIpList(null), isEmpty);
    });
  });

  group('controller vendor classification', () {
    test('maps MultiSync typeId to vendor (per FPP controller plugin)', () {
      expect(vendorFromTypeId(0x01), ControllerVendor.fpp);
      expect(vendorFromTypeId(0x7F), ControllerVendor.fpp);
      expect(vendorFromTypeId(0x85), ControllerVendor.falconV3);
      expect(vendorFromTypeId(0x87), ControllerVendor.falconV3);
      expect(vendorFromTypeId(0x88), ControllerVendor.falconV4);
      expect(vendorFromTypeId(0x89), ControllerVendor.falconV4);
      expect(vendorFromTypeId(0xA0), ControllerVendor.genius);
      expect(vendorFromTypeId(0xAF), ControllerVendor.genius);
      expect(vendorFromTypeId(0xFB), ControllerVendor.wled);
      expect(vendorFromTypeId(0x00), ControllerVendor.unknown);
      expect(vendorFromTypeId(0x90), ControllerVendor.unknown);
    });

    test('device refreshVendor classifies from typeId', () {
      final falcon = FppDevice(ip: '192.168.1.60', typeId: 0x88)..refreshVendor();
      expect(falcon.vendor, ControllerVendor.falconV4);
      final genius = FppDevice(ip: '192.168.1.61', typeId: 0xA1)..refreshVendor();
      expect(genius.vendor, ControllerVendor.genius);
    });

    test('falls back to platform when typeId is absent', () {
      expect(vendorFromPlatform('Raspberry Pi 4'), ControllerVendor.fpp);
      expect(vendorFromPlatform('BeagleBone Black'), ControllerVendor.fpp);
      expect(vendorFromPlatform('something else'), ControllerVendor.unknown);
    });
  });
}
