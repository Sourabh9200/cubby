import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Raised when a backup cannot be sealed or opened.
///
/// Separate from `BackupFormatException` because the two mean different things
/// to a user: a format error means "this is not the right file", a crypto error
/// means "this is the right file and the wrong passphrase". Only one is worth
/// retrying.
class BackupCryptoException implements Exception {
  const BackupCryptoException(this.message);

  final String message;

  @override
  String toString() => 'BackupCryptoException: $message';
}

/// Seals a backup file under a passphrase the user chooses.
///
/// The passphrase is a *second*, independent secret. It is deliberately not the
/// database key: that key is 256 random bits living in the platform keystore,
/// which is unguessable but also unmemorable, and it dies with the app — which
/// is precisely the problem a backup exists to solve. A passphrase the user can
/// type is the only thing that can outlive a reinstall.
///
/// ## The file format
///
/// ```text
/// magic "CUBBYBKP" (8) | version (1) | kdf id (1) | iterations (4, big-endian)
/// | salt length (1) | salt (16) | nonce (12) | ciphertext | mac (16)
/// ```
///
/// Everything before the nonce is the header, and it is authenticated
/// implicitly: AES-GCM's tag covers the ciphertext, and the key is derived from
/// the salt and iteration count, so altering either to weaken the derivation
/// yields a key that fails the tag check.
///
/// The iteration count is *stored* rather than assumed, so it can be raised in
/// a later release without making every backup written today unreadable.
class BackupCrypto {
  BackupCrypto._();

  /// Identifies the file before any parsing is attempted, so an unrelated file
  /// fails with one clear sentence.
  static const List<int> magic = <int>[
    0x43, 0x55, 0x42, 0x42, 0x59, 0x42, 0x4B, 0x50, // "CUBBYBKP"
  ];

  /// The envelope layout this build writes.
  static const int envelopeVersion = 1;

  static const int _kdfPbkdf2HmacSha256 = 1;

  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _macLength = 16;

  /// PBKDF2-HMAC-SHA256 rounds. OWASP's floor for this construction is 210,000.
  ///
  /// Affordable here because sealing happens on a deliberate tap, once, rather
  /// than on every launch — which is exactly why the earlier comment in
  /// `passphrase_store.dart` says a typed secret belongs in a UI action and not
  /// in the database key's path.
  static const int pbkdf2Iterations = 210000;

  /// The shortest passphrase worth accepting.
  ///
  /// Length is the only property the user controls that reliably moves the cost
  /// of guessing, so this refuses a token that would fall to a dictionary in
  /// minutes — a backup people believe is protected and is not is worse than one
  /// they know is unencrypted.
  static const int minimumPassphraseLength = 8;

  static final AesGcm _cipher = AesGcm.with256bits();
  static final Random _random = Random.secure();

  /// Encrypts [clearText] and returns a complete backup file.
  static Future<Uint8List> seal({
    required List<int> clearText,
    required String passphrase,
  }) async {
    final salt = _randomBytes(_saltLength);
    final secretKey = await _deriveKey(passphrase, salt);
    final box = await _cipher.encrypt(clearText, secretKey: secretKey);
    final body = box.concatenation(); // nonce || ciphertext || mac

    final headerLength = magic.length + 1 + 1 + 4 + 1;
    final out = Uint8List(headerLength + salt.length + body.length);
    var offset = 0;

    out.setRange(offset, offset + magic.length, magic);
    offset += magic.length;
    out[offset++] = envelopeVersion;
    out[offset++] = _kdfPbkdf2HmacSha256;
    out[offset++] = (pbkdf2Iterations >> 24) & 0xFF;
    out[offset++] = (pbkdf2Iterations >> 16) & 0xFF;
    out[offset++] = (pbkdf2Iterations >> 8) & 0xFF;
    out[offset++] = pbkdf2Iterations & 0xFF;
    out[offset++] = salt.length;
    out.setRange(offset, offset + salt.length, salt);
    offset += salt.length;
    out.setRange(offset, offset + body.length, body);

    return out;
  }

  /// Decrypts a file produced by [seal].
  ///
  /// Throws [BackupCryptoException] with a sentence a user can act on when the
  /// file is not ours, is truncated, or the passphrase is wrong.
  static Future<Uint8List> open({
    required List<int> envelope,
    required String passphrase,
  }) async {
    final headerLength = magic.length + 1 + 1 + 4 + 1;
    if (envelope.length < headerLength + _nonceLength + _macLength) {
      throw const BackupCryptoException(
        'That file is too short to be a Cubby backup.',
      );
    }
    for (var i = 0; i < magic.length; i++) {
      if (envelope[i] != magic[i]) {
        throw const BackupCryptoException(
          'That file is not a Cubby backup. Choose the file this app saved.',
        );
      }
    }

    var offset = magic.length;
    final version = envelope[offset++];
    if (version != envelopeVersion) {
      throw BackupCryptoException(
        'This backup was written in a newer format (v$version). Update Cubby '
        'and try again.',
      );
    }
    if (envelope[offset++] != _kdfPbkdf2HmacSha256) {
      throw const BackupCryptoException(
        'This backup uses a key derivation this version of Cubby does not '
        'support.',
      );
    }
    final iterations = _readUint32(envelope, offset);
    offset += 4;
    final saltLength = envelope[offset++];
    if (saltLength == 0 ||
        envelope.length < offset + saltLength + _nonceLength + _macLength) {
      throw const BackupCryptoException('This backup file is incomplete.');
    }
    final salt = envelope.sublist(offset, offset + saltLength);
    offset += saltLength;

    final secretKey = await _deriveKey(
      passphrase,
      salt,
      iterations: iterations,
    );
    final box = SecretBox.fromConcatenation(
      envelope.sublist(offset),
      nonceLength: _nonceLength,
      macLength: _macLength,
    );

    final List<int> clearText;
    try {
      clearText = await _cipher.decrypt(box, secretKey: secretKey);
    } on SecretBoxAuthenticationError {
      // The tag failed, which is what a wrong passphrase looks like. Nothing in
      // the file distinguishes it from a corrupted one, and saying so would only
      // make the user doubt a passphrase they typed correctly.
      throw const BackupCryptoException(
        'That passphrase does not open this backup. Check it and try again.',
      );
    } on Object {
      throw const BackupCryptoException('This backup file is damaged.');
    }
    return Uint8List.fromList(clearText);
  }

  static Future<SecretKey> _deriveKey(
    String passphrase,
    List<int> salt, {
    int iterations = pbkdf2Iterations,
  }) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  ).deriveKeyFromPassword(password: passphrase, nonce: salt);

  static Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  static int _readUint32(List<int> bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}
