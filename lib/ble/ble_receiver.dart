import 'dart:convert';
import 'dart:typed_data';
import 'package:ble_peripheral/ble_peripheral.dart';
import 'package:ble_peripheral/src/models/ble_enums.dart' as BleEnums;
import 'package:permission_handler/permission_handler.dart';
import 'ble_constants.dart';

class BleReceiver {
  final void Function(String status) onStatusChange;
  final void Function(String payload) onPayloadReceived;

  BleReceiver({required this.onStatusChange, required this.onPayloadReceived});

  Future<void> requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.locationWhenInUse,
    ].request();
  }

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
        onPayloadReceived(decoded);
        onStatusChange("Received payload from $deviceId");
      }
      return WriteRequestResult(value: value);
    });

    BlePeripheral.setConnectionStateChangeCallback((deviceId, connected) {
      onStatusChange(
        connected
            ? "Sender connected: $deviceId"
            : "Sender disconnected: $deviceId",
      );
    });

    BlePeripheral.setAdvertisingStatusUpdateCallback((
      bool advertising,
      String? error,
    ) {
      if (error != null) {
        onStatusChange("Advertising error: $error");
      }
    });

    await BlePeripheral.startAdvertising(
      services: [ZPLIT_SERVICE_UUID],
      localName: "Zplit-Receiver",
    );

    onStatusChange("Advertising as Zplit-Receiver. Waiting for sender...");
  }

  Future<void> stopAdvertising() async {
    await BlePeripheral.stopAdvertising();
    onStatusChange("Stopped advertising");
  }
}
