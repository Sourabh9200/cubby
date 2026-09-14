import 'package:drift/drift.dart';

import '../database.dart';
import '../query_rows.dart';
import 'row_parsing.dart';

/// Recurring-rule reads.
extension RecurringQueries on AppDatabase {
  /// Every live rule, soonest due first.
  ///
  /// Ordered by `next_due_on`, because the question this list answers is "what
  /// posts next". A `Stream` like every other read here, so stopping a rule or
  /// letting one post repaints the screen with no manual refresh.
  Stream<List<RecurringRuleRow>> watchRecurringRules() {
    return customSelect(
      '''
      SELECT r.id           AS id,
             r.account_id   AS accountId,
             a.name         AS accountName,
             r.category_id  AS categoryId,
             c.name         AS categoryName,
             r.amount_minor AS amountMinor,
             r.direction    AS direction,
             r.payee        AS payee,
             r.note         AS note,
             r.frequency    AS frequency,
             r.day_of_month AS dayOfMonth,
             r.next_due_on  AS nextDueOn,
             r.started_on   AS startedOn
        FROM recurring_rules r
        JOIN categories c ON c.id = r.category_id
        JOIN accounts   a ON a.id = r.account_id
       WHERE r.deleted_at IS NULL
       ORDER BY r.next_due_on, c.name
      ''',
      readsFrom: <ResultSetImplementation<Object, Object>>{
        recurringRules,
        categories,
        accounts,
      },
    ).watch().map(
      (rows) => rows
          .map(
            (row) => RecurringRuleRow(
              id: row.read<String>('id'),
              accountId: row.read<String>('accountId'),
              accountName: row.read<String>('accountName'),
              categoryId: row.read<String>('categoryId'),
              categoryName: row.read<String>('categoryName'),
              amountMinor: row.read<int>('amountMinor'),
              direction: parseDirection(row.read<String>('direction')),
              payee: row.read<String>('payee'),
              note: row.read<String>('note'),
              frequency: parseRecurrenceFrequency(
                row.read<String>('frequency'),
              ),
              dayOfMonth: row.read<int>('dayOfMonth'),
              nextDueOn: row.read<String>('nextDueOn'),
              startedOn: row.read<String>('startedOn'),
            ),
          )
          .toList(growable: false),
    );
  }
}
