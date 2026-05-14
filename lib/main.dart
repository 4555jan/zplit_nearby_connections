import 'package:flutter/material.dart';
import 'ble/ble_home_page.dart';

void main() {
  runApp(const ZplitBLEDemo());
}

class ZplitBLEDemo extends StatelessWidget {
  const ZplitBLEDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zplit BLE Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const BLEHomePage(),
    );
  }
}
