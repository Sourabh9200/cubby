import 'package:drift/drift.dart' show Value;
import 'package:finance_db/finance_db.dart';
import 'package:flutter_test/flutter_test.dart';

/// Recurring rules: the date arithmetic and the posting.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  /// Inserts a rule directly, so each test states only what it cares about.
  Future<String> addRule({
    String id = 'rule-1',
    int amountMinor = 1800000,
    int dayOfMonth = 1,
    String startedOn = '2026-09-01',
    String? nextDueOn,
    EntryDirection direction = EntryDirection.expense,
    String categoryId = SeedIds.categoryRent,
    String payee = 'Monthly rent transfer',
    bool stopped = false,
  }) async {
    await db
        .into(db.recurringRules)
        .insert(
          RecurringRulesCompanion.insert(
            id: id,
            accountId: SeedIds.accountHdfc,
            categoryId: categoryId,
            amountMinor: Value<int>(amountMinor),
            currency: 'INR',
            direction: direction,
            payee: Value<String>(payee),
            frequency: RecurrenceFrequency.monthly,
            dayOfMonth: dayOfMonth,
            nextDueOn:
                nextDueOn ??
                nextOccurrenceAfter(iso: startedOn, dayOfMonth: dayOfMonth),
            startedOn: startedOn,
            createdAt: DateTime(2026, 9, 1),
            updatedAt: DateTime(2026, 9, 1),
            deletedAt: stopped
                ? Value<DateTime>(DateTime(2026, 9, 2))
                : const Value<DateTime>.absent(),
          ),
        );
    return id;
  }

  group('occurrence arithmetic', () {
    test('a short month clamps to its last day', () {
      // A rule on the 31st. Skipping the month would lose a rent payment, and
      // rolling into the 1st would file it under the wrong month's total.
      expect(
        monthlyOccurrence(year: 2026, month: 4, dayOfMonth: 31),
        DateTime(2026, 4, 30),
      );
      expect(
        monthlyOccurrence(year: 2026, month: 2, dayOfMonth: 31),
        DateTime(2026, 2, 28),
      );
      expect(
        monthlyOccurrence(year: 2026, month: 2, dayOfMonth: 30),
        DateTime(2026, 2, 28),
      );
      // A leap year still clamps, just one day later.
      expect(
        monthlyOccurrence(year: 2028, month: 2, dayOfMonth: 31),
        DateTime(2028, 2, 29),
      );
      // And a day that exists is left alone.
      expect(
        monthlyOccurrence(year: 2026, month: 3, dayOfMonth: 31),
        DateTime(2026, 3, 31),
      );
    });

    test('the next occurrence rolls the year over', () {
      expect(
        nextOccurrenceAfter(iso: '2026-12-01', dayOfMonth: 1),
        '2027-01-01',
      );
      // The clamped day is recomputed from the rule's own day, so a rule on the
      // 31st returns to the 31st as soon as a month is long enough.
      expect(
        nextOccurrenceAfter(iso: '2026-02-28', dayOfMonth: 31),
        '2026-03-31',
      );
    });

    test('the first occurrence is the month after the start', () {
      // The entry the rule was created from is already in the ledger, so
      // repeating from its own month would post that rent twice.
      expect(
        firstOccurrenceAfter(startedOn: '2026-09-01', dayOfMonth: 1),
        '2026-10-01',
      );
    });
  });

  group('materialising due occurrences', () {
    test('posts the occurrence and advances the due date', () async {
      // A rule due on the 1st, and it is now the 5th.
      await addRule(nextDueOn: '2026-10-01');

      final written = await materialiseDueRecurring(
        db,
        today: DateTime(2026, 10, 5),
      );
      expect(written, 1);

      final posted = (await db.watchLedger().first).single;
      expect(posted.categoryName, 'Rent');
      expect(posted.accountName, 'HDFC Savings');
      expect(posted.amountMinor, 1800000);
      expect(posted.payee, 'Monthly rent transfer');
      // Filed under the day it was due, not the day the app happened to open: an
      // entry dated the 5th would sit in the wrong week of the pace chart.
      expect(posted.occurredOn, '2026-10-01');
      expect(posted.direction, EntryDirection.expense);

      final rule = (await db.watchRecurringRules().first).single;
      expect(rule.nextDueOn, '2026-11-01');
    });

    test('running twice posts once', () async {
      // The property the app relies on across a crash or a double launch.
      await addRule(nextDueOn: '2026-10-01');

      final first = await materialiseDueRecurring(
        db,
        today: DateTime(2026, 10, 5),
      );
      final second = await materialiseDueRecurring(
        db,
        today: DateTime(2026, 10, 5),
      );

      expect(first, 1);
      expect(second, 0);
      expect(await db.watchLedger().first, hasLength(1));
      expect(
        (await db.watchRecurringRules().first).single.nextDueOn,
        '2026-11-01',
      );
    });

    test('a rule missed for months posts every month it was due', () async {
      // An app left alone for three months must gain all three months' rent. A
      // missing month in a household ledger is harder to notice than a wrong
      // total, which is why the catch-up is not optional.
      await addRule(nextDueOn: '2026-10-01');

      final written = await materialiseDueRecurring(
        db,
        today: DateTime(2026, 12, 20),
      );

      expect(written, 3);
      expect(
        (await db.watchLedger().first).map((row) => row.occurredOn),
        <String>['2026-12-01', '2026-11-01', '2026-10-01'],
      );
      expect(
        (await db.watchRecurringRules().first).single.nextDueOn,
        '2027-01-01',
      );
    });

    test('is capped, so a far-past due date cannot flood the ledger', () async {
      // A rule created from a heavily back-dated entry, or a device off for
      // years. Without a cap one bad date writes thousands of rows on launch.
      await addRule(nextDueOn: '2020-01-01');

      final written = await materialiseDueRecurring(
        db,
        today: DateTime(2026, 10, 5),
        maxOccurrencesPerRule: 12,
      );

      expect(written, 12);
      expect(await db.watchLedger().first, hasLength(12));
      // The rule stays due, so the remainder is posted by the next run rather
      // than being lost.
      expect(
        (await db.watchRecurringRules().first).single.nextDueOn,
        '2021-01-01',
      );
    });

    test('posts nothing before the due date', () async {
      await addRule(nextDueOn: '2026-11-01');

      expect(
        await materialiseDueRecurring(db, today: DateTime(2026, 10, 31)),
        0,
      );
      expect(await db.watchLedger().first, isEmpty);
    });

    test('a stopped rule posts nothing', () async {
      await addRule(nextDueOn: '2026-10-01', stopped: true);

      expect(
        await materialiseDueRecurring(db, today: DateTime(2026, 10, 5)),
        0,
      );
      expect(await db.watchLedger().first, isEmpty);
      expect(await db.watchRecurringRules().first, isEmpty);
    });

    test('an investing rule posts an investment, not a spend', () async {
      // The rule stores the direction rather than re-deriving it from the
      // category on every run, so a fund contribution cannot be posted as
      // consumption and inflate every spending total in the app.
      await addRule(
        nextDueOn: '2026-10-01',
        direction: EntryDirection.investment,
        categoryId: SeedIds.categoryMutualFunds,
        amountMinor: 2000000,
        payee: 'Index fund SIP',
      );

      await materialiseDueRecurring(db, today: DateTime(2026, 10, 5));

      final row = (await db.watchLedger().first).single;
      expect(row.isInvestment, isTrue);
      expect(row.isExpense, isFalse);

      final october = (await db.watchMonthTotals().first).firstWhere(
        (month) => month.month == 10,
      );
      expect(october.investmentMinor, 2000000);
      expect(october.expenseMinor, 0);
    });

    test('an income rule posts income', () async {
      await addRule(
        nextDueOn: '2026-10-01',
        direction: EntryDirection.income,
        categoryId: SeedIds.categoryIncome,
        amountMinor: 8000000,
        payee: 'Salary credit',
      );

      await materialiseDueRecurring(db, today: DateTime(2026, 10, 5));

      expect((await db.watchLedger().first).single.isIncome, isTrue);
      final october = (await db.watchMonthTotals().first).firstWhere(
        (month) => month.month == 10,
      );
      expect(october.incomeMinor, 8000000);
    });

    test('two rules each post their own month', () async {
      await addRule(id: 'rule-rent', nextDueOn: '2026-10-01', dayOfMonth: 1);
      await addRule(
        id: 'rule-sip',
        nextDueOn: '2026-10-07',
        dayOfMonth: 7,
        direction: EntryDirection.investment,
        categoryId: SeedIds.categoryMutualFunds,
        amountMinor: 500000,
        payee: 'SIP',
      );

      expect(
        await materialiseDueRecurring(db, today: DateTime(2026, 10, 8)),
        2,
      );
      expect(await db.watchLedger().first, hasLength(2));
      expect(
        (await db.watchRecurringRules().first).map((rule) => rule.nextDueOn),
        <String>['2026-11-01', '2026-11-07'],
      );
    });
  });
}
