import 'package:drift/drift.dart';

import '../database.dart';
import '../query_rows.dart';

/// Month and day aggregates.
extension MonthQueries on AppDatabase {
  /// Income, expense, and investment totals per calendar month, oldest first.
  ///
  /// Grouping is on the local ISO date, so a "month" here is the user's month,
  /// not UTC's. That distinction is invisible right up until a total disagrees
  /// with a bank statement.
  ///
  /// The three directions are summed in separate columns rather than folded
  /// together, because they answer different questions: expense is money gone,
  /// investment is money relocated, income is money arrived. Adding investment
  /// into the expense column would make a month in which the user saved more
  /// look like a month in which they spent more.
  Stream<List<MonthTotalRow>> watchMonthTotals() {
    return customSelect(
      '''
      SELECT CAST(substr(t.occurred_on, 1, 4) AS INTEGER) AS yr,
             CAST(substr(t.occurred_on, 6, 2) AS INTEGER) AS mo,
             COALESCE(SUM(CASE WHEN t.direction = 'expense'
                               THEN t.amount_minor ELSE 0 END), 0) AS expenseMinor,
             COALESCE(SUM(CASE WHEN t.direction = 'income'
                               THEN t.amount_minor ELSE 0 END), 0) AS incomeMinor,
             COALESCE(SUM(CASE WHEN t.direction = 'investment'
                               THEN t.amount_minor ELSE 0 END), 0) AS investmentMinor,
             COUNT(t.id) AS txnCount
        FROM transactions t
       WHERE t.deleted_at IS NULL
         AND t.direction IN ('expense', 'income', 'investment')
       GROUP BY yr, mo
       ORDER BY yr, mo
      ''',
      readsFrom: <ResultSetImplementation<Object, Object>>{transactions},
    ).watch().map(
      (rows) => rows
          .map(
            (row) => MonthTotalRow(
              year: row.read<int>('yr'),
              month: row.read<int>('mo'),
              expenseMinor: row.read<int>('expenseMinor'),
              incomeMinor: row.read<int>('incomeMinor'),
              investmentMinor: row.read<int>('investmentMinor'),
              txnCount: row.read<int>('txnCount'),
            ),
          )
          .toList(growable: false),
    );
  }

  /// Expense totals per day, for every month on record.
  ///
  /// All months in one read rather than one query per month, so the pace curve
  /// can follow whichever month the user selects without a query per step — and
  /// so every month's curve describes the same revision of the ledger.
  ///
  /// Deliberately excludes investments. The pace curve answers "am I burning
  /// through this month faster than usual", and money moved into a fund is not
  /// burning — counting it would make a diligent saver look like a big spender
  /// on the one day a month their SIP lands.
  Stream<List<DailyTotalRow>> watchDailyTotals() {
    return customSelect(
      '''
      SELECT substr(t.occurred_on, 1, 7) AS monthKey,
             CAST(substr(t.occurred_on, 9, 2) AS INTEGER) AS day,
             COALESCE(SUM(t.amount_minor), 0) AS totalMinor
        FROM transactions t
       WHERE t.deleted_at IS NULL
         AND t.direction = 'expense'
       GROUP BY monthKey, day
       ORDER BY monthKey, day
      ''',
      readsFrom: <ResultSetImplementation<Object, Object>>{transactions},
    ).watch().map(
      (rows) => rows
          .map(
            (row) => DailyTotalRow(
              monthKey: row.read<String>('monthKey'),
              day: row.read<int>('day'),
              totalMinor: row.read<int>('totalMinor'),
            ),
          )
          .toList(growable: false),
    );
  }
}
