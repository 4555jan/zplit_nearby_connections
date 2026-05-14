# Zplit BLE Transport Layer — Offline Expense Sync over Bluetooth Low Energy

## Overview
Zplit is an offline-first expense splitting application. This repository implements and validates the Bluetooth Low Energy transport layer 
 the mechanism by which two Android devices exchange structured expense data with zero internet dependency.

**What this demo proves:**
 Phone-to-phone BLE expense sync works on real Android hardware
 The transport is completely offline — no WiFi, no mobile data, no hotspot required at any point
 One sender can sequentially sync to multiple receivers in a single operation
 The payload format is identical to what the production Zplit app will use
 
## BLE Fundamentals
Bluetooth Low Energy operates on a client-server model with two distinct roles: Peripheral and Central.
The Peripheral is the server. It hosts a GATT server, 
advertises its presence over the air,services and characteristics(its nothing but what we used the bluetooth for for instance for zplit it will be trasfering the data) 
 and waits for incoming connections
In Zplit, the receiver phone plays this role. It uses the `ble_peripheral` package to set up the GATT server and begin advertising.
The Central is the client. It scans for nearby peripherals, filters by service UUID to find only Zplit devices, initiates a connection, discovers the 
available services and characteristics, and writes data to the appropriate characteristic. In Zplit, the sender phone plays this role. It uses the `flutter_blue_plus` package.
BLE operates on the 2.4 GHz ISM radio band independently of any network infrastructure. There is no router, no access point, and no internet required at any point in the connection.
## Connection Lifecycle
Every sync operation between a sender and a single receiver follows this sequence.
First, the receiver initializes its GATT server, registers the Zplit service and characteristic, sets up the write request callback, 
and begins advertising. 
The advertising packet broadcasts the service UUID and the local name "Zplit-Receiver" every approximately 100 milliseconds.
Second, the sender requests BLE scan permissions, starts a scan filtered to the Zplit service UUID, and collects scan results as they arrive
The scan runs for 10 seconds and surfaces only devices that are actively advertising the Zplit UUID.
Third, the sender connects to the target device, negotiates an MTU of 512 bytes, and calls `discoverServices()` to retrieve the full GATT map from the receiver's server.
This is the slowest step in the entire process as it involves a hardware round trip.
Fourth, the sender iterates through the discovered services and characteristics to locate the Zplit characteristic by UUID. Once found,
it writes the serialized JSON payload as a byte array to that characteristic using a confirmed write operation (`withoutResponse: false`), which guarantees delivery acknowledgment from the receiver.
Fifth, on the receiver side, `setWriteRequestCallback` fires, decodes the incoming bytes using UTF-8, and passes the JSON string up to the UI layer via the `onPayloadReceived` callback.
Sixth, the sender disconnects and moves to the next device if any remain in the sync queue.

The `signature` field is a placeholder in this demo. In the production Zplit app, this will be a real ECDSA signature generated using the sender's private key via the `pointycastle` package. T
he receiver will verify this signature against the sender's public key before accepting and persisting any payload. Any payload with an invalid or missing signature will be rejected silently.
The MTU is negotiated to 512 bytes. A typical expense payload of this structure serializes to approximately 280-320 bytes, comfortably within a single MTU packet. Larger payloads such as group 
sync operations with multiple expenses will require chunking, which is planned for the production implementation.

**Install dependencies:**
```bash
flutter pub get
```

**Run on a connected device:**
```bash
flutter run
```

**Build a release APK:**
```bash
flutter build apk --release
```

The APK will be at `build/app/outputs/flutter-apk/app-release.apk`. Install on both devices manually.

**Testing the sync:**

On the receiver device, select Receiver mode and tap Start Advertising. On the sender device, select Sender mode and tap Scan. Once the scan completes and the 
receiver appears in the list, tap Sync All. The receiver will display the incoming expense card and the sender will report the sync result.
To test offline operation, disable WiFi and mobile data on both devices before scanning. BLE operates independently of all network connectivity and the sync will complete identically.

<img width="338" height="758" alt="image" src="https://github.com/user-attachments/assets/94e5b005-000c-45e5-8658-54c9a433d7ca" />

<img width="366" height="819" alt="image" src="https://github.com/user-attachments/assets/d0fd2ed2-03b0-479d-a214-f69e326c6f09" />


<img width="367" height="776" alt="image" src="https://github.com/user-attachments/assets/1b160bc9-3803-4fb1-abb4-9d9df057311e" />


