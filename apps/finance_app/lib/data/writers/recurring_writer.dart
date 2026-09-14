import 'package:drift/drift.dart';
import 'package:finance_db/finance_db.dart' as db_layer;
import 'package:uuid/uuid.dart';

import '../models.dart';

/// Write operations on recurring rules.
///
/// The storage package is imported with a prefix because both layers name an
/// entry's direction differently; keeping the two types apart means a rename in
/// one cannot silently change what a rule posts.
class RecurringWriter {
  RecurringWriter(this.db);

  final db_layer.AppDatabase db;

  static const Uuid _uuid = Uuid();

  /// Creates a monthly rule from an entry the user has just recorded.
  ///
  /// [startedOn] is that entry's date, and the rule's first occurrence is the
  /// month *after* it: the entry itself is already in the ledger, so repeating
  /// from its own month would post the same rent twice.
  ///
  /// [postMissedMonths] decides what happens when the entry is not from this
  /// month. True — recording August's rent today — means September's is already
  /// due and gets posted, so the ledger is right the moment the user looks at it.
  /// False is for making an entry the user *already had* recurring: the anchor
  /// becomes today instead, because posting months before today could duplicate
  /// rows they entered by hand, and of the two errors only a duplicate is
  /// visible on screen.
  Future<String> add({
    required String accountId,
    required String categoryId,
    required int amountMinor,
    required TxDirection direction,
    required DateTime startedOn,
    String payee = '',
    bool postMissedMonths = true,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    final dayOfMonth = startedOn.day;
    final anchor = postMissedMonths ? startedOn : now;

    await db
        .into(db.recurringRules)
        .insert(
          db_layer.RecurringRulesCompanion.insert(
            id: id,
            accountId: accountId,
            categoryId: categoryId,
            amountMinor: Value<int>(amountMinor),
            currency: 'INR',
            direction: _direction(direction),
            payee: Value<String>(payee.trim()),
            frequency: db_layer.RecurrenceFrequency.monthly,
            // The day comes from the entry in both cases — rent falls on the 1st
            // whatever day the user happens to be editing it.
            dayOfMonth: dayOfMonth,
            nextDueOn: db_layer.firstOccurrenceAfter(
              startedOn: db_layer.isoDate(anchor),
              dayOfMonth: dayOfMonth,
            ),
            startedOn: db_layer.isoDate(anchor),
            createdAt: now,
            updatedAt: now,
          ),
        );

    // Harmless when nothing is due — the call is idempotent — and it is what
    // makes a back-dated first entry visible in the ledger immediately rather
    // than after the next launch.
    await db_layer.materialiseDueRecurring(db, today: now);
    return id;
  }

  /// Stops a rule.
  ///
  /// Entries it already posted are ordinary ledger rows and are left alone:
  /// "not again" is not "erase the rent you already paid".
  Future<void> stop(String ruleId) async {
    final now = DateTime.now();
    await (db.update(
      db.recurringRules,
    )..where((rule) => rule.id.equals(ruleId))).write(
      db_layer.RecurringRulesCompanion(
        deletedAt: Value<DateTime>(now),
        updatedAt: Value<DateTime>(now),
      ),
    );
  }

  /// Maps the UI enum onto the storage enum.
  static db_layer.EntryDirection _direction(TxDirection direction) =>
      switch (direction) {
        TxDirection.income => db_layer.EntryDirection.income,
        TxDirection.transfer => db_layer.EntryDirection.transfer,
        TxDirection.investment => db_layer.EntryDirection.investment,
        TxDirection.expense => db_layer.EntryDirection.expense,
      };
}
