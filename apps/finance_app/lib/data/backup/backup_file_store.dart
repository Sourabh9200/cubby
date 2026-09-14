import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// A backup file the user chose to restore from.
class PickedBackup {
  const PickedBackup({required this.name, required this.bytes});

  /// The file's name, for the confirmation the user sees before anything is
  /// replaced.
  final String name;

  final Uint8List bytes;
}

/// Where a backup physically goes, and where it comes back from.
///
/// An interface because the file dialog is a platform plugin: it cannot run
/// under `flutter test`, and what happens *around* the dialog — encrypting,
/// exporting, validating, replacing — is exactly what the tests need to
/// exercise. Same pattern as `PassphraseStore` in the database package, and for
/// the same reason.
abstract interface class BackupFileStore {
  /// Writes [bytes] under [fileName] at a location the user picks.
  ///
  /// Returns where it landed, or null when the user backed out — which is not
  /// an error and must not be reported as one.
  Future<String?> save({required String fileName, required Uint8List bytes});

  /// Asks the user for a backup file, or null when they backed out.
  Future<PickedBackup?> pick();
}

/// [BackupFileStore] backed by the system save-as and open dialogs.
///
/// The dialogs are deliberately left unfiltered. Filtering on a `.cubby`
/// extension would hide the very file the user just saved on some Android
/// document providers, and the app already validates the file itself: a wrong
/// file fails on the magic bytes with a sentence, which is a better error than
/// a file that cannot be selected at all.
class SystemBackupFileStore implements BackupFileStore {
  const SystemBackupFileStore();

  @override
  Future<String?> save({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final target = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      dialogTitle: 'Save your Cubby backup',
    );
    return target?.toString();
  }

  @override
  Future<PickedBackup?> pick() async {
    final file = await FilePicker.pickFile();
    if (file == null) {
      return null;
    }
    return PickedBackup(name: file.name, bytes: await file.readAsBytes());
  }
}

/// [BackupFileStore] that keeps everything in memory, for tests and for the
/// widget harness, where there is no platform file dialog to call.
class InMemoryBackupFileStore implements BackupFileStore {
  InMemoryBackupFileStore({this.cancelsSave = false, this.nextPick});

  /// Mimics the user dismissing the save dialog.
  bool cancelsSave;

  /// What [pick] returns; null mimics a cancelled pick.
  PickedBackup? nextPick;

  /// The most recent save, so a test can read back what was written.
  String? savedName;
  Uint8List? savedBytes;

  @override
  Future<String?> save({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (cancelsSave) {
      return null;
    }
    savedName = fileName;
    savedBytes = bytes;
    return 'memory://$fileName';
  }

  @override
  Future<PickedBackup?> pick() async => nextPick;
}
