import 'package:flutter/material.dart';

import 'services/device_manager.dart';
import 'ui/device_list_page.dart';

void main() {
  runApp(const FppControlApp());
}

class FppControlApp extends StatefulWidget {
  const FppControlApp({super.key});

  @override
  State<FppControlApp> createState() => _FppControlAppState();
}

class _FppControlAppState extends State<FppControlApp> {
  late final DeviceManager _manager;

  @override
  void initState() {
    super.initState();
    _manager = DeviceManager();
    _manager.init();
  }

  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Controller Viewer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: DeviceListPage(manager: _manager),
    );
  }
}
