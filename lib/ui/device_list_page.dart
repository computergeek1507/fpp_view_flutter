import 'package:flutter/material.dart';

import '../models/controller_vendor.dart';
import '../models/fpp_device.dart';
import '../services/device_manager.dart';
import 'controller_detail_page.dart';
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
          return Column(
            children: [
              if (!manager.supportsNetworkDiscovery)
                MaterialBanner(
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  leading: const Icon(Icons.info_outline),
                  content: const Text(
                    'Add devices manually by IP using the + button.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => _showAddDialog(context),
                      child: const Text('Add device'),
                    ),
                  ],
                ),
              Expanded(
                child: devices.isEmpty
                    ? _EmptyState(
                        scanning: manager.scanning,
                        canScan: manager.supportsNetworkDiscovery,
                        onScan: manager.scan,
                        onAdd: () => _showAddDialog(context),
                      )
                    : RefreshIndicator(
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
                      ),
              ),
            ],
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
    // FPP players get the full playback control page; pixel controllers
    // (Falcon/Genius/WLED) get the monitor + test + outputs page.
    final isFpp = device.vendor == ControllerVendor.fpp ||
        device.vendor == ControllerVendor.unknown;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => isFpp
            ? DeviceDetailPage(manager: manager, device: device)
            : ControllerDetailPage(manager: manager, device: device),
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

class _VendorBadge extends StatelessWidget {
  final ControllerVendor vendor;
  const _VendorBadge({required this.vendor});

  static const _colors = {
    ControllerVendor.fpp: Color(0xFF1565C0),
    ControllerVendor.falconV3: Color(0xFF6A1B9A),
    ControllerVendor.falconV4: Color(0xFF8E24AA),
    ControllerVendor.genius: Color(0xFF2E7D32),
    ControllerVendor.wled: Color(0xFFEF6C00),
    ControllerVendor.unknown: Color(0xFF546E7A),
  };

  @override
  Widget build(BuildContext context) {
    if (vendor == ControllerVendor.unknown) return const SizedBox.shrink();
    final color = _colors[vendor] ?? const Color(0xFF546E7A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(vendor.label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
    );
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
          _VendorBadge(vendor: device.vendor),
          if (device.prettyVersion.isNotEmpty) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('v${device.prettyVersion}', style: theme.textTheme.labelSmall),
            ),
          ],
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
  final bool canScan;
  final VoidCallback onScan;
  final VoidCallback onAdd;
  const _EmptyState({
    required this.scanning,
    required this.canScan,
    required this.onScan,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lightbulb_outline, size: 64, color: Theme.of(context).disabledColor),
          const SizedBox(height: 16),
          Text(scanning
              ? 'Scanning for FPP devices…'
              : (canScan ? 'No FPP devices found yet' : 'Add an FPP device by IP to get started')),
          const SizedBox(height: 16),
          if (!scanning && canScan)
            FilledButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.search),
              label: const Text('Scan network'),
            ),
          if (!canScan)
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add device by IP'),
            ),
        ],
      ),
    );
  }
}
