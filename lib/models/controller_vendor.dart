/// The kinds of lighting controller this app can talk to.
enum ControllerVendor { fpp, falconV3, falconV4, genius, wled, unknown }

extension ControllerVendorInfo on ControllerVendor {
  /// Short label for badges/UI.
  String get label {
    switch (this) {
      case ControllerVendor.fpp:
        return 'FPP';
      case ControllerVendor.falconV3:
        return 'Falcon V3';
      case ControllerVendor.falconV4:
        return 'Falcon V4';
      case ControllerVendor.genius:
        return 'Genius';
      case ControllerVendor.wled:
        return 'WLED';
      case ControllerVendor.unknown:
        return 'Unknown';
    }
  }

  /// Whether this is a full FPP player (vs a pixel controller).
  bool get isFppPlayer => this == ControllerVendor.fpp;

  bool get isFalcon =>
      this == ControllerVendor.falconV3 || this == ControllerVendor.falconV4;
}

/// Classify a controller from the MultiSync ping `typeId` byte (data[9]).
///
/// Mapping mirrors the FalconChristmas/computergeek1507 FPP controller plugin
/// (controllerPlugin.cpp MakeController):
///   0x01–0x7F  -> FPP
///   0x85,0x87  -> Falcon V3
///   0x88,0x89  -> Falcon V4 (and V5)
///   0xA0–0xAF  -> Genius
///   0xFB       -> WLED
ControllerVendor vendorFromTypeId(int typeId) {
  if (typeId == 0x88 || typeId == 0x89) return ControllerVendor.falconV4;
  if (typeId == 0x85 || typeId == 0x87) return ControllerVendor.falconV3;
  if (typeId >= 0xA0 && typeId <= 0xAF) return ControllerVendor.genius;
  if (typeId == 0xFB) return ControllerVendor.wled;
  if (typeId > 0x00 && typeId < 0x80) return ControllerVendor.fpp;
  return ControllerVendor.unknown;
}

/// Best-effort classification when we only have HTTP sysinfo (no ping typeId),
/// e.g. for manually-added hosts. Falls back to FPP for FPP-like platforms.
ControllerVendor vendorFromPlatform(String platform, {int typeId = 0}) {
  if (typeId != 0) {
    final v = vendorFromTypeId(typeId);
    if (v != ControllerVendor.unknown) return v;
  }
  final p = platform.toLowerCase();
  if (p.contains('beaglebone') || p.contains('raspberry') || p.contains('fpp')) {
    return ControllerVendor.fpp;
  }
  return ControllerVendor.unknown;
}
