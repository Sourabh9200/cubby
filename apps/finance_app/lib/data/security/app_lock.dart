import 'package:local_auth/local_auth.dart';

/// What the platform said when it was asked to unlock.
enum AppLockOutcome {
  /// The user proved who they are.
  unlocked,

  /// They dismissed the prompt, ran out of attempts, or a system event took it
  /// away. Worth another attempt.
  cancelled,

  /// The platform cannot ask at all: no screen lock is set on the phone.
  unavailable,
}

/// The on-device unlock in front of the app.
///
/// An interface because `local_auth` is a platform plugin: it cannot run under
/// `flutter test`, and every decision worth testing is on this side of it — when
/// to re-lock, what a dismissed prompt means, and whether a toggle may be turned
/// on at all. The same pattern as `PassphraseStore` and `BackupFileStore`.
///
/// ## What this is, and what it is not
///
/// The database is already encrypted with a key held in the platform keystore.
/// This is the *screen-level* gate in front of it — the division of labour
/// `passphrase_store.dart` describes — and it stops someone who picks up an
/// unlocked phone from scrolling the ledger. It is not a second layer of
/// cryptography, and no copy in the UI should suggest otherwise.
abstract interface class AppLock {
  /// Whether the platform can ask at all.
  Future<bool> isAvailable();

  /// Asks the user to unlock.
  Future<AppLockOutcome> authenticate();
}

/// [AppLock] backed by the platform's biometric and device-credential prompt.
class LocalAuthAppLock implements AppLock {
  LocalAuthAppLock({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    try {
      // `isDeviceSupported` rather than `canCheckBiometrics`: a phone with no
      // fingerprint reader but a perfectly good PIN is one this gate must
      // accept, and `canCheckBiometrics` calls that false.
      return await _auth.isDeviceSupported();
    } on Object {
      return false;
    }
  }

  @override
  Future<AppLockOutcome> authenticate() async {
    try {
      final unlocked = await _auth.authenticate(
        localizedReason: 'Unlock Cubby to see your ledger',
        // Falls back to the device PIN, pattern or password, which is the whole
        // point: a wet or bandaged finger must not lock someone out of their own
        // money.
        biometricOnly: false,
        // A phone call during the prompt must not end the attempt for good; the
        // prompt comes back when the app does.
        persistAcrossBackgrounding: true,
      );
      return unlocked ? AppLockOutcome.unlocked : AppLockOutcome.cancelled;
    } on LocalAuthException catch (error) {
      // `noCredentialsSet` is the one failure that is not the user's to retry:
      // there is no screen lock on the phone, so there is nothing to ask for.
      // Every other code — a dismissal, a timeout, a system interruption, a
      // hardware lockout that a PIN can clear — deserves another attempt.
      return error.code == LocalAuthExceptionCode.noCredentialsSet
          ? AppLockOutcome.unavailable
          : AppLockOutcome.cancelled;
    } on Object {
      return AppLockOutcome.cancelled;
    }
  }
}

/// An [AppLock] for a build with no platform prompt.
///
/// The default in `FinanceApp`, so a widget test never reaches for a plugin and
/// a build without the lock behaves exactly as it did before the feature
/// existed.
class UnavailableAppLock implements AppLock {
  const UnavailableAppLock();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<AppLockOutcome> authenticate() async => AppLockOutcome.unavailable;
}

/// An [AppLock] a test drives directly.
class FakeAppLock implements AppLock {
  FakeAppLock({
    this.available = true,
    this.outcomes = const <AppLockOutcome>[AppLockOutcome.unlocked],
  });

  /// Whether the platform is reported as able to ask.
  bool available;

  /// Consumed in order; the last one repeats. Lets a test script a dismissed
  /// prompt followed by a success.
  final List<AppLockOutcome> outcomes;

  /// How many times the platform was asked, so a test can prove the gate does
  /// not prompt on every rebuild — or that it does prompt again after the app
  /// was in the background.
  int attempts = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<AppLockOutcome> authenticate() async {
    attempts++;
    if (outcomes.isEmpty) {
      return AppLockOutcome.unavailable;
    }
    final index = attempts - 1 < outcomes.length
        ? attempts - 1
        : outcomes.length - 1;
    return outcomes[index];
  }
}
