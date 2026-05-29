import '../../models/controller_vendor.dart';
import '../../models/fpp_output.dart';
import '../fpp_api.dart';
import 'controller_client.dart';

/// FPP player, exposed through the common ControllerClient interface so the
/// unified list/detail can treat it like any other controller. Rich playback
/// control (playlists/sequences) still lives in FppApi + the FPP detail view.
class FppControllerClient extends ControllerClient {
  final FppApi api;
  final int majorVersion;
  final String platform;

  FppControllerClient(super.ip, {FppApi? api, this.majorVersion = 99, this.platform = ''})
      : api = api ?? FppApi();

  @override
  ControllerVendor get vendor => ControllerVendor.fpp;
  @override
  bool get supportsOutputConfig => true;

  @override
  Future<ControllerStatus> fetchStatus() async {
    final info = await api.systemInfo(ip);
    final status = await api.systemStatus(ip, majorVersion: majorVersion);
    if (info == null && status == null) return ControllerStatus.unreachable();
    final test = status?['status_name']?.toString().toLowerCase() == 'testing';
    return ControllerStatus(
      reachable: true,
      inTestMode: test,
      model: (info?['HostName'] ?? info?['hostname'] ?? '').toString(),
      firmware: (info?['Version'] ?? info?['version'] ?? '').toString(),
      mode: (status?['mode_name'] ?? info?['fppModeString'] ?? '').toString(),
    );
  }

  @override
  Future<List<ControllerOutput>> fetchOutputs() async {
    final docs = await api.channelOutputDocs(ip, platform: platform);
    final all = <FppOutput>[];
    for (final doc in docs) {
      all.addAll(FppOutput.parseDocument(doc));
    }
    return all.map((o) => ControllerOutput(o.portLabel, o.detail)).toList();
  }

  @override
  Future<bool> testOn() => api.setTestMode(ip, enabled: true);
  @override
  Future<bool> testOff() => api.setTestMode(ip, enabled: false);
}
