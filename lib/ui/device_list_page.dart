import 'package:flutter/material.dart';

import '../models/fpp_device.dart';
import '../services/device_manager.dart';
import 'device_detail_page.dart';

class DeviceListPage extends StatelessWidget {
  final DeviceManager manager;
  const DeviceListPage({super.key, required this.manager});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FPP Devices'),
        actions: [
          AnimatedBuilder(
            animation: manager,
            builder: (context, _) => manager.scanning
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Rescan network',
                    onPressed: manager.scan,
                  ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add device by IP',
            onPressed: () => _showAddDialog(context),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => _onMenu(context, v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'test_all', child: Text('Start Testing All')),
              PopupMenuItem(value: 'stop_all', child: Text('Stop Testing All')),
              PopupMenuItem(value: 'clear_ips', child: Text('Clear Stored IPs')),
            ],
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: manager,
        builder: (context, _) {
          final devices = manager.devices;
          if (devices.isEmpty) {
            return _EmptyState(scanning: manager.scanning, onScan: manager.scan);
          }
          return RefreshIndicator(
            onRefresh: manager.scan,
            child: ListView.separated(
              itemCount: devices.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _DeviceTile(
                device: devices[i],
                onTap: () => _openDetail(context, devices[i]),
                onRemove: () => manager.removeDevice(devices[i].ip),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _onMenu(BuildContext context, String value) async {
    final messenger = ScaffoldMessenger.of(context);
    switch (value) {
      case 'test_all':
        final n = await manager.setTestAll(true);
        messenger.showSnackBar(SnackBar(content: Text('Started test on $n device(s)')));
        break;
      case 'stop_all':
        final n = await manager.setTestAll(false);
        messenger.showSnackBar(SnackBar(content: Text('Stopped test on $n device(s)')));
        break;
      case 'clear_ips':
        await manager.clearKnownIps();
        messenger.showSnackBar(const SnackBar(content: Text('Cleared stored IPs')));
        break;
    }
  }

  void _openDetail(BuildContext context, FppDevice device) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DeviceDetailPage(manager: manager, device: device),
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    final controller = TextEditingController();
    final host = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add FPP Device'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Hostname or IP address',
            hintText: '192.168.1.50',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (host != null && host.trim().isNotEmpty) {
      await manager.addManual(host);
    }
  }
}

class _DeviceTile extends StatelessWidget {
  final FppDevice device;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  const _DeviceTile({required this.device, required this.onTap, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = device.hostname.isNotEmpty ? device.hostname : device.ip;
    return ListTile(
      onTap: onTap,
      leading: _StatusDot(device: device),
      title: Row(
        children: [
          Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
          if (device.prettyVersion.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('v${device.prettyVersion}', style: theme.textTheme.labelSmall),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text('${device.ip}'
              '${device.platform.isNotEmpty ? '  •  ${device.platform}' : ''}'
              '${device.mode.isNotEmpty ? '  •  ${device.mode}' : ''}'),
          const SizedBox(height: 2),
          _PlaybackLine(device: device),
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'remove') onRemove();
          if (v == 'open') onTap();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'open', child: Text('Open controls')),
          PopupMenuItem(value: 'remove', child: Text('Remove from list')),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final FppDevice device;
  const _StatusDot({required this.device});

  @override
  Widget build(BuildContext context) {
    Color color;
    if (!device.reachable) {
      color = Colors.grey;
    } else {
      switch (device.statusName.toLowerCase()) {
        case 'playing':
          color = Colors.green;
          break;
        case 'testing':
          color = Colors.amber;
          break;
        case 'paused':
        case 'stopping gracefully':
        case 'stopping gracefully after loop':
        case 'stopping now':
          color = Colors.orange;
          break;
        default:
          color = Colors.blueGrey;
      }
    }
    return Tooltip(
      message: device.reachable ? (device.statusName.isEmpty ? 'idle' : device.statusName) : 'unreachable',
      child: CircleAvatar(
        radius: 8,
        backgroundColor: color,
      ),
    );
  }
}

class _PlaybackLine extends StatelessWidget {
  final FppDevice device;
  const _PlaybackLine({required this.device});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary);
    if (!device.reachable) {
      return Text('unreachable', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey));
    }
    final status = device.statusName.isEmpty ? 'idle' : device.statusName;
    final detail = device.currentSequence.isNotEmpty
        ? device.currentSequence
        : (device.currentPlaylist.isNotEmpty ? device.currentPlaylist : '');
    return Text(
      detail.isNotEmpty ? '$status — $detail' : status,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool scanning;
  final VoidCallback onScan;
  const _EmptyState({required this.scanning, required this.onScan});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lightbulb_outline, size: 64, color: Theme.of(context).disabledColor),
          const SizedBox(height: 16),
          Text(scanning ? 'Scanning for FPP devices…' : 'No FPP devices found yet'),
          const SizedBox(height: 16),
          if (!scanning)
            FilledButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.search),
              label: const Text('Scan network'),
            ),
        ],
      ),
    );
  }
}
