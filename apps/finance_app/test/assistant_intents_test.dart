import 'package:finance_app/data/models.dart';
import 'package:finance_app/features/assistant/intent_matcher.dart';
import 'package:finance_app/features/assistant/local_engine.dart';
import 'package:finance_db/finance_db.dart' hide CategoryKind;
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

/// Tier 1.8: the deeper figures, asked for rather than shown.
///
/// The assistant is the opt-in surface: an intent is only ever run because the
/// user asked, so nothing here adds anything to a screen. What it must not do is
/// guess — a projection carries its basis (C5), a year-over-year comparison
/// refuses to exist without the year behind it (C7), and payee names are the
/// strings as recorded (C8). The outbound payload is a different question, and is
/// pinned by the redaction package's own tests.
void main() {
  group('matching', () {
    void expectIntent(String question, AssistantIntent intent) {
      expect(
        IntentMatcher.match(question).intent,
        intent,
        reason: 'question: $question',
      );
    }

    test('the deeper questions reach their own handler', () {
      expectIntent(
        'will I stay within budget this month?',
        AssistantIntent.forecast,
      );
      expectIntent('am I on track?', AssistantIntent.forecast);
      expectIntent('what is the projection?', AssistantIntent.forecast);
      expectIntent(
        'what subscriptions do I have?',
        AssistantIntent.subscriptions,
      );
      expectIntent('what repeats every month?', AssistantIntent.subscriptions);
      expectIntent(
        'which shops did I spend the most at?',
        AssistantIntent.payees,
      );
      expectIntent('who are my top payees?', AssistantIntent.payees);
      expectIntent(
        'how does this compare with last year?',
        AssistantIntent.yearOverYear,
      );
      expectIntent(
        'what did I spend a year ago?',
        AssistantIntent.yearOverYear,
      );
    });

    test('the more specific question wins', () {
      // "will I be over budget" is about the projection, not the position now.
      expectIntent(
        'will I be over budget this month?',
        AssistantIntent.forecast,
      );
      // "top places" is a payee question, even though it starts with "top".
      expectIntent('what are my top places?', AssistantIntent.payees);
      expectIntent(
        'how does this compare with last year?',
        AssistantIntent.yearOverYear,
      );
    });

    test('the questions that already worked still work', () {
      expectIntent(
        'how much did I spend this month?',
        AssistantIntent.monthTotal,
      );
      expectIntent(
        'how much did I spend on groceries?',
        AssistantIntent.categoryTotal,
      );
      expectIntent(
        'where is most of my money going?',
        AssistantIntent.breakdown,
      );
      expectIntent('am I over budget anywhere?', AssistantIntent.budgetCheck);
      expectIntent(
        'what was my biggest expense?',
        AssistantIntent.biggestExpense,
      );
      expectIntent(
        'how does this compare to my average?',
        AssistantIntent.comparison,
      );
      expectIntent('what is my savings rate?', AssistantIntent.savingsRate);
    });

    test('every suggestion lands on a real intent', () {
      for (final suggestion in LocalEngine.suggestions) {
        expect(
          IntentMatcher.match(suggestion).intent,
          isNot(AssistantIntent.fallback),
          reason: 'suggestion falls through: $suggestion',
        );
      }
    });
  });

  group('forecast', () {
    test('says so when there is nothing to project from', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);

      final reply = LocalEngine(await fixture.snapshot()).forecast();

      // Not enough history is the answer, never a confident estimate (C5, C11).
      expect(reply.intent, 'forecast');
      expect(reply.text, contains('Not enough history'));
    });

    test('projects the month and names its basis', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);
      for (final (date, amount) in <(DateTime, int)>[
        (DateTime(2026, 3, 1), 100000),
        (DateTime(2026, 4, 5), 120000),
        (DateTime(2026, 5, 5), 110000),
        (DateTime(2026, 6, 5), 130000),
        (DateTime(2026, 7, 5), 105000),
        (DateTime(2026, 8, 5), 115000),
        (DateTime(2026, 9, 5), 90000),
      ]) {
        await fixture.repository.addTransaction(
          accountId: SeedIds.accountHdfc,
          categoryId: SeedIds.categoryGroceries,
          amountMinor: amount,
          date: date,
          direction: TxDirection.expense,
          payee: 'BigBasket',
        );
      }

      final reply = LocalEngine(await fixture.snapshot()).forecast();

      expect(reply.text, contains('At this rate you land at'));
      expect(reply.text, contains('spent so far'));
      expect(reply.text, contains('of limits'));
      // The basis, and the label that stops it reading as a promise.
      expect(reply.text, contains('6 months of history'));
      expect(reply.text, contains('not a promise'));
    });
  });

  group('subscriptions', () {
    test('annualises what repeats', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);
      await fixture.repository.addRecurringRule(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryRent,
        amountMinor: 1800000,
        direction: TxDirection.expense,
        startedOn: testNow,
        payee: 'Monthly rent transfer',
      );

      final reply = LocalEngine(await fixture.snapshot()).subscriptions();

      expect(reply.intent, 'subscriptions');
      // ₹18,000 a month is ₹2,16,000 a year: the figure that makes anyone act.
      expect(reply.text, contains('₹2,16,000 a year'));
      expect(reply.text, contains('Monthly rent transfer'));
    });

    test('says nothing repeats when nothing does', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);

      expect(
        LocalEngine(await fixture.snapshot()).subscriptions().text,
        contains('Nothing repeats yet'),
      );
    });
  });

  group('payees', () {
    test('lists the places, as recorded', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);
      for (final (payee, amount) in <(String, int)>[
        ('BigBasket', 45000),
        ('BigBasket', 25000),
        ('Amazon', 80000),
      ]) {
        await fixture.repository.addTransaction(
          accountId: SeedIds.accountHdfc,
          categoryId: SeedIds.categoryGroceries,
          amountMinor: amount,
          date: DateTime(2026, 9, 5),
          direction: TxDirection.expense,
          payee: payee,
        );
      }

      final reply = LocalEngine(await fixture.snapshot()).payees();

      expect(reply.text, contains('Amazon — ₹800 across 1 entry'));
      expect(reply.text, contains('BigBasket — ₹700 across 2 entries'));
      expect(reply.sources, containsAll(<String>['Amazon', 'BigBasket']));
    });
  });

  group('year over year', () {
    test('refuses to compare without the year behind it', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);
      await fixture.repository.addTransaction(
        accountId: SeedIds.accountHdfc,
        categoryId: SeedIds.categoryGroceries,
        amountMinor: 100000,
        date: DateTime(2026, 9, 5),
        direction: TxDirection.expense,
        payee: 'BigBasket',
      );

      final reply = LocalEngine(await fixture.snapshot()).yearOverYear();

      expect(reply.intent, 'year_over_year');
      expect(reply.text, contains('same month a year ago'));
    });

    test('compares with the same days of the same month', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);
      for (final (date, amount, direction) in <(DateTime, int, TxDirection)>[
        (DateTime(2025, 9, 1), 5000000, TxDirection.income),
        (DateTime(2025, 9, 15), 3000000, TxDirection.expense),
        (DateTime(2026, 9, 5), 1500000, TxDirection.expense),
      ]) {
        await fixture.repository.addTransaction(
          accountId: SeedIds.accountHdfc,
          categoryId: direction == TxDirection.income
              ? SeedIds.categoryIncome
              : SeedIds.categoryGroceries,
          amountMinor: amount,
          date: date,
          direction: direction,
          payee: 'Test',
        );
      }

      final reply = LocalEngine(await fixture.snapshot()).yearOverYear();

      expect(reply.text, contains('September 2026 against the same days of'));
      expect(reply.text, contains('September 2025'));
      expect(reply.text, contains('spending up 15%'));
      expect(reply.text, contains('scaled'));
    });
  });
}
