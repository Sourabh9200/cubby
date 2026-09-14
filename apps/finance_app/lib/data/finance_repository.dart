import 'dart:typed_data';

import 'finance_snapshot.dart';
import 'models.dart';

/// The app's data access contract.
///
/// An interface rather than a concrete class so the UI depends on behaviour,
/// not on drift. That is what allowed the demo repository to be swapped for the
/// encrypted one without touching a widget, and it is what a widget test uses
/// to inject a fixed snapshot.
abstract interface class FinanceRepository {
  /// Emits a fresh snapshot on load and after every write.
  Stream<FinanceSnapshot> watch();

  /// Records a new entry. [occurredOn] is the local calendar date.
  Future<void> addTransaction({
    required String accountId,
    required String categoryId,
    required int amountMinor,
    required DateTime date,
    required TxDirection direction,
    String payee,
    String note,
  });

  /// Replaces an existing entry.
  Future<void> updateTransaction({
    required String id,
    required String accountId,
    required String categoryId,
    required int amountMinor,
    required DateTime date,
    required TxDirection direction,
    String payee,
    String note,
  });

  /// Soft-deletes an entry, keeping the row for a future sync or undo.
  Future<void> deleteTransaction(String id);

  /// Sets the recurring monthly budget for a category, in minor units.
  Future<void> setCategoryBudget({
    required String categoryId,
    required int budgetMinor,
  });

  /// Creates a user category.
  Future<void> addCategory({
    required String name,
    required CategoryKind kind,
    required int budgetMinor,
  });

  /// Soft-deletes a user category. System categories are refused.
  Future<void> deleteCategory(String categoryId);

  /// Creates a monthly rule that posts an entry like the one just recorded.
  ///
  /// The first occurrence is the month after [startedOn], because that entry is
  /// already in the ledger.
  ///
  /// [postMissedMonths] is false when the entry being made recurring already
  /// existed: the rule then starts from today rather than from the entry's month,
  /// so months the user may have recorded by hand are never posted a second time.
  Future<void> addRecurringRule({
    required String accountId,
    required String categoryId,
    required int amountMinor,
    required TxDirection direction,
    required DateTime startedOn,
    String payee,
    bool postMissedMonths,
  });

  /// Stops a rule. Entries it already posted are left alone.
  Future<void> stopRecurringRule(String ruleId);

  /// Populates six months of plausible history, for trying the app out.
  ///
  /// Returns the number of entries created.
  Future<int> loadSampleData();

  /// Soft-deletes every entry. Categories, accounts, and settings survive.
  Future<void> eraseTransactions();

  /// Soft-deletes only the entries created by [loadSampleData].
  ///
  /// Kept separate from [eraseTransactions] because "clear the demo data I
  /// loaded" and "delete my records" are different intentions that must not
  /// share a button.
  Future<void> eraseSampleData();

  /// Whether the database file on disk is genuinely encrypted.
  ///
  /// Exposed so the UI can state the truth rather than assume it.
  Future<bool> verifyEncrypted();

  /// Encrypts a complete snapshot of everything the user has recorded.
  ///
  /// The bytes are a self-contained file: they carry the data *and* its own
  /// encryption, keyed by [passphrase] rather than by anything on this device.
  /// That is what makes a backup usable after a reinstall or on another phone —
  /// the database key itself lives in the platform keystore and dies with the
  /// app, so it can never be what a backup relies on.
  Future<Uint8List> exportBackup({required String passphrase});

  /// Replaces everything stored with the contents of [bytes].
  ///
  /// Throws `BackupFailure` with a sentence the UI can show directly — a wrong
  /// passphrase, a foreign file, a backup from a newer release. Nothing is
  /// written in any of those cases: the replace happens in one transaction.
  Future<BackupRestoreReport> restoreBackup({
    required Uint8List bytes,
    required String passphrase,
  });

  /// Whether the app asks for a fingerprint or the device PIN before showing
  /// anything.
  ///
  /// Read at startup, before the first frame, so a locked app never renders the
  /// ledger for an instant while the setting is fetched.
  Future<bool> appLockEnabled();

  /// Turns the screen-level lock on or off.
  ///
  /// Persisted in the encrypted database beside every other setting, so the flag
  /// cannot be flipped by editing a plain file on a rooted device.
  Future<void> setAppLockEnabled(bool enabled);
}

/// What a restore put back, so the confirmation can state it in the user's own
/// terms rather than saying "done".
class BackupRestoreReport {
  const BackupRestoreReport({
    required this.transactions,
    required this.categories,
    required this.accounts,
    required this.recurringRules,
  });

  final int transactions;
  final int categories;
  final int accounts;
  final int recurringRules;
}
