import '../../models/controller_vendor.dart';

/// A single output/string row read from a controller (vendor-neutral).
class ControllerOutput {
  final String label;
  final String detail;
  ControllerOutput(this.label, this.detail);
}

/// Live monitoring snapshot from a controller, normalized across vendors.
class ControllerStatus {
  final bool reachable;
  final bool? inTestMode;
  final String model;
  final String firmware;
  final String mode;
  final int portCount;
  final Map<String, String> extra; // vendor-specific extras (temps, volts...)

  ControllerStatus({
    this.reachable = false,
    this.inTestMode,
    this.model = '',
    this.firmware = '',
    this.mode = '',
    this.portCount = 0,
    this.extra = const {},
  });

  static ControllerStatus unreachable() => ControllerStatus(reachable: false);
}

/// Vendor-agnostic interface for talking to a lighting controller over HTTP.
///
/// Each vendor implementation encapsulates that hardware's quirks (Falcon's
/// /api JSON envelope, Genius's /api/test_mode_*, WLED's /json, etc.). Mirrors
/// the ControllerBase design in the FPP controller plugin.
abstract class ControllerClient {
  final String ip;
  ControllerClient(this.ip);

  ControllerVendor get vendor;

  /// Whether this vendor exposes a usable test/identify mode.
  bool get supportsTestMode => true;

  /// Whether this vendor can test a single port/output.
  bool get supportsPerPortTest => false;

  /// Whether this vendor exposes a readable output configuration.
  bool get supportsOutputConfig => false;

  /// Read a normalized monitoring snapshot.
  Future<ControllerStatus> fetchStatus();

  /// Read the per-output configuration (empty if unsupported).
  Future<List<ControllerOutput>> fetchOutputs() async => const [];

  /// Enable the controller's test pattern on all outputs.
  Future<bool> testOn();

  /// Disable the test pattern.
  Future<bool> testOff();

  /// Enable test on a single 1-based port (no-op false if unsupported).
  Future<bool> testPort(int port) async => false;
}
