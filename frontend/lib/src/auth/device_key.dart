import 'dart:convert';

import 'package:flutter/services.dart';

import '../config.dart';

/// P-256 key in the Android Keystore that renews the session (see the
/// backend's handler/device.go). Elsewhere every call answers null: those
/// platforms sign in again when the session runs out.
class DeviceKey {
  const DeviceKey();

  static const _channel = MethodChannel('com.caldasstudios.app217/device_key');

  /// Replaces any previous key; returns the base64 PKIX public key.
  Future<String?> create() async {
    if (!isAndroidPlatform) return null;
    try {
      final der = await _channel.invokeMethod<Uint8List>('create');
      return der == null ? null : base64Encode(der);
    } catch (_) {
      return null;
    }
  }

  /// Base64 DER (ASN.1) SHA256withECDSA signature of [message].
  Future<String?> sign(String message) async {
    if (!isAndroidPlatform) return null;
    try {
      final sig = await _channel.invokeMethod<Uint8List>(
        'sign',
        {'message': Uint8List.fromList(utf8.encode(message))},
      );
      return sig == null ? null : base64Encode(sig);
    } catch (_) {
      return null;
    }
  }

  Future<void> delete() async {
    if (!isAndroidPlatform) return;
    try {
      await _channel.invokeMethod<void>('delete');
    } catch (_) {}
  }
}
