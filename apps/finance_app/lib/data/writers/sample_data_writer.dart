import 'package:drift/drift.dart';
import 'package:finance_db/finance_db.dart';
import 'package:uuid/uuid.dart';

import '../demo_catalog.dart';

/// Populates the database with plausible history.
///
/// A real install starts empty, which is correct but useless for evaluating the
/// charts. This gives the user a one-tap way to see the app working with data
/// they can then erase. It is deliberately not run automatically: silently
/// inventing transactions in someone's finance app would be a betrayal of
/// trust, however well-intentioned.
class SampleDataWriter {
  SampleDataWriter(this.db);

  final AppDatabase db;

  static const Uuid _uuid = Uuid();

  /// How many months of history to generate, including the current one.
  static const int monthsBack = 5;

  /// Inserts the sample history and returns the number of entries created.
  ///
  /// Category and account ids are read from the database rather than hardcoded,
  /// so this keeps working if the seed set ever changes.
  Future<int> load() async {
    final accounts = await db.watchAccounts().first;
    final categories = await db.watchCategories().first;
    if (accounts.isEmpty || categories.isEmpty) {
      return 0;
    }

    // Match each spending profile to a real category by name, skipping any
    // profile whose category is missing.
    final categoryIdByName = <String, String>{
      for (final category in categories) category.name: category.id,
    };
    final incomeCategoryId = categories
        .firstWhere(
          (category) => category.kind == CategoryKind.income,
          orElse: () => categories.first,
        )
        .id;
    final primaryAccountId = accounts.first.id;

    final rng = DemoRng(20260913);
    final now = DateTime.now();
    final rows = <TransactionsCompanion>[];

    for (var back = monthsBack; back >= 0; back--) {
      final anchor = DateTime(now.year, now.month - back);
      final isCurrentMonth = back == 0;
      // Only generate up to today for the current month, so "month to date" is
      // genuinely partial rather than a finished month pretending otherwise.
      final lastDay = isCurrentMonth
          ? now.day
          : DateTime(anchor.year, anchor.month + 1, 0).day;

      for (final profile in demoProfiles) {
        final categoryId = categoryIdByName[profile.category];
        if (categoryId == null) {
          continue;
        }
        final basePaise = (profile.monthlyRupees * 100) ~/ profile.txnsPerMonth;
        for (var i = 0; i < profile.txnsPerMonth; i++) {
          final day = 1 + rng.nextInt(0, lastDay > 1 ? lastDay - 1 : 1);
          final jitter = 0.65 + rng.nextUnit() * 0.7;
          final amount = ((basePaise * jitter) / 100).round() * 100;
          final date = DateTime(anchor.year, anchor.month, day);
          rows.add(
            _row(
              categoryId: categoryId,
              accountId: rng.pick(accounts).id,
              amountMinor: amount,
              date: date,
              direction: EntryDirection.expense,
              payee: profile.category == 'Rent'
                  ? 'Rent - ${monthShortNames[anchor.month - 1]}'
                  : rng.pick(profile.payees),
            ),
          );
        }
      }

      // Salary on the 1st, plus occasional freelance income.
      final salaryDate = DateTime(anchor.year, anchor.month, 1);
      rows.add(
        _row(
          categoryId: incomeCategoryId,
          accountId: primaryAccountId,
          amountMinor: 8500000,
          date: salaryDate,
          direction: EntryDirection.income,
          payee: 'Salary credit',
        ),
      );

      if (rng.nextUnit() > 0.55) {
        final day = rng.nextInt(8, 24);
        final date = DateTime(anchor.year, anchor.month, day);
        rows.add(
          _row(
            categoryId: incomeCategoryId,
            accountId: primaryAccountId,
            amountMinor: rng.nextInt(8, 25) * 100000,
            date: date,
            direction: EntryDirection.income,
            payee: 'Freelance project',
          ),
        );
      }

      // Investments: a SIP on a fixed day, so the investing trend has a steady
      // baseline, plus an occasional lump-sum deposit.
      for (final profile in demoInvestmentProfiles) {
        final categoryId = categoryIdByName[profile.category];
        if (categoryId == null) {
          continue;
        }
        // Capped at today, so a partial current month never contains an
        // investment dated in the future.
        final day = lastDay < 5 ? lastDay : 5;
        rows.add(
          _row(
            categoryId: categoryId,
            accountId: primaryAccountId,
            amountMinor: profile.monthlyRupees * 100,
            date: DateTime(anchor.year, anchor.month, day),
            direction: EntryDirection.investment,
            payee: rng.pick(profile.payees),
          ),
        );
      }

      if (rng.nextUnit() > 0.7) {
        final depositCategoryId = categoryIdByName['Fixed Deposit'];
        if (depositCategoryId != null) {
          rows.add(
            _row(
              categoryId: depositCategoryId,
              accountId: primaryAccountId,
              amountMinor: rng.nextInt(25, 50) * 100000,
              date: DateTime(anchor.year, anchor.month, lastDay),
              direction: EntryDirection.investment,
              payee: 'Fixed deposit booking',
            ),
          );
        }
      }
    }

    await db.batch((Batch batch) => batch.insertAll(db.transactions, rows));
    return rows.length;
  }

  TransactionsCompanion _row({
    required String categoryId,
    required String accountId,
    required int amountMinor,
    required DateTime date,
    required EntryDirection direction,
    required String payee,
  }) {
    final created = DateTime.now();
    return TransactionsCompanion.insert(
      id: _uuid.v4(),
      accountId: accountId,
      categoryId: categoryId,
      amountMinor: Value<int>(amountMinor),
      currency: 'INR',
      direction: direction,
      occurredOn: isoDate(date),
      occurredAt: date,
      payee: Value<String>(payee),
      note: const Value<String>('Sample data'),
      isSample: const Value<bool>(true),
      createdAt: created,
      updatedAt: created,
    );
  }
}
