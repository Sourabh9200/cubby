/// Recurring rules: the date arithmetic, and posting what has fallen due.
///
/// Kept out of the query extensions because this is the only place in the package
/// that *writes* to the ledger on a schedule, and it is worth being able to read
/// the whole of it in one file.
library;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import 'queries/row_parsing.dart';
import 'tables.dart';

const Uuid _uuid = Uuid();

/// The day a monthly occurrence falls on in a given month.
///
/// Clamped to the month's last day, so a rule on the 31st lands on the 30th in
/// April and the 28th in February. The alternatives are both worse: skipping the
/// month silently loses a rent payment, and rolling into the 1st of the next
/// month files it under the wrong month's total.
DateTime monthlyOccurrence({
  required int year,
  required int month,
  required int dayOfMonth,
}) {
  final lastDay = DateTime(year, month + 1, 0).day;
  final day = dayOfMonth > lastDay ? lastDay : dayOfMonth;
  return DateTime(year, month, day);
}

/// The occurrence after [iso] for a rule that falls on [dayOfMonth].
///
/// `DateTime(year, month + 1)` rather than adding days, so December rolls into
/// January of the next year and February is the right length.
String nextOccurrenceAfter({required String iso, required int dayOfMonth}) {
  final current = DateTime.parse(iso);
  final next = DateTime(current.year, current.month + 1);
  return isoDate(
    monthlyOccurrence(
      year: next.year,
      month: next.month,
      dayOfMonth: dayOfMonth,
    ),
  );
}

/// The first occurrence of a rule that started on [startedOn].
///
/// The month *after* the start, because the entry the rule was created from is
/// already in the ledger: repeating it from its own month would post that rent
/// twice.
String firstOccurrenceAfter({
  required String startedOn,
  required int dayOfMonth,
}) => nextOccurrenceAfter(iso: startedOn, dayOfMonth: dayOfMonth);

/// Posts every occurrence of every live rule that has fallen due by [today].
///
/// Returns how many ledger entries were written.
///
/// Called on every open, so an app left alone for three months gains all three
/// months' rent rather than only the most recent one — a missing month in a
/// household ledger is harder to notice than a wrong total.
///
/// Idempotent by construction rather than by a guard flag: each rule's
/// `next_due_on` advances in the same batch that writes its rows, so a second
/// call, a restart, or a crash mid-post cannot duplicate a month.
///
/// [maxOccurrencesPerRule] bounds a rule whose due date is far in the past — a
/// rule created from a heavily back-dated entry, or a device that has been off
/// for years. Without it, one bad date could write thousands of rows on launch.
Future<int> materialiseDueRecurring(
  AppDatabase db, {
  required DateTime today,
  int maxOccurrencesPerRule = 60,
}) async {
  final active = await (db.select(
    db.recurringRules,
  )..where((rule) => rule.deletedAt.isNull())).get();
  if (active.isEmpty) {
    return 0;
  }

  final now = DateTime.now();
  final todayIso = isoDate(today);
  var written = 0;

  for (final rule in active) {
    final rows = <TransactionsCompanion>[];
    var due = rule.nextDueOn;
    var dueDate = DateTime.parse(due);

    while (rows.length < maxOccurrencesPerRule &&
        !dueDate.isAfter(DateTime.parse(todayIso))) {
      rows.add(
        TransactionsCompanion.insert(
          id: _uuid.v4(),
          accountId: rule.accountId,
          categoryId: rule.categoryId,
          amountMinor: Value<int>(rule.amountMinor),
          currency: rule.currency,
          direction: rule.direction,
          // `occurred_on` is the local ISO date and is what every aggregate
          // groups on; `occurred_at` is kept in step so the two never disagree
          // about which day this was.
          occurredOn: due,
          occurredAt: dueDate,
          payee: Value<String>(rule.payee),
          note: Value<String>(rule.note),
          createdAt: now,
          updatedAt: now,
        ),
      );
      due = nextOccurrenceAfter(iso: due, dayOfMonth: rule.dayOfMonth);
      dueDate = DateTime.parse(due);
    }

    if (rows.isEmpty) {
      continue;
    }

    // The rows and the advance of `next_due_on` go together or not at all. Two
    // separate writes would allow the entries to land while the due date stayed
    // put, which duplicates a month's rent on the next open.
    await db.batch(
      (Batch batch) => batch
        ..insertAll(db.transactions, rows)
        ..update(
          db.recurringRules,
          RecurringRulesCompanion(
            nextDueOn: Value<String>(due),
            updatedAt: Value<DateTime>(now),
          ),
          where: (RecurringRules table) => table.id.equals(rule.id),
        ),
    );
    written += rows.length;
  }

  return written;
}
