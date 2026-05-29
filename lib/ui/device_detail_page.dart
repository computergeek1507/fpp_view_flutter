import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/fpp_device.dart';
import '../services/device_manager.dart';
import 'outputs_page.dart';

class DeviceDetailPage extends StatefulWidget {
  final DeviceManager manager;
  final FppDevice device;
  const DeviceDetailPage({super.key, required this.manager, required this.device});

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
  Timer? _poll;
  bool _busy = false;

  DeviceManager get manager => widget.manager;
  FppDevice get device => widget.device;

  @override
  void initState() {
    super.initState();
    manager.refreshOne(device);
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => manager.refreshOne(device));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _run(String label, Future<bool> Function() action) async {
    setState(() => _busy = true);
    final ok = await action();
    await manager.refreshOne(device);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '$label sent' : '$label failed'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = device.hostname.isNotEmpty ? device.hostname : device.ip;
    final canPlay = device.isPlayer || device.isFppDevice;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: 'Open web UI in browser',
            onPressed: () => _openWebUi(),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: manager,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _InfoCard(device: device),
              const SizedBox(height: 16),
              _SectionTitle('Testing'),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _run('Start test', () => manager.api.setTestMode(device.ip, enabled: true)),
                    icon: const Icon(Icons.flash_on),
                    label: const Text('Start Test'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _testModel,
                    icon: const Icon(Icons.view_in_ar),
                    label: const Text('Test Model'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run('Stop test', () => manager.api.setTestMode(device.ip, enabled: false)),
                    icon: const Icon(Icons.flash_off),
                    label: const Text('Stop Test'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SectionTitle('Sequence'),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _pickSequence,
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Play Sequence'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run('Stop sequence', () => manager.api.stopSequence(device.ip)),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Stop Sequence'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SectionTitle('Playlist'),
              if (!canPlay)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('This device is not in player mode.'),
                ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: (_busy || !canPlay) ? null : _pickPlaylist,
                    icon: const Icon(Icons.playlist_play),
                    label: const Text('Start Playlist'),
                  ),
                  OutlinedButton.icon(
                    onPressed: (_busy || !canPlay) ? null : () => _run('Stop gracefully', () => manager.api.stopGracefully(device.ip)),
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop Gracefully'),
                  ),
                  OutlinedButton.icon(
                    onPressed: (_busy || !canPlay) ? null : () => _run('Stop now', () => manager.api.stopNow(device.ip)),
                    icon: const Icon(Icons.stop_circle),
                    label: const Text('Stop Now'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SectionTitle('Device'),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OutputsPage(api: manager.api, device: device),
                      ),
                    ),
                    icon: const Icon(Icons.cable),
                    label: const Text('View Outputs'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _openWebUi,
                    icon: const Icon(Icons.open_in_browser),
                    label: const Text('Open Web UI'),
                  ),
                ],
              ),
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

  Future<void> _pickPlaylist() async {
    setState(() => _busy = true);
    final playlists = await manager.api.playlists(device.ip);
    if (!mounted) return;
    setState(() => _busy = false);
    if (playlists.isEmpty) {
      _toast('No playlists found');
      return;
    }
    final choice = await _pickFromList('Select Playlist', playlists);
    if (choice != null) {
      await _run('Start playlist', () => manager.api.startPlaylist(device.ip, choice));
    }
  }

  Future<void> _pickSequence() async {
    setState(() => _busy = true);
    final sequences = await manager.api.sequences(device.ip);
    if (!mounted) return;
    setState(() => _busy = false);
    if (sequences.isEmpty) {
      _toast('No sequences found');
      return;
    }
    final choice = await _pickFromList('Select Sequence', sequences);
    if (choice != null) {
      await _run('Play sequence', () => manager.api.startSequence(device.ip, choice));
    }
  }

  Future<void> _testModel() async {
    setState(() => _busy = true);
    final models = await manager.api.models(device.ip);
    if (!mounted) return;
    setState(() => _busy = false);
    if (models.isEmpty) {
      _toast('No models found');
      return;
    }
    final names = models.map((m) => m['name'] as String).toList();
    final choice = await _pickFromList('Select Model to Test', names);
    if (choice == null) return;
    final model = models.firstWhere((m) => m['name'] == choice);
    final start = model['startChannel'] as int;
    final end = start + (model['channelCount'] as int);
    // Run the RGB-chase test over just this model's channel range (POC parity).
    await _run('Test model', () => manager.api.setTestMode(device.ip, enabled: true, channelSet: '$start-$end'));
  }

  Future<void> _openWebUi() async {
    final uri = Uri.parse('http://${device.ip}');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) _toast('Could not open browser');
  }

  Future<String?> _pickFromList(String title, List<String> items) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title, style: Theme.of(ctx).textTheme.titleLarge),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(items[i]),
                  onTap: () => Navigator.of(ctx).pop(items[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
        : (device.statusName.isEmpty ? 'idle' : device.statusName);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('Status', status, theme, emphasize: true),
            _kv('IP', device.ip, theme),
            if (device.prettyVersion.isNotEmpty) _kv('Version', device.prettyVersion, theme),
            if (device.platform.isNotEmpty) _kv('Platform', device.platform, theme),
            if (device.mode.isNotEmpty) _kv('Mode', device.mode, theme),
            if (device.currentPlaylist.isNotEmpty) _kv('Playlist', device.currentPlaylist, theme),
            if (device.currentSequence.isNotEmpty) _kv('Sequence', device.currentSequence, theme),
            if (device.currentSong.isNotEmpty) _kv('Media', device.currentSong, theme),
            if (device.reachable && (device.secondsPlayed > 0 || device.secondsRemaining > 0))
              _kv('Time', '${_fmt(device.secondsPlayed)} / -${_fmt(device.secondsRemaining)}', theme),
            if (device.volume >= 0) _kv('Volume', '${device.volume}', theme),
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
          SizedBox(width: 92, child: Text(k, style: theme.textTheme.labelMedium)),
          Expanded(
            child: Text(
              v,
              style: emphasize
                  ? theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)
                  : theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
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
