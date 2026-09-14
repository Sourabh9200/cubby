/// Passphrase handling for the encrypted database.
///
/// The passphrase is a 32-byte random value, not a user password. Deriving it
/// from something a person types would weaken the key to human entropy, and
/// PIN-based protection is a separate UI-level concern handled by `local_auth`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Reads and writes the database passphrase.
///
/// Stored in the platform keystore (Android Keystore, Keychain) rather than
/// shared preferences, so that reading the app's data directory on a rooted
/// device does not also yield the key that decrypts it.
abstract interface class PassphraseStore {
  /// Returns the existing passphrase, generating and persisting one on first
  /// run.
  Future<String> loadOrCreate();

  /// Whether a passphrase already exists. Used by the UI to distinguish a
  /// fresh install from a returning one.
  Future<bool> exists();

  /// Destroys the passphrase, which makes the existing database permanently
  /// unreadable. Only ever called after an explicit confirmation.
  Future<void> destroy();
}

/// [PassphraseStore] backed by `flutter_secure_storage`.
class SecureStoragePassphraseStore implements PassphraseStore {
  SecureStoragePassphraseStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  // Note on options: `flutter_secure_storage` 11.x removed the old
  // `encryptedSharedPreferences: true` flag because the default Android
  // backend is now AES-GCM with RSA-OAEP key wrapping in the Keystore. The
  // defaults are the strong configuration, so nothing needs opting into.

  static const String _key = 'finance_db_passphrase_v1';

  /// 32 bytes, base64-encoded. Base64 avoids quoting hazards entirely, and 256
  /// bits is well beyond the range of brute force.
  static const int _keyBytes = 32;

  final FlutterSecureStorage _storage;

  @override
  Future<bool> exists() async => await _storage.read(key: _key) != null;

  @override
  Future<String> loadOrCreate() async {
    final existing = await _storage.read(key: _key);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final generated = generatePassphrase();
    await _storage.write(key: _key, value: generated);
    return generated;
  }

  @override
  Future<void> destroy() => _storage.delete(key: _key);

  /// Generates a fresh 256-bit passphrase.
  ///
  /// Uses [Random.secure] specifically: the default `Random` is a predictable
  /// PRNG, and a predictable database key is equivalent to no encryption.
  static String generatePassphrase() {
    final random = Random.secure();
    final bytes = List<int>.generate(_keyBytes, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }
}

/// In-memory passphrase store for tests.
class InMemoryPassphraseStore implements PassphraseStore {
  InMemoryPassphraseStore([String? passphrase])
    : _passphrase =
          passphrase ?? SecureStoragePassphraseStore.generatePassphrase();

  String? _passphrase;

  @override
  Future<bool> exists() async => _passphrase != null;

  @override
  Future<String> loadOrCreate() async {
    _passphrase ??= SecureStoragePassphraseStore.generatePassphrase();
    return _passphrase!;
  }

  @override
  Future<void> destroy() async {
    _passphrase = null;
  }
}

/// Confirms that a database file is actually encrypted.
///
/// This is the check that catches the dangerous failure mode: if the
/// cipher-enabled SQLite build is not linked, `PRAGMA key` is accepted as a
/// no-op and the database is written as plaintext with no error anywhere. A
/// plaintext SQLite file begins with the bytes `SQLite format 3\0`; an
/// encrypted one begins with random data.
///
/// Returns true when the header is *not* the SQLite magic string.
Future<bool> isFileEncrypted(File file) async {
  if (!await file.exists()) {
    return false;
  }
  final handle = await file.open();
  try {
    final header = await handle.read(16);
    if (header.length < 16) {
      return false; // Too short to be a valid database of either kind.
    }
    const magic = <int>[
      0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66, // "SQLite f"
      0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00, // "ormat 3\0"
    ];
    for (var i = 0; i < magic.length; i++) {
      if (header[i] != magic[i]) {
        // The header is not the SQLite magic string, so the file is encrypted.
        return true;
      }
    }
    return false;
  } finally {
    await handle.close();
  }
}
