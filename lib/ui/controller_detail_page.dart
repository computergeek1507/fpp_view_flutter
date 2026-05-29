import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/controller_vendor.dart';
import '../models/fpp_device.dart';
import '../services/controllers/controller_client.dart';
import '../services/device_manager.dart';

/// Monitor + control page for non-FPP pixel controllers (Falcon V3/V4, Genius,
/// WLED). Shows live status, output config, and test-mode controls via the
/// device's vendor [ControllerClient].
class ControllerDetailPage extends StatefulWidget {
  final DeviceManager manager;
  final FppDevice device;
  const ControllerDetailPage({super.key, required this.manager, required this.device});

  @override
  State<ControllerDetailPage> createState() => _ControllerDetailPageState();
}

class _ControllerDetailPageState extends State<ControllerDetailPage> {
  late final ControllerClient? _client;
  Timer? _poll;
  bool _busy = false;
  List<ControllerOutput>? _outputs;

  FppDevice get device => widget.device;

  @override
  void initState() {
    super.initState();
    _client = widget.manager.clientFor(device);
    widget.manager.refreshOne(device);
    _loadOutputs();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => widget.manager.refreshOne(device));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _loadOutputs() async {
    final client = _client;
    if (client == null || !client.supportsOutputConfig) return;
    final outs = await client.fetchOutputs();
    if (mounted) setState(() => _outputs = outs);
  }

  Future<void> _run(String label, Future<bool> Function() action) async {
    setState(() => _busy = true);
    final ok = await action();
    await widget.manager.refreshOne(device);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '$label sent' : '$label failed'), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = device.hostname.isNotEmpty ? device.hostname : device.ip;
    final client = _client;
    return Scaffold(
      appBar: AppBar(
        title: Text('$title  •  ${device.vendor.label}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: 'Open web UI',
            onPressed: _openWebUi,
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.manager,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _InfoCard(device: device),
              if (client == null)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No control client available for this controller type.'),
                )
              else ...[
                const SizedBox(height: 16),
                _SectionTitle('Testing'),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _run('Start test', client.testOn),
                      icon: const Icon(Icons.flash_on),
                      label: const Text('Start Test'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _run('Stop test', client.testOff),
                      icon: const Icon(Icons.flash_off),
                      label: const Text('Stop Test'),
                    ),
                    if (client.supportsPerPortTest)
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _testPort,
                        icon: const Icon(Icons.linear_scale),
                        label: const Text('Test Port'),
                      ),
                  ],
                ),
                if (client.supportsOutputConfig) ...[
                  const SizedBox(height: 16),
                  _SectionTitle('Outputs'),
                  _OutputsList(outputs: _outputs, onRefresh: _loadOutputs),
                ],
              ],
              if (_busy) ...[
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _testPort() async {
    final ports = device.portCount > 0 ? device.portCount : 16;
    final choice = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Select port', style: Theme.of(ctx).textTheme.titleLarge),
            ),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 72, childAspectRatio: 1.6, crossAxisSpacing: 8, mainAxisSpacing: 8),
                itemCount: ports,
                itemBuilder: (_, i) => OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(i + 1),
                  child: Text('${i + 1}'),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (choice != null) {
      await _run('Test port $choice', () => _client!.testPort(choice));
    }
  }

  Future<void> _openWebUi() async {
    final ok = await launchUrl(Uri.parse('http://${device.ip}'),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open browser')));
    }
  }
}

class _OutputsList extends StatelessWidget {
  final List<ControllerOutput>? outputs;
  final Future<void> Function() onRefresh;
  const _OutputsList({required this.outputs, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (outputs == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Loading outputs…'),
      );
    }
    if (outputs!.isEmpty) {
      return Row(
        children: [
          const Text('No outputs reported.'),
          const Spacer(),
          TextButton(onPressed: onRefresh, child: const Text('Retry')),
        ],
      );
    }
    return Card(
      child: Column(
        children: [
          for (final o in outputs!)
            ListTile(
              dense: true,
              leading: const Icon(Icons.cable, size: 20),
              title: Text(o.label),
              subtitle: Text(o.detail),
            ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final FppDevice device;
  const _InfoCard({required this.device});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = !device.reachable
        ? 'unreachable'
        : (device.inTestMode == true ? 'testing' : 'online');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('Status', status, theme, emphasize: true),
            _kv('Vendor', device.vendor.label, theme),
            _kv('IP', device.ip, theme),
            if (device.prettyVersion.isNotEmpty) _kv('Firmware', device.prettyVersion, theme),
            if (device.mode.isNotEmpty) _kv('Mode', device.mode, theme),
            if (device.portCount > 0) _kv('Ports', '${device.portCount}', theme),
            for (final e in device.extra.entries) _kv(e.key, e.value, theme),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v, ThemeData theme, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(k, style: theme.textTheme.labelMedium)),
          Expanded(
            child: Text(v,
                style: emphasize
                    ? theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)
                    : theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
