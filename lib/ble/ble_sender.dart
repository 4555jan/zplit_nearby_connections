import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ble_constants.dart';

/// Handles scanning, connecting, and writing expense payloads to receiver devices.
class BleSender {
  final void Function(String status) onStatusChange;
  final void Function(List<ScanResult> results) onScanResults;
  final void Function(int success, int fail) onSyncComplete;

  BleSender({
    required this.onStatusChange,
    required this.onScanResults,
    required this.onSyncComplete,
  });

  Future<void> requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  /// Starts a BLE scan filtered to ZPLIT_SERVICE_UUID.
  /// Only devices advertising the Zplit service UUID appear in results
  Future<void> startScan() async {
    await requestPermissions();
    onStatusChange("Scanning for Zplit receivers...");

    await FlutterBluePlus.startScan(
      withServices: [Guid(ZPLIT_SERVICE_UUID)],
      timeout: const Duration(seconds: 10),
    );

    /// Streams scan results to the UI as devices are discovered.
    /// Each emission contains the full updated list of found devices.
    FlutterBluePlus.scanResults.listen((results) {
      onScanResults(results);
    });

    FlutterBluePlus.isScanning.listen((scanning) {
      if (!scanning) {
        // status handled by page via onScanResults
      }
    });
  }

  /// Sequentially connects to every discovered Zplit receiver and writes
  /// the expense payload to each one.
  Future<void> syncToAllDevices({
    required List<ScanResult> scanResults,
    required Map<String, dynamic> payload,
  }) async {
    if (scanResults.isEmpty) {
      onStatusChange("No devices to sync to.");
      return;
    }

    onStatusChange("Starting sync to ${scanResults.length} device(s)...");

    /// Serializes the expense Map to UTF-8 JSON bytes once before the loop.
    /// The same byte array is reused for every device `1 x
    Uint8List bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));

    int successCount = 0;
    int failCount = 0;

    for (int i = 0; i < scanResults.length; i++) {
      BluetoothDevice device = scanResults[i].device;
      String deviceName = device.platformName.isEmpty
          ? "Device ${i + 1}"
          : device.platformName;

      onStatusChange(
        "[${i + 1}/${scanResults.length}] Connecting to $deviceName...",
      );

      try {
        /// Opens a dedicated BLE radio channel to the receiver.
        /// requestMtu(512) negotiates max packet size — default 23 bytes
        await device.connect(timeout: const Duration(seconds: 10));
        await device.requestMtu(512);

        BluetoothCharacteristic? characteristic;
        List<BluetoothService> services = await device.discoverServices();

        /// Locates the Zplit characteristic by UUID within the discovered services.
        /// Uses loose contains() matching to handle UUID format variations
        /// across different Android versions and manufacturers.
        for (BluetoothService service in services) {
          if (service.uuid.toString().toLowerCase().contains("abcd")) {
            for (BluetoothCharacteristic char in service.characteristics) {
              if (char.uuid.toString().toLowerCase().contains("dcba")) {
                characteristic = char;
                break;
              }
            }
          }
        }

        if (characteristic == null) {
          onStatusChange(
            "[${i + 1}/${scanResults.length}] Service not found on $deviceName",
          );
          await device.disconnect();
          failCount++;
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }

        onStatusChange(
          "[${i + 1}/${scanResults.length}] Sending to $deviceName...",
        );
        await characteristic.write(bytes, withoutResponse: false);

        successCount++;
        onStatusChange("[${i + 1}/${scanResults.length}]  Sent to $deviceName");

        await device.disconnect();
        await Future.delayed(const Duration(seconds: 1));
      } catch (e) {
        failCount++;
        onStatusChange(
          "[${i + 1}/${scanResults.length}]  Failed: $deviceName — $e",
        );
        try {
          await device.disconnect();
        } catch (_) {}
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    onSyncComplete(successCount, failCount);
  }
}
