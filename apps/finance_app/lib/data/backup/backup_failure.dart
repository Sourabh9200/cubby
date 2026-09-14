/// A backup operation that failed, carrying a sentence the user can act on.
///
/// The settings screen must not need to know about AES-GCM, PBKDF2 or the
/// database schema, so the data layer translates every failure — a wrong
/// passphrase, a foreign file, a backup written by a newer release — into this
/// one type, and the UI shows [message] and nothing else. Without it the widget
/// would catch two exception types from two libraries to say one sentence.
class BackupFailure implements Exception {
  const BackupFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
