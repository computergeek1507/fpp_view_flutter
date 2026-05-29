import 'package:http/http.dart' as http;

import '../../models/controller_vendor.dart';
import '../../models/fpp_device.dart';
import '../fpp_api.dart';
import 'controller_client.dart';
import 'falcon_v3_client.dart';
import 'falcon_v4_client.dart';
import 'fpp_controller_client.dart';
import 'genius_client.dart';
import 'wled_client.dart';

/// Build the right [ControllerClient] for a discovered device based on its
/// classified vendor. Returns null for unknown vendors (no control client).
ControllerClient? controllerClientFor(
  FppDevice device, {
  FppApi? fppApi,
  http.Client? httpClient,
}) {
  switch (device.vendor) {
    case ControllerVendor.fpp:
      return FppControllerClient(device.ip,
          api: fppApi, majorVersion: device.majorVersion, platform: device.platform);
    case ControllerVendor.falconV4:
      return FalconV4Client(device.ip, client: httpClient);
    case ControllerVendor.falconV3:
      return FalconV3Client(device.ip, client: httpClient);
    case ControllerVendor.genius:
      return GeniusClient(device.ip, client: httpClient);
    case ControllerVendor.wled:
      return WledClient(device.ip, client: httpClient);
    case ControllerVendor.unknown:
      return null;
  }
}
