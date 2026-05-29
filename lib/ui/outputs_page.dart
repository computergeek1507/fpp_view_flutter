import 'package:flutter/material.dart';

import '../models/fpp_device.dart';
import '../models/fpp_output.dart';
import '../services/fpp_api.dart';

/// Shows the channel-output wiring for a device (pixel/serial/matrix/other),
/// ported from the POC's WiringViewActivity.
class OutputsPage extends StatefulWidget {
  final FppApi api;
  final FppDevice device;
  const OutputsPage({super.key, required this.api, required this.device});

  @override
  State<OutputsPage> createState() => _OutputsPageState();
}

class _OutputsPageState extends State<OutputsPage> {
  List<FppOutput>? _outputs;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final docs = await widget.api.channelOutputDocs(widget.device.ip, platform: widget.device.platform);
    final all = <FppOutput>[];
    for (final doc in docs) {
      all.addAll(FppOutput.parseDocument(doc));
    }
    if (!mounted) return;
    setState(() {
      _outputs = all;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.device.hostname.isNotEmpty ? widget.device.hostname : widget.device.ip;
    return Scaffold(
      appBar: AppBar(
        title: Text('Outputs — $title'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_outputs == null || _outputs!.isEmpty)
              ? const Center(child: Text('No channel outputs reported by this device.'))
              : ListView.separated(
                  itemCount: _outputs!.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final o = _outputs![i];
                    return ListTile(
                      leading: const Icon(Icons.cable),
                      title: Text(o.portLabel),
                      subtitle: Text(o.detail),
                    );
                  },
                ),
    );
  }
}
