import 'package:drift/drift.dart';
import 'package:finance_db/finance_db.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';

/// Write operations on the ledger.
///
/// A separate class rather than methods on the repository so that the read
/// path (which builds snapshots) and the write path (which mutates) can be
/// tested independently, and so neither file grows unbounded.
class TransactionWriter {
  TransactionWriter(this.db);

  final AppDatabase db;

  static const Uuid _uuid = Uuid();

  /// Records a new entry, generating a UUID primary key.
  Future<void> add({
    required String accountId,
    required String categoryId,
    required int amountMinor,
    required DateTime date,
    required TxDirection direction,
    String payee = '',
    String note = '',
  }) => _insert(
    id: _uuid.v4(),
    accountId: accountId,
    categoryId: categoryId,
    amountMinor: amountMinor,
    date: date,
    direction: direction,
    payee: payee,
    note: note,
  );

  /// Replaces an existing entry, preserving its id and creation time.
  Future<void> update({
    required String id,
    required String accountId,
    required String categoryId,
    required int amountMinor,
    required DateTime date,
    required TxDirection direction,
    String payee = '',
    String note = '',
  }) async {
    await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        accountId: Value<String>(accountId),
        categoryId: Value<String>(categoryId),
        amountMinor: Value<int>(amountMinor),
        direction: Value<EntryDirection>(_direction(direction)),
        // Both date columns move together: `occurredOn` is what grouping reads,
        // and leaving it stale would silently file the entry under the old day.
        occurredOn: Value<String>(isoDate(date)),
        occurredAt: Value<DateTime>(date),
        payee: Value<String>(payee.trim()),
        note: Value<String>(note.trim()),
        updatedAt: Value<DateTime>(DateTime.now()),
      ),
    );
  }

  /// Soft-deletes an entry.
  ///
  /// The row survives so a future sync can propagate the deletion and so an
  /// accidental swipe can be undone. Hard deletion of a financial record is
  /// almost never what the user actually wants.
  Future<void> softDelete(String id) async {
    await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        deletedAt: Value<DateTime>(DateTime.now()),
        updatedAt: Value<DateTime>(DateTime.now()),
      ),
    );
  }

  /// Soft-deletes every live entry.
  Future<void> softDeleteAll() async {
    await (db.update(
      db.transactions,
    )..where((t) => t.deletedAt.isNull())).write(
      TransactionsCompanion(
        deletedAt: Value<DateTime>(DateTime.now()),
        updatedAt: Value<DateTime>(DateTime.now()),
      ),
    );
  }

  /// Soft-deletes only the rows created by "Load sample data".
  ///
  /// Guarantees that clearing the sample set cannot touch a row the user typed.
  /// That is the entire reason `is_sample` is a column rather than a marker in
  /// the free-text note: text the user can write is text that can be matched
  /// against by mistake, and the cost of that mistake is deleted financial
  /// records.
  Future<void> softDeleteSampleData() async {
    await (db.update(
      db.transactions,
    )..where((t) => t.deletedAt.isNull() & t.isSample.equals(true))).write(
      TransactionsCompanion(
        deletedAt: Value<DateTime>(DateTime.now()),
        updatedAt: Value<DateTime>(DateTime.now()),
      ),
    );
  }

  Future<void> _insert({
    required String id,
    required String accountId,
    required String categoryId,
    required int amountMinor,
    required DateTime date,
    required TxDirection direction,
    required String payee,
    required String note,
  }) async {
    final now = DateTime.now();
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: id,
            accountId: accountId,
            categoryId: categoryId,
            amountMinor: Value<int>(amountMinor),
            currency: 'INR',
            direction: _direction(direction),
            occurredOn: isoDate(date),
            occurredAt: date,
            payee: Value<String>(payee.trim()),
            note: Value<String>(note.trim()),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  /// Maps the UI enum onto the storage enum.
  ///
  /// They are deliberately distinct types: the UI's `TxDirection` should not
  /// change shape just because a storage column does.
  static EntryDirection _direction(TxDirection direction) =>
      switch (direction) {
        TxDirection.income => EntryDirection.income,
        TxDirection.transfer => EntryDirection.transfer,
        TxDirection.investment => EntryDirection.investment,
        TxDirection.expense => EntryDirection.expense,
      };
}
