import 'dart:convert';
import 'dart:typed_data';
import 'package:ble_peripheral/ble_peripheral.dart';
import 'package:ble_peripheral/src/models/ble_enums.dart' as BleEnums;
import 'package:permission_handler/permission_handler.dart';
import 'ble_constants.dart';

/// In BLE terminology, a Peripheral is a device that:
/// Hosts a GATT server in memory inside the Bluetooth chip

class BleReceiver {
  /// Called whenever the BLE connection state or operational status changes.
  /// The UI layer wires this to setState() to update the status bar.
  final void Function(String status) onStatusChange;

  /// Called exactly once per incoming write operation with the decoded
  /// UTF-8 JSON string.
  final void Function(String payload) onPayloadReceived;

  BleReceiver({required this.onStatusChange, required this.onPayloadReceived});

  /// Requests all runtime permissions required for BLE peripheral operation
  /// on Android.

  Future<void> requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.locationWhenInUse,
    ].request();
  }

  /// Initializes the GATT server, registers the Zplit service and
  /// characteristic, sets up all BLE callbacks, and begins advertising.

  Future<void> startAdvertising() async {
    await requestPermissions();

    /// Allocates the GATT server object inside the Android Bluetooth stack
    await BlePeripheral.initialize();

    /// Defines the GATT attribute table structure that will be registered
    /// on the server.
    BleService service = BleService(
      /// The 128-bit UUID that uniquely identifies the Zplit sync service.
      /// This UUID is included in every advertising packet so that the
      /// Central (sender) can filter scan results to only Zplit devices.
      uuid: ZPLIT_SERVICE_UUID,
      primary: true,
      characteristics: [
        /// Defines the single characteristic that will be registered inside
        /// the Zplit service
        BleCharacteristic(
          /// The 128-bit UUID identifying this specific characteristic.
          /// The Central uses this UUID during service
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

    /// Registers the service definition into the GATT server's attribute
    /// table on the Android Bluetooth stack.
    await BlePeripheral.addService(service);

    /// Registers the callback that fires when a Central writes data to
    /// the Zplit characteristic.
    BlePeripheral.setWriteRequestCallback((
      String deviceId,
      String characteristicId,
      int offset,
      Uint8List? value,
    ) {
      if (value != null) {
        String decoded = utf8.decode(value);
        onPayloadReceived(decoded);
        onStatusChange("Received payload from $deviceId");
      }
      return WriteRequestResult(value: value);
    });

    /// Registers the callback that fires when a Central connects to or
    /// disconnects from this peripheral's GATT server.
    BlePeripheral.setConnectionStateChangeCallback((deviceId, connected) {
      onStatusChange(
        connected
            ? "Sender connected: $deviceId"
            : "Sender disconnected: $deviceId",
      );
    });

    /// Registers the callback that fires when the advertising operation
    /// starts or encounters an error
    BlePeripheral.setAdvertisingStatusUpdateCallback((
      bool advertising,
      String? error,
    ) {
      if (error != null) {
        onStatusChange("Advertising error: $error");
      }
    });

    /// Starts BLE advertising — begins broadcasting advertising packets
    /// over the air on BLE advertising channels
    await BlePeripheral.startAdvertising(
      services: [ZPLIT_SERVICE_UUID],
      localName: "Zplit-Receiver",
    );

    onStatusChange("Advertising as Zplit-Receiver. Waiting for sender...");
  }

  /// Stops BLE advertising and ceases broadcasting advertising packets.
  Future<void> stopAdvertising() async {
    await BlePeripheral.stopAdvertising();
    onStatusChange("Stopped advertising");
  }
}
