import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:sdk_ble_flutter/protos/gatt.pb.dart';
export 'package:sdk_ble_flutter/protos/gatt.pb.dart';

import 'package:sdk_ble_flutter/protos/device.pb.dart';
export 'package:sdk_ble_flutter/protos/device.pb.dart';

export 'package:sdk_ble_flutter/protos/bound_witness.pb.dart';

enum XyoDeviceType { sentinel, bridge, android, ios, xy4 }

typedef XyoDeviceUpdatedCallback = void Function(BluetoothDevice);

class XyoDeviceChannel extends MethodChannel {
  Map<String, XyoDeviceUpdatedCallback> onDetectNotify = Map();
  Map<String, XyoDeviceUpdatedCallback> onEnterNotify = Map();
  Map<String, XyoDeviceUpdatedCallback> onExitNotify = Map();

  void reportEnter(dynamic device) {
    final bluetoothDevice = BluetoothDevice.fromBuffer(device);
    onEnterNotify.forEach((String key, XyoDeviceUpdatedCallback callback) => callback(bluetoothDevice));
  }

  void reportExit(dynamic device) {
    final bluetoothDevice = BluetoothDevice.fromBuffer(device);
    onExitNotify.forEach((String key, XyoDeviceUpdatedCallback callback) => callback(bluetoothDevice));
  }

  void reportDetected(dynamic device) {
    final bluetoothDevice = BluetoothDevice.fromBuffer(device);
    onDetectNotify.forEach((String key, XyoDeviceUpdatedCallback callback) => callback(bluetoothDevice));
  }

  final EventChannel onEnter;
  final EventChannel onExit;
  final EventChannel onDetected;
  XyoDeviceChannel(String name)
      : onEnter = EventChannel("${name}OnEnter"),
        onExit = EventChannel("${name}OnExit"),
        onDetected = EventChannel("${name}OnDetect"),
        super(name) {
    onEnter.receiveBroadcastStream().listen(reportEnter);
    onExit.receiveBroadcastStream().listen(reportExit);
    onDetected.receiveBroadcastStream().listen(reportDetected);
  }

  // Start listening for button presses on devices
  Future<bool> startAddDevice() async {
    return await invokeMethod<bool>('start');
  }

  // Stop listening for button presses on devices
  Future<bool> stopAddDevice() async {
    return await invokeMethod<bool>('stop');
  }

  /// Run one defined operation on a single device
  Future<GattResponse> defined(BluetoothDevice device, DefinedOperation operation) async {
    final gattOp = GattOperation();
    gattOp.definedOperation = operation;
    gattOp.deviceId = device.id;

    final Uint8List rawData = await invokeMethod('gattSingle', <String, dynamic>{
      'request': gattOp.writeToBuffer(),
    });

    if (rawData != null) {
      final GattResponse response = GattResponse.fromBuffer(rawData);
      return response;
    } else {
      return GattResponse.getDefault();
    }
  }

  /// Run one GATT call on a single device
  Future<GattResponse> operation(BluetoothDevice device, String serviceUuid, String characteristicUuid) async {
    final gattCall = GattCall();
    gattCall.serviceUuid = serviceUuid;
    gattCall.characteristicUuid = characteristicUuid;

    final gattOp = GattOperation();
    gattOp.deviceId = device.id;
    gattOp.gattCall = gattCall;

    final Uint8List rawData = await invokeMethod('gattSingle', <String, dynamic>{
      'request': gattOp.writeToBuffer(),
    });

    final GattResponse response = GattResponse.fromBuffer(rawData);
    return response;
  }

  Future<GattResponse> get definedListDifferentDevices async {
    final gattOp1 = GattOperation();
    gattOp1.definedOperation = DefinedOperation.SONG;
    gattOp1.deviceId = 'xy:ibeacon:a44eacf4-0104-0000-0000-5f784c9977b5.8196.2628';

    final gattOp2 = GattOperation();
    gattOp2.definedOperation = DefinedOperation.SONG;
    gattOp2.deviceId = 'xy:ibeacon:a44eacf4-0104-0000-0000-5f784c9977b5.12308.27748';

    final operations = GattOperationList();
    operations.operations
      ..clear()
      ..addAll([gattOp1, gattOp2]);
    operations.disconnectOnCompletion = true;

    final Uint8List rawData = await invokeMethod('gattList', <String, dynamic>{
      'request': operations.writeToBuffer(),
    });

    final GattResponse response = GattResponse.fromBuffer(rawData);
    return response;
  }

  Future<GattResponse> get buzzerDefined async {
    final buzzer = GattOperation();
    buzzer.definedOperation = DefinedOperation.SONG;
    buzzer.deviceId = 'xy:ibeacon:a44eacf4-0104-0000-0000-5f784c9977b5.69.17896';

    final Uint8List rawData = await invokeMethod('gattSingle', <String, dynamic>{
      'request': buzzer.writeToBuffer(),
    });

    final GattResponse response = GattResponse.fromBuffer(rawData);
    return response;
  }

  Future<GattResponse> get buzzerDefinedGroup async {
    final buzzer = GattOperation();
    buzzer.definedOperation = DefinedOperation.SONG;

    final operations = GattOperationList();
    operations.deviceId = 'xy:ibeacon:a44eacf4-0104-0000-0000-5f784c9977b5.69.17896';
    operations.operations
      ..clear()
      ..addAll([buzzer]);
    operations.disconnectOnCompletion = true;

    final Uint8List rawData = await invokeMethod('gattGroup', <String, dynamic>{
      'request': operations.writeToBuffer(),
    });

    final GattResponse response = GattResponse.fromBuffer(rawData);
    return response;
  }

  Future<GattResponse> get buzzer async {
    final unlock = GattOperation();

    final unlockCall = GattCall();
    unlockCall.serviceUuid = 'a44eacf4-0104-0001-0000-5f784c9977b5';
    unlockCall.characteristicUuid = 'a44eacf4-0104-0001-0002-5f784c9977b5';

    unlock.gattCall = unlockCall;

    final unlockData = GattOperation_Write();
    unlockData.request =
        Uint8List.fromList([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f]);
    unlockData.requiresResponse = true;

    unlock.writeRequest = unlockData;

    final buzzer = GattOperation();

    final buzzerCall = GattCall();
    buzzerCall.serviceUuid = 'a44eacf4-0104-0001-0000-5f784c9977b5';
    buzzerCall.characteristicUuid = 'a44eacf4-0104-0001-0008-5f784c9977b5';

    buzzer.gattCall = buzzerCall;

    final buzzerData = GattOperation_Write();
    buzzerData.request = Uint8List.fromList([0x0b, 0x03]);
    buzzerData.requiresResponse = true;

    buzzer.writeRequest = buzzerData;

    final operations = GattOperationList();
    operations.deviceId = 'xy:ibeacon:a44eacf4-0104-0000-0000-5f784c9977b5.69.17896';
    operations.operations
      ..clear()
      ..addAll([unlock, buzzer]);

    final Uint8List rawData = await invokeMethod('gattGroup', <String, dynamic>{
      'request': operations.writeToBuffer(),
    });

    final GattResponse response = GattResponse.fromBuffer(rawData);
    return response;
  }
}
