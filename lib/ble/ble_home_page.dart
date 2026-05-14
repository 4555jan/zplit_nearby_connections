import 'dart:convert';
import 'package:ble_peripheral/ble_peripheral.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_receiver.dart';
import 'ble_sender.dart';

class BLEHomePage extends StatefulWidget {
  const BLEHomePage({super.key});

  @override
  State<BLEHomePage> createState() => _BLEHomePageState();
}

class _BLEHomePageState extends State<BLEHomePage> {
  bool isSender = true;

  List<ScanResult> scanResults = [];
  bool isScanning = false;
  bool isSyncing = false;
  bool isAdvertising = false;
  int syncSuccessCount = 0;
  int syncFailCount = 0;

  String status = "Select mode and tap Start";
  List<String> receivedPayloads = [];

  late BleReceiver _receiver;
  late BleSender _sender;

  @override
  void initState() {
    super.initState();

    _receiver = BleReceiver(
      onStatusChange: (s) => setState(() => status = s),
      onPayloadReceived: (p) => setState(() => receivedPayloads.add(p)),
    );

    _sender = BleSender(
      onStatusChange: (s) => setState(() => status = s),
      onScanResults: (results) => setState(() {
        scanResults = results;
        status = results.isEmpty
            ? "No Zplit devices found."
            : "Found ${results.length} Zplit device(s). Tap 'Sync All'";
      }),
      onSyncComplete: (success, fail) => setState(() {
        isSyncing = false;
        syncSuccessCount = success;
        syncFailCount = fail;
        status = "Sync complete —  $success succeeded   $fail failed";
      }),
    );
  }

  // Dummy payload — replace with real Drift data in production
  Map<String, dynamic> _buildPayload() => {
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
                  ElevatedButton(
                    onPressed: isScanning || isSyncing
                        ? null
                        : () async {
                            setState(() {
                              isScanning = true;
                              scanResults.clear();
                            });
                            await _sender.startScan();
                            setState(() => isScanning = false);
                          },
                    child: Text(isScanning ? "Scanning..." : "Scan"),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed:
                        scanResults.isNotEmpty && !isSyncing && !isScanning
                        ? () async {
                            setState(() => isSyncing = true);
                            await _sender.syncToAllDevices(
                              scanResults: scanResults,
                              payload: _buildPayload(),
                            );
                          }
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

              if (isSyncing)
                LinearProgressIndicator(
                  value:
                      (syncSuccessCount + syncFailCount) /
                      (scanResults.isEmpty ? 1 : scanResults.length),
                  backgroundColor: Colors.grey.shade200,
                  color: Colors.deepPurple,
                ),

              const SizedBox(height: 8),

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
                    onPressed: isAdvertising
                        ? null
                        : () async {
                            await _receiver.startAdvertising();
                            setState(() => isAdvertising = true);
                          },
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
                    onPressed: isAdvertising
                        ? () async {
                            await _receiver.stopAdvertising();
                            setState(() => isAdvertising = false);
                          }
                        : null,
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
