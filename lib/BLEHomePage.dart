import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:ble_peripheral/ble_peripheral.dart';
import 'package:ble_peripheral/src/models/ble_enums.dart' as BleEnums;
import 'package:permission_handler/permission_handler.dart';

const String ZPLIT_SERVICE_UUID = "0000abcd-0000-1000-8000-00805f9b34fb";
const String ZPLIT_CHAR_UUID = "0000dcba-0000-1000-8000-00805f9b34fb";

class BLEHomePage extends StatefulWidget {
  const BLEHomePage({super.key});

  @override
  State<BLEHomePage> createState() => _BLEHomePageState();
}


class _BLEHomePageState extends State<BLEHomePage> {
  bool isSender = true;

  // Scanning
  List<ScanResult> scanResults = [];
  bool isScanning = false;

  // Syncing
  bool isSyncing = false;
  int syncSuccessCount = 0;
  int syncFailCount = 0;

  // Advertising
  bool isAdvertising = false;

  // Single connect (kept for individual connect button)
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? zplitCharacteristic;

  // Status and received data
  String status = "Select mode and tap Start";
  List<String> receivedPayloads = [];

  // ─── Permissions ────────────────────────────────────────────────────────────
  Future<void> requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.locationWhenInUse,
    ].request();
  }

  // ─── RECEIVER ───────────────────────────────────────────────────────────────
  Future<void> startAdvertising() async {
    await requestPermissions();
    await BlePeripheral.initialize();

    BleService service = BleService(
      uuid: ZPLIT_SERVICE_UUID,
      primary: true,
      characteristics: [
        BleCharacteristic(
          uuid: ZPLIT_CHAR_UUID,
          properties: [
            BleEnums.CharacteristicProperties.write.index,
            BleEnums.CharacteristicProperties.notify.index,
            BleEnums.CharacteristicProperties.read.index,
          ],
          permissions: [
            BleEnums.AttributePermissions.readable.index,
            BleEnums.AttributePermissions.writeable.index,
          ],
        ),
      ],
    );

    await BlePeripheral.addService(service);

    BlePeripheral.setWriteRequestCallback((
      String deviceId,
      String characteristicId,
      int offset,
      Uint8List? value,
    ) {
      if (value != null) {
        String decoded = utf8.decode(value);
        setState(() {
          receivedPayloads.add(decoded);
          status = "Received payload from $deviceId";
        });
      }
      return WriteRequestResult(value: value);
    });

    BlePeripheral.setConnectionStateChangeCallback((deviceId, connected) {
      setState(() {
        status = connected
            ? "Sender connected: $deviceId"
            : "Sender disconnected: $deviceId";
      });
    });

    BlePeripheral.setAdvertisingStatusUpdateCallback((
      bool advertising,
      String? error,
    ) {
      if (error != null) {
        setState(() => status = "Advertising error: $error");
      }
    });

    await BlePeripheral.startAdvertising(
      services: [ZPLIT_SERVICE_UUID],
      localName: "Zplit-Receiver",
    );

    setState(() {
      isAdvertising = true;
      status = "Advertising as Zplit-Receiver. Waiting for sender...";
    });
  }

  Future<void> stopAdvertising() async {
    await BlePeripheral.stopAdvertising();
    setState(() {
      isAdvertising = false;
      status = "Stopped advertising";
    });
  }

  // ─── SENDER — Scan ──────────────────────────────────────────────────────────
  Future<void> startScan() async {
    await requestPermissions();

    setState(() {
      scanResults.clear();
      isScanning = true;
      syncSuccessCount = 0;
      syncFailCount = 0;
      status = "Scanning for Zplit receivers...";
    });

    await FlutterBluePlus.startScan(
      withServices: [Guid(ZPLIT_SERVICE_UUID)],
      timeout: const Duration(seconds: 10),
    );

    FlutterBluePlus.scanResults.listen((results) {
      setState(() => scanResults = results);
    });

    FlutterBluePlus.isScanning.listen((scanning) {
      setState(() {
        isScanning = scanning;
        if (!scanning) {
          status = scanResults.isEmpty
              ? "No Zplit devices found. Make sure receivers are advertising."
              : "Found ${scanResults.length} Zplit device(s). Tap 'Sync All'";
        }
      });
    });
  }

  // ─── SENDER — Sync to ALL devices ───────────────────────────────────────────
  Future<void> syncToAllDevices() async {
    if (scanResults.isEmpty) {
      setState(() => status = "No devices to sync to.");
      return;
    }

    setState(() {
      isSyncing = true;
      syncSuccessCount = 0;
      syncFailCount = 0;
      status = "Starting sync to ${scanResults.length} device(s)...";
    });

    // Build payload once, send to everyone
    Map<String, dynamic> payload = {
      "type": "expense_sync",
      "version": "1.0",
      "timestamp": DateTime.now().toIso8601String(),
      "data": {
        "expense_id": "exp_${DateTime.now().millisecondsSinceEpoch}",
        "description": "Dinner at restaurant",
        "amount": 1200.0,
        "currency": "INR",
        "paid_by": "janvi",
        "split_type": "equal",
        "participants": ["janvi", "friend1", "friend2"],
        "amount_per_person": 400.0,
        "group_id": "grp_001",
        "category": "food",
      },
      "signature": "DUMMY_ECDSA_SIGNATURE_PLACEHOLDER",
    };

    Uint8List bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));

    for (int i = 0; i < scanResults.length; i++) {
      BluetoothDevice device = scanResults[i].device;
      String deviceName = device.platformName.isEmpty
          ? "Device ${i + 1}"
          : device.platformName;

      setState(
        () => status =
            "[${i + 1}/${scanResults.length}] Connecting to $deviceName...",
      );

      try {
        // Connect
        await device.connect(timeout: const Duration(seconds: 10));
        await device.requestMtu(512);

        // Find characteristic
        BluetoothCharacteristic? characteristic;
        List<BluetoothService> services = await device.discoverServices();

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
          setState(
            () => status =
                "[${i + 1}/${scanResults.length}] ❌ Service not found on $deviceName",
          );
          await device.disconnect();
          syncFailCount++;
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }

        // Send payload
        setState(
          () => status =
              "[${i + 1}/${scanResults.length}] Sending to $deviceName...",
        );
        await characteristic.write(bytes, withoutResponse: false);

        syncSuccessCount++;
        setState(
          () =>
              status = "[${i + 1}/${scanResults.length}] ✅ Sent to $deviceName",
        );

        // Disconnect before next device
        await device.disconnect();
        await Future.delayed(const Duration(seconds: 1));
      } catch (e) {
        syncFailCount++;
        setState(
          () => status =
              "[${i + 1}/${scanResults.length}] ❌ Failed: $deviceName — $e",
        );
        try {
          await device.disconnect();
        } catch (_) {}
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    // Final summary
    setState(() {
      isSyncing = false;
      status =
          "Sync complete — ✅ $syncSuccessCount succeeded  ❌ $syncFailCount failed";
    });
  }

  // ─── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Zplit BLE Demo"),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mode selector
            Row(
              children: [
                const Text("Mode: "),
                ChoiceChip(
                  label: const Text("Sender"),
                  selected: isSender,
                  onSelected: (_) => setState(() {
                    isSender = true;
                    status = "Select mode and tap Start";
                    scanResults.clear();
                  }),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text("Receiver"),
                  selected: !isSender,
                  onSelected: (_) => setState(() {
                    isSender = false;
                    status = "Select mode and tap Start";
                  }),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Status bar
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "Status: $status",
                style: const TextStyle(fontSize: 13),
              ),
            ),

            const SizedBox(height: 12),

            // ── SENDER UI ──
            if (isSender) ...[
              Row(
                children: [
                  // Scan button
                  ElevatedButton(
                    onPressed: isScanning || isSyncing ? null : startScan,
                    child: Text(isScanning ? "Scanning..." : "Scan"),
                  ),
                  const SizedBox(width: 8),
                  // Sync All button
                  ElevatedButton(
                    onPressed:
                        scanResults.isNotEmpty && !isSyncing && !isScanning
                        ? syncToAllDevices
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    child: Text(
                      isSyncing
                          ? "Syncing..."
                          : "Sync All (${scanResults.length})",
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Sync progress indicator
              if (isSyncing)
                LinearProgressIndicator(
                  value:
                      (syncSuccessCount + syncFailCount) /
                      (scanResults.isEmpty ? 1 : scanResults.length),
                  backgroundColor: Colors.grey.shade200,
                  color: Colors.deepPurple,
                ),

              const SizedBox(height: 8),

              // Device list
              if (scanResults.isNotEmpty) ...[
                Text(
                  "Nearby Zplit Receivers (${scanResults.length}):",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: scanResults.length,
                    itemBuilder: (context, index) {
                      ScanResult result = scanResults[index];
                      return Card(
                        child: ListTile(
                          leading: const Icon(
                            Icons.bluetooth,
                            color: Colors.deepPurple,
                          ),
                          title: Text(
                            result.device.platformName.isEmpty
                                ? "Zplit Device ${index + 1}"
                                : result.device.platformName,
                          ),
                          subtitle: Text("Signal: ${result.rssi} dBm"),
                        ),
                      );
                    },
                  ),
                ),
              ] else if (!isScanning) ...[
                const Expanded(
                  child: Center(
                    child: Text(
                      "Tap Scan to find nearby Zplit receivers",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              ],

              // ── RECEIVER UI ──
            ] else ...[
              Row(
                children: [
                  ElevatedButton(
                    onPressed: isAdvertising ? null : startAdvertising,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                    ),
                    child: const Text(
                      "Start Advertising",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: isAdvertising ? stopAdvertising : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: const Text(
                      "Stop",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              if (receivedPayloads.isNotEmpty) ...[
                Text(
                  "Received Payloads (${receivedPayloads.length}):",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: receivedPayloads.length,
                    itemBuilder: (context, index) {
                      Map<String, dynamic> parsed = jsonDecode(
                        receivedPayloads[index],
                      );
                      Map<String, dynamic> data = parsed['data'];
                      return Card(
                        color: Colors.green.shade50,
                        child: ListTile(
                          leading: const Icon(
                            Icons.receipt,
                            color: Colors.green,
                          ),
                          title: Text(data['description'] ?? ''),
                          subtitle: Text(
                            "₹${data['amount']} • Paid by ${data['paid_by']}",
                          ),
                          trailing: Text(
                            "₹${data['amount_per_person']}/person",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ] else if (isAdvertising) ...[
                const Expanded(
                  child: Center(
                    child: Text(
                      "Waiting for sender to connect\nand send expense data...",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    FlutterBluePlus.stopScan();
    BlePeripheral.stopAdvertising();
    super.dispose();
  }
}
