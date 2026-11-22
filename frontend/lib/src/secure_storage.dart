import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The one secure-storage configuration every construction site must use.
///
/// Installs from the 9.x plugin hold their values under RSA-PKCS1 + AES-CBC.
/// The 10.x plugin re-encrypts them to RSA-OAEP + AES-GCM on first access
/// (`migrateOnAlgorithmChange`, on by default); `migrateWithBackup` keeps a
/// copy first so a crash mid-migration cannot lose the session token or the
/// offline store key. Keep the options identical everywhere, including the
/// headless background isolate.
const FlutterSecureStorage appSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(migrateWithBackup: true),
);
