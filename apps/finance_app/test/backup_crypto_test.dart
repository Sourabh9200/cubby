import 'dart:convert';
import 'dart:typed_data';

import 'package:finance_app/data/backup/backup_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const String passphrase = 'a good passphrase';
  final Uint8List clear = Uint8List.fromList(utf8.encode('{"hello":"world"}'));

  test('opens exactly what it sealed', () async {
    final file = await BackupCrypto.seal(
      clearText: clear,
      passphrase: passphrase,
    );
    final opened = await BackupCrypto.open(
      envelope: file,
      passphrase: passphrase,
    );
    expect(utf8.decode(opened), '{"hello":"world"}');
  });

  test('writes the magic header first', () async {
    final file = await BackupCrypto.seal(
      clearText: clear,
      passphrase: passphrase,
    );
    expect(
      file.sublist(0, BackupCrypto.magic.length),
      equals(BackupCrypto.magic),
    );
  });

  test('never repeats itself, because the salt and nonce are random', () async {
    final first = await BackupCrypto.seal(
      clearText: clear,
      passphrase: passphrase,
    );
    final second = await BackupCrypto.seal(
      clearText: clear,
      passphrase: passphrase,
    );
    // Two backups of the same data that were byte-identical would tell an
    // observer that nothing changed between them.
    expect(first, isNot(equals(second)));
  });

  test('refuses the wrong passphrase', () async {
    final file = await BackupCrypto.seal(
      clearText: clear,
      passphrase: passphrase,
    );
    await expectLater(
      BackupCrypto.open(envelope: file, passphrase: 'the wrong passphrase'),
      throwsA(isA<BackupCryptoException>()),
    );
  });

  test('refuses a file that is not one of ours', () async {
    await expectLater(
      BackupCrypto.open(
        envelope: Uint8List.fromList(List<int>.filled(96, 7)),
        passphrase: passphrase,
      ),
      throwsA(isA<BackupCryptoException>()),
    );
  });

  test('refuses a body that was altered after sealing', () async {
    final file = await BackupCrypto.seal(
      clearText: clear,
      passphrase: passphrase,
    );
    final tampered = Uint8List.fromList(file);
    // Flip a bit in the ciphertext: AES-GCM's tag must reject it rather than
    // decrypting to different data.
    final index = tampered.length - 20;
    tampered[index] = tampered[index] ^ 0xFF;

    await expectLater(
      BackupCrypto.open(envelope: tampered, passphrase: passphrase),
      throwsA(isA<BackupCryptoException>()),
    );
  });
}
