import 'package:finance_app/data/account_balance.dart';
import 'package:finance_app/data/finance_snapshot.dart';
import 'package:finance_app/data/models.dart';
import 'package:finance_app/data/period_views.dart';
import 'package:finance_app/data/stats_period.dart';
import 'package:finance_db/finance_db.dart' hide CategoryKind;
import 'package:flutter_test/flutter_test.dart';

import 'support/fixture.dart';

/// Tier 1.7: what the user owns less what they owe, month by month, at cost.
///
/// Two things this file exists to pin. The replay has to agree with the balance
/// the database computes — otherwise the line and the accounts screen would
/// disagree while looking identical. And the figure has to say *at cost*: an
/// investment moves money sideways, so it must not change net worth, which is
/// exactly what the old "is this spending or saving" confusion gets wrong (C1,
/// C3).
void main() {
  /// A movement in the bank account. The replay matches on `accountId`, which is
  /// why these helpers exist rather than bare `movementOn` calls: a transaction
  /// pointing at an account the snapshot does not carry is silently not part of
  /// the balance, exactly as it should be.
  Transaction inBank(DateTime date, int amountMinor, TxDirection direction) =>
      movementOn(date, amountMinor, direction, accountId: 'acc-bank');

  /// A purchase on the credit card.
  Transaction onCard(DateTime date, int amountMinor) => movementOn(
    date,
    amountMinor,
    TxDirection.expense,
    account: 'ICICI Card',
    accountId: 'acc-card',
  );

  /// A bank account with ₹50,000 in it and an empty credit card, plus a month of
  /// movements: income, an expense, an investment, and a card purchase.
  FinanceSnapshot movementsFixture({List<Transaction> extra = const []}) =>
      snapshotWith(
        accounts: <AccountBalance>[
          const AccountBalance(
            id: 'acc-bank',
            name: 'HDFC Savings',
            type: 'bank',
            openingBalanceMinor: 5000000,
            balanceMinor: 5500000,
          ),
          const AccountBalance(
            id: 'acc-card',
            name: 'ICICI Card',
            type: 'creditCard',
            openingBalanceMinor: 0,
            balanceMinor: -300000,
          ),
        ],
        transactions: <Transaction>[
          inBank(DateTime(2026, 9, 1), 2000000, TxDirection.income),
          inBank(DateTime(2026, 9, 5), 500000, TxDirection.expense),
          inBank(DateTime(2026, 9, 6), 1000000, TxDirection.investment),
          onCard(DateTime(2026, 9, 7), 300000),
          ...extra,
        ],
      );

  test('splits a balance into what is liquid, owed, and invested', () {
    final point = movementsFixture().currentNetWorth;

    // Bank: 50,000 + 20,000 income − 5,000 spent − 10,000 invested.
    expect(point.liquidMinor, 5500000);
    // A card balance is money owed, so it is negative.
    expect(point.cardMinor, -300000);
    expect(point.investedMinor, 1000000);
    // 55,000 − 3,000 + 10,000 invested at cost.
    expect(point.netWorthMinor, 6200000);
    expect(point.liquidNetWorthMinor, 5200000);
    expect(point.isEmpty, isFalse);
  });

  test('an investment moves money sideways, so it does not change net worth', () {
    FinanceSnapshot single(TxDirection direction) => snapshotWith(
      accounts: <AccountBalance>[
        const AccountBalance(
          id: 'acc-bank',
          name: 'HDFC Savings',
          type: 'bank',
          openingBalanceMinor: 1000000,
          balanceMinor: 800000,
        ),
      ],
      transactions: <Transaction>[
        inBank(DateTime(2026, 9, 5), 200000, direction),
      ],
    );
    final spent = single(TxDirection.expense);
    final invested = single(TxDirection.investment);

    // ₹1,000 consumed leaves ₹8,000 to own; ₹1,000 put into a fund leaves
    // ₹8,000 liquid *and* ₹1,000 at cost, which is still ₹10,000 of net worth.
    expect(spent.currentNetWorth.netWorthMinor, 800000);
    expect(invested.currentNetWorth.netWorthMinor, 1000000);
    expect(invested.currentNetWorth.liquidNetWorthMinor, 800000);
  });

  test('income moves it by exactly its own amount', () {
    expect(
      movementsFixture(
        extra: <Transaction>[
          inBank(DateTime(2026, 8, 20), 700000, TxDirection.income),
        ],
      ).currentNetWorth.netWorthMinor,
      // Opening ₹50,000 + income ₹20,000 + ₹7,000 back-dated, less ₹8,000 spent,
      // with the ₹10,000 investment counted at cost.
      6200000 + 700000,
    );
  });

  test('a month in progress is today, not a projection of the month', () {
    final snapshot = movementsFixture(
      extra: <Transaction>[
        inBank(DateTime(2026, 9, 25), 999900, TxDirection.expense),
      ],
    );

    // A balance is a stock: the point for September is the balance *today*, and a
    // spend dated later in the month is not in it. (This is also why the SQL
    // total can differ from the replay whenever future-dated rows exist — the
    // entry sheet refuses to create one.)
    expect(snapshot.currentNetWorth.liquidMinor, 5500000);
    expect(snapshot.currentNetWorth.month, DateTime(2026, 9));
  });

  test('every earlier month end is the balance on its last day', () {
    final points = movementsFixture(
      // History from January, so the line has earlier month ends to show.
      extra: <Transaction>[
        inBank(DateTime(2026, 1, 10), 1000000, TxDirection.income),
      ],
    ).netWorthSeries(StatsRange.containing(StatsPeriod.year, testNow));

    // January through September, each labelled with the month it ends.
    expect(points, hasLength(9));
    expect(points.first.month, DateTime(2026));
    expect(points.last.month, DateTime(2026, 9));
    // Nothing but the opening balance and January's income by the 31st.
    expect(points.first.netWorthMinor, 6000000);
    expect(points.first.investedMinor, 0);
    // By the end of September: ₹62,000 plus the ₹10,000 that came in January.
    expect(points.last.netWorthMinor, 7200000);
  });

  test('the line starts at the ledger, never before it', () {
    final points = movementsFixture().netWorthSeries(
      StatsRange.containing(StatsPeriod.year, testNow),
    );

    // January through August are not drawn: the only entry is in September, and
    // a month before the first entry would show the account's opening balance as
    // if the user had had it then (C7).
    expect(points, hasLength(1));
    expect(points.single.month, DateTime(2026, 9));
  });

  test('a closed range stops at the month it covers', () {
    final points =
        movementsFixture(
          extra: <Transaction>[
            inBank(DateTime(2026, 1, 10), 1000000, TxDirection.income),
          ],
        ).netWorthSeries(
          StatsRange.containing(StatsPeriod.quarter, DateTime(2026, 5, 10)),
        );

    expect(points.map((point) => point.month), <DateTime>[
      DateTime(2026, 4),
      DateTime(2026, 5),
      DateTime(2026, 6),
    ]);
  });

  test('no accounts is a zero balance, not a missing line', () {
    final point = snapshotWith().currentNetWorth;

    expect(point.netWorthMinor, 0);
    expect(point.isEmpty, isTrue);
  });

  group('against the database', () {
    test('the replay agrees with the balance the query computes', () async {
      final fixture = makeFixture();
      addTearDown(fixture.dispose);
      for (final (date, amount, categoryId, direction, accountId)
          in <(DateTime, int, String, TxDirection, String)>[
            (
              DateTime(2026, 9, 1),
              8000000,
              SeedIds.categoryIncome,
              TxDirection.income,
              SeedIds.accountHdfc,
            ),
            (
              DateTime(2026, 9, 5),
              45000,
              SeedIds.categoryGroceries,
              TxDirection.expense,
              SeedIds.accountHdfc,
            ),
            (
              DateTime(2026, 9, 6),
              200000,
              SeedIds.categoryMutualFunds,
              TxDirection.investment,
              SeedIds.accountHdfc,
            ),
            (
              DateTime(2026, 9, 7),
              150000,
              SeedIds.categoryShopping,
              TxDirection.expense,
              SeedIds.accountCreditCard,
            ),
          ]) {
        await fixture.repository.addTransaction(
          accountId: accountId,
          categoryId: categoryId,
          amountMinor: amount,
          date: date,
          direction: direction,
          payee: 'Test',
        );
      }

      final snapshot = await fixture.snapshot();
      final today = snapshot.currentNetWorth;
      final fromQuery = snapshot.accounts.fold(
        0,
        (total, account) => total + account.balanceMinor,
      );

      // The line and the accounts query have to describe the same money: one
      // replays the ledger, the other sums it in SQL.
      expect(today.liquidMinor + today.cardMinor, fromQuery);
      expect(today.investedMinor, 200000);
      expect(today.netWorthMinor, fromQuery + 200000);
    });

    test(
      'transfer legs are skipped by both, so neither invents a sign',
      () async {
        final fixture = makeFixture();
        addTearDown(fixture.dispose);
        // Transfers are schema-ready but not exposed yet, so the app cannot create
        // one; the arithmetic still has to be right the day it can (C2).
        for (final accountId in <String>[
          SeedIds.accountHdfc,
          SeedIds.accountCreditCard,
        ]) {
          await fixture.repository.addTransaction(
            accountId: accountId,
            categoryId: SeedIds.categoryMisc,
            amountMinor: 500000,
            date: DateTime(2026, 9, 8),
            direction: TxDirection.transfer,
            payee: 'Card payment',
          );
        }

        final snapshot = await fixture.snapshot();
        final today = snapshot.currentNetWorth;
        final fromQuery = snapshot.accounts.fold(
          0,
          (total, account) => total + account.balanceMinor,
        );

        expect(today.liquidMinor + today.cardMinor, fromQuery);
      },
    );
  });
}
