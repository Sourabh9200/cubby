import 'finance_snapshot.dart';
import 'models.dart';
import 'stats_period.dart';

/// Views over a snapshot for any period, not only a month.
///
/// Every figure here is derived from the rows the snapshot already holds, which
/// is what guarantees the weekly, monthly, quarterly and yearly views cannot
/// disagree with each other: there is one implementation, and the month-shaped
/// methods in `snapshot_views.dart` are thin adapters onto it.
///
/// The month-shaped methods stay because most of the app still asks a monthly
/// question — the trend charts, the category averages, the assistant — and because
/// the *rules* the app is built on are monthly: budgets repeat monthly, and the
/// records card is a highest-and-lowest month on record.
extension PeriodViews on FinanceSnapshot {
  /// The period of [period] that contains today.
  StatsRange currentRange(StatsPeriod period) =>
      StatsRange.containing(period, now);

  /// Every live entry inside [range].
  List<Transaction> transactionsIn(StatsRange range) => transactions
      .where((txn) => range.contains(txn.date))
      .toList(growable: false);

  /// Income, spend, and investing for [range].
  ///
  /// Transfers are counted in none of the three: the two legs of a credit-card
  /// payment move money between accounts the user already owns, so counting them
  /// would inflate both sides of the month.
  PeriodTotals totalsFor(StatsRange range) {
    var expense = 0;
    var income = 0;
    var investment = 0;
    for (final txn in transactions) {
      if (!range.contains(txn.date)) {
        continue;
      }
      switch (txn.direction) {
        case TxDirection.expense:
          expense += txn.amountMinor;
        case TxDirection.income:
          income += txn.amountMinor;
        case TxDirection.investment:
          investment += txn.amountMinor;
        case TxDirection.transfer:
          break;
      }
    }
    return PeriodTotals(
      expenseMinor: expense,
      incomeMinor: income,
      investmentMinor: investment,
    );
  }

  /// Spend per category in [range], largest first.
  List<CategorySpend> spendIn(StatsRange range) =>
      _byCategory(range, TxDirection.expense);

  /// Amount invested per category in [range], largest first.
  List<CategorySpend> investedIn(StatsRange range) =>
      _byCategory(range, TxDirection.investment);

  /// Income received per source in [range], largest first.
  List<CategorySpend> incomeIn(StatsRange range) =>
      _byCategory(range, TxDirection.income);

  /// Largest individual expenses in [range].
  List<Transaction> topExpensesIn(StatsRange range, {int limit = 5}) {
    final candidates = transactionsIn(range)
        .where((txn) => txn.isExpense)
        .toList();
    candidates.sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    return candidates.take(limit).toList();
  }

  /// One category's totals for one direction inside [range].
  List<CategorySpend> _byCategory(StatsRange range, TxDirection direction) {
    final totals = <String, int>{};
    final counts = <String, int>{};
    for (final txn in transactions) {
      if (txn.direction != direction || !range.contains(txn.date)) {
        continue;
      }
      totals.update(
        txn.category,
        (value) => value + txn.amountMinor,
        ifAbsent: () => txn.amountMinor,
      );
      counts.update(txn.category, (value) => value + 1, ifAbsent: () => 1);
    }
    final spends = totals.entries
        .map(
          (entry) => CategorySpend(
            category: entry.key,
            totalMinor: entry.value,
            txnCount: counts[entry.key] ?? 0,
          ),
        )
        .toList();
    spends.sort((a, b) {
      final byTotal = b.totalMinor.compareTo(a.totalMinor);
      // Ties broken by name so the order is deterministic rather than whatever
      // insertion order the map happened to have.
      return byTotal != 0 ? byTotal : a.category.compareTo(b.category);
    });
    return spends;
  }

  /// Spending limits for [range], most at risk first.
  ///
  /// The limit is monthly, so it scales with the number of whole months the
  /// period covers — exactly for a quarter and a year, and not at all for a week,
  /// which covers no whole month. An empty list for a week is deliberate: the
  /// screen says why rather than drawing a bar against a limit stretched over the
  /// wrong number of days.
  ///
  /// [includeUnlimited] adds categories with spend in the period but no limit set,
  /// because the limit is optional in the category editor and a category that is
  /// being spent from should not vanish from the summary for lack of one.
  List<BudgetStatus> budgetStatusesIn(
    StatsRange range, {
    bool includeUnlimited = false,
  }) {
    final scale = range.period.monthsCovered;
    if (scale == 0) {
      return const <BudgetStatus>[];
    }
    final spend = <String, int>{
      for (final entry in spendIn(range)) entry.category: entry.totalMinor,
    };
    final statuses = categories
        .where(
          (category) =>
              category.isSpending &&
              (category.budgetMinor > 0 ||
                  (includeUnlimited && (spend[category.name] ?? 0) > 0)),
        )
        .map(
          (category) => BudgetStatus(
            category: category.name,
            spentMinor: spend[category.name] ?? 0,
            budgetMinor: category.budgetMinor * scale,
            kind: CategoryKind.expense,
          ),
        )
        .toList();
    statuses.sort((a, b) {
      final rankA = _attentionRank(a);
      final rankB = _attentionRank(b);
      if (rankA != rankB) {
        return rankA.compareTo(rankB);
      }
      return switch (rankA) {
        0 => b.fraction.compareTo(a.fraction),
        1 => b.spentMinor.compareTo(a.spentMinor),
        _ => a.category.compareTo(b.category),
      };
    });
    return statuses;
  }

  /// Investing targets for [range], closest to being met first.
  ///
  /// The target is monthly and scales with the period's whole months, exactly as
  /// a spending limit does. A week gets nothing, for the same reason: a monthly
  /// target stretched over seven days is an invented figure, and a target that is
  /// wrong is worse than no target.
  ///
  /// Sorted by progress descending — the opposite of [budgetStatusesIn]. For a
  /// target, being near the top is good news, so the user sees what they have
  /// already achieved before what they have not.
  List<BudgetStatus> investmentTargetsIn(StatsRange range) {
    final scale = range.period.monthsCovered;
    if (scale == 0) {
      return const <BudgetStatus>[];
    }
    final invested = <String, int>{
      for (final entry in investedIn(range)) entry.category: entry.totalMinor,
    };
    final statuses = categories
        .where((category) => category.isInvestment && category.budgetMinor > 0)
        .map(
          (category) => BudgetStatus(
            category: category.name,
            spentMinor: invested[category.name] ?? 0,
            budgetMinor: category.budgetMinor * scale,
            kind: CategoryKind.investment,
          ),
        )
        .toList();
    statuses.sort((a, b) => b.fraction.compareTo(a.fraction));
    return statuses;
  }

  /// Cumulative spend through each day of [range], in rupees.
  ///
  /// Index 0 is the origin; index N is the running total through day N of the
  /// period. A period still in progress stops at today rather than drawing a flat
  /// line to its end.
  List<double> cumulativeSpendIn(StatsRange range) {
    final byDay = <DateTime, int>{};
    for (final txn in transactions) {
      if (!txn.isExpense || !range.contains(txn.date)) {
        continue;
      }
      final day = DateTime(txn.date.year, txn.date.month, txn.date.day);
      byDay.update(
        day,
        (value) => value + txn.amountMinor,
        ifAbsent: () => txn.amountMinor,
      );
    }

    final lastDay = range.contains(now)
        ? now.difference(range.from).inDays + 1
        : range.days;
    final running = List<double>.filled(lastDay + 1, 0);
    var total = 0;
    for (var day = 1; day <= lastDay; day++) {
      total +=
          byDay[DateTime(
            range.from.year,
            range.from.month,
            range.from.day + day - 1,
          )] ??
          0;
      running[day] = total / 100;
    }
    return running;
  }

  /// Change in spend against the previous period of the same kind, as a
  /// percentage, or null when there is nothing to compare with.
  ///
  /// A period still in progress has the previous one scaled to the same point,
  /// because comparing a part-week against a whole week would read as a saving
  /// every single time.
  double? expenseChangeForRange(StatsRange range) {
    final previousTotal = totalsFor(range.step(-1)).expenseMinor;
    if (previousTotal == 0) {
      return null;
    }
    final scale = range.contains(now) ? range.elapsedFraction(now) : 1.0;
    final scaled = previousTotal * scale;
    if (scaled == 0) {
      return null;
    }
    return ((totalsFor(range).expenseMinor - scaled) / scaled) * 100;
  }
}

/// How much attention a budget row deserves, lowest first.
///
/// A limit being spent against is what a budget card exists for. Next is spending
/// with no limit, because it is money leaving that no bar is watching — ranking it
/// last would let a long list of untouched limits push the one row the user needs
/// to see off the end of a capped card. Last are limits nothing has touched, which
/// need no action at all.
int _attentionRank(BudgetStatus status) {
  if (status.hasLimit && status.spentMinor > 0) {
    return 0;
  }
  if (status.spentMinor > 0) {
    return 1;
  }
  return 2;
}
