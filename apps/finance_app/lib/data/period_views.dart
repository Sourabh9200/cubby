import 'budget_pace.dart';
import 'composition.dart';
import 'finance_snapshot.dart';
import 'models.dart';
import 'net_worth.dart';
import 'payee_totals.dart';
import 'period_comparison.dart';
import 'projection.dart';
import 'spending_rhythm.dart';
import 'statistics.dart';
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

  /// Income split into what was spent, what was invested, and what was left
  /// unallocated, for [range].
  ///
  /// Derived from [totalsFor] rather than summed again, because composition is a
  /// re-arrangement of figures that already exist: a second set of sums is a
  /// second chance for the headline and this card to disagree.
  CompositionTotals compositionFor(StatsRange range) =>
      CompositionTotals.from(totalsFor(range));

  /// One composition per month of [range], oldest first.
  ///
  /// A month with nothing recorded still gets a column — a gap has to read as a
  /// short column, not as a missing month — but months after today are not drawn
  /// at all, because they cannot hold anything and empty columns would read as a
  /// collapse in saving (C6).
  ///
  /// Edge months are clipped to [range], so a weekly range reports the part of
  /// its month that actually falls inside it, and [CompositionPoint.isPartial]
  /// is true for any column that covers only part of its month.
  List<CompositionPoint> compositionByMonthIn(StatsRange range) {
    final lastMonth = range.contains(now)
        ? DateTime(now.year, now.month)
        : DateTime(range.to.year, range.to.month - 1);
    final points = <CompositionPoint>[];
    var month = DateTime(range.from.year, range.from.month);
    while (!month.isAfter(lastMonth)) {
      final monthEnd = DateTime(month.year, month.month + 1);
      final start = month.isBefore(range.from) ? range.from : month;
      final end = monthEnd.isAfter(range.to) ? range.to : monthEnd;
      final partial =
          start != month ||
          end != monthEnd ||
          (range.contains(now) &&
              month.year == now.year &&
              month.month == now.month);
      points.add(
        CompositionPoint(
          month: month,
          totals: compositionFor(
            StatsRange(period: range.period, from: start, to: end),
          ),
          isPartial: partial,
        ),
      );
      month = monthEnd;
    }
    return points;
  }

  /// [range] against the same window a year earlier, or null when the ledger
  /// does not hold a full year of history before [range].
  ///
  /// Null rather than a comparison against a half-covered window: last year's
  /// fortnight measured against this year's whole month would read as growth
  /// that never happened, and it would read that way every time (C7, C6).
  PeriodComparison? yearOverYearFor(StatsRange range) {
    final first = firstRecordedDay;
    final previous = range.oneYearEarlier();
    if (first == null || previous.from.isBefore(first)) {
      return null;
    }
    return PeriodComparison(
      range: range,
      current: totalsFor(range),
      previous: totalsFor(previous),
      // Scaled only while the range is still running: a period that is over is
      // compared whole against a whole one, because scaling there would invent a
      // figure that never happened.
      previousScale: range.contains(now) ? range.elapsedFraction(now) : 1.0,
    );
  }

  /// Change in spend against the same window a year earlier, as a percentage,
  /// or null when there is no comparable year.
  double? expenseChangeYearOverYear(StatsRange range) =>
      yearOverYearFor(range)?.expenseChangePercent;

  /// [range] against the span immediately before it, or null when that span is
  /// not wholly inside the ledger.
  ///
  /// The same arithmetic as [yearOverYearFor] over a different earlier span —
  /// which for a custom range is the same number of days, because holding the
  /// span length constant is the only way the two windows are comparable.
  ///
  /// Stricter than [expenseChangeForRange], which has no history guard: that one
  /// is the overview's quick delta, read as a nudge beside a headline figure, and
  /// its behaviour is pinned by tests. This one is what a report states as a
  /// fact, so a ledger that began on the 20th reports nothing rather than
  /// comparing against the previous month's ten days and showing a fivefold rise
  /// in spending for a reason that has nothing to do with the user's money (C7).
  PeriodComparison? previousPeriodComparison(StatsRange range) {
    final previous = range.step(-1);
    final first = firstRecordedDay;
    if (first == null || previous.from.isBefore(first)) {
      return null;
    }
    return PeriodComparison(
      range: range,
      current: totalsFor(range),
      previous: totalsFor(previous),
      previousScale: range.contains(now) ? range.elapsedFraction(now) : 1.0,
    );
  }

  /// Spend per payee in [range], largest first.
  ///
  /// Expenses only. A category says *what* was bought; a payee says *where*, and
  /// a salary credit's payee is not a place. Entries with no payee recorded are
  /// left out rather than collected under a blank row: an entry nobody
  /// attributed cannot be attributed by the app (C8).
  List<PayeeTotal> topPayeesIn(StatsRange range, {int limit = 5}) =>
      payeeTotalsIn(range).take(limit).toList(growable: false);

  /// Every payee paid in [range], largest total first.
  ///
  /// The unpaged list behind [topPayeesIn] and [mostFrequentPayeeIn], so the two
  /// rankings cannot disagree about how much a payee was paid. Callers that draw
  /// a list want [topPayeesIn]; this exists for the ones that ask a different
  /// question of the same sums.
  List<PayeeTotal> payeeTotalsIn(StatsRange range) {
    final totals = <String, int>{};
    final counts = <String, int>{};
    for (final txn in transactions) {
      if (!txn.isExpense || !range.contains(txn.date)) {
        continue;
      }
      final payee = txn.payee.trim();
      if (payee.isEmpty) {
        continue;
      }
      totals.update(
        payee,
        (value) => value + txn.amountMinor,
        ifAbsent: () => txn.amountMinor,
      );
      counts.update(payee, (value) => value + 1, ifAbsent: () => 1);
    }
    final payees = totals.entries
        .map(
          (entry) => PayeeTotal(
            payee: entry.key,
            totalMinor: entry.value,
            count: counts[entry.key] ?? 0,
          ),
        )
        .toList();
    payees.sort((a, b) {
      final byTotal = b.totalMinor.compareTo(a.totalMinor);
      // Ties broken by name so the order is deterministic rather than whatever
      // insertion order the map happened to have.
      return byTotal != 0 ? byTotal : a.payee.compareTo(b.payee);
    });
    return payees;
  }

  /// The payee with the most entries in [range], or null when nothing was paid.
  ///
  /// A different question from [topPayeesIn], and the one a year in review asks:
  /// the coffee shop visited forty times says more about a year than the rent
  /// paid twelve times, even though the rent is the larger total. Ties go to the
  /// larger total, then to the name, so the answer is stable between rebuilds.
  PayeeTotal? mostFrequentPayeeIn(StatsRange range) {
    final payees = List<PayeeTotal>.of(payeeTotalsIn(range));
    if (payees.isEmpty) {
      return null;
    }
    payees.sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      if (byCount != 0) {
        return byCount;
      }
      final byTotal = b.totalMinor.compareTo(a.totalMinor);
      return byTotal != 0 ? byTotal : a.payee.compareTo(b.payee);
    });
    return payees.first;
  }

  /// Every expense recorded against [payee], newest first.
  ///
  /// The one filter the payee figures are built from, so the drill-down's list,
  /// its total and its monthly series cannot disagree about what belongs to the
  /// merchant. Names are matched exactly as recorded (C8).
  List<Transaction> payeeEntries(String payee) {
    final name = payee.trim();
    return transactions
        .where((txn) => txn.isExpense && txn.payee.trim() == name)
        .toList(growable: false);
  }

  /// One payee's whole recorded spend.
  PayeeTotal payeeTotalFor(String payee) {
    final entries = payeeEntries(payee);
    var total = 0;
    for (final txn in entries) {
      total += txn.amountMinor;
    }
    return PayeeTotal(
      payee: payee.trim(),
      totalMinor: total,
      count: entries.length,
    );
  }

  /// One payee's spend month by month, over everything recorded, oldest first.
  List<PayeeMonthTotal> payeeSeries(String payee) {
    final totals = <DateTime, int>{};
    final counts = <DateTime, int>{};
    for (final txn in payeeEntries(payee)) {
      final month = DateTime(txn.date.year, txn.date.month);
      totals.update(
        month,
        (value) => value + txn.amountMinor,
        ifAbsent: () => txn.amountMinor,
      );
      counts.update(month, (value) => value + 1, ifAbsent: () => 1);
    }
    final months = totals.keys.toList()..sort();
    return <PayeeMonthTotal>[
      for (final month in months)
        PayeeMonthTotal(
          month: month,
          totalMinor: totals[month]!,
          count: counts[month]!,
        ),
    ];
  }

  /// How spending falls across the days of the week in [range].
  ///
  /// Every statement this supports is about the ledger rather than about
  /// behaviour: a quiet day is a day nothing was recorded, and cash never passes
  /// through this app between deposits (C11).
  SpendingRhythm spendingRhythmIn(StatsRange range) {
    final totals = List<int>.filled(DateTime.sunday + 1, 0);
    final active = <DateTime>{};
    var total = 0;
    for (final txn in transactions) {
      if (!txn.isExpense || !range.contains(txn.date)) {
        continue;
      }
      totals[txn.date.weekday] += txn.amountMinor;
      active.add(DateTime(txn.date.year, txn.date.month, txn.date.day));
      total += txn.amountMinor;
    }

    // Days of the range that have happened, counted the way the pace curve
    // counts them: a range still running stops at today rather than crediting
    // the future with quiet days it has not had.
    final recordedDays = range.contains(now)
        ? now.difference(range.from).inDays + 1
        : range.days;
    final daysPerWeekday = List<int>.filled(DateTime.sunday + 1, 0);
    for (var offset = 0; offset < recordedDays; offset++) {
      daysPerWeekday[DateTime(
        range.from.year,
        range.from.month,
        range.from.day + offset,
      ).weekday]++;
    }

    return SpendingRhythm(
      byWeekday: <WeekdaySpend>[
        for (
          var weekday = DateTime.monday;
          weekday <= DateTime.sunday;
          weekday++
        )
          WeekdaySpend(
            weekday: weekday,
            totalMinor: totals[weekday],
            days: daysPerWeekday[weekday],
          ),
      ],
      totalMinor: total,
      activeDays: active.length,
      recordedDays: recordedDays,
    );
  }

  /// Where [range] is heading, or null when the period is not running (C5, C11).
  ///
  /// The rate comes from the complete months *before* the one in progress, whose
  /// spend is already inside the figure: mixing a part-month into the average
  /// would make the rate chase the calendar rather than the user. The window is
  /// clipped to the ledger's own life, so a three-week-old install cannot be
  /// dragged toward zero by months the app did not exist for.
  PeriodProjection? projectionFor(StatsRange range, {int months = 6}) {
    if (!range.contains(now)) {
      return null;
    }
    final today = DateTime(now.year, now.month, now.day);
    final elapsedDays = today.difference(range.from).inDays + 1;
    final daysRemaining = range.days - elapsedDays;

    // Rules still to post before the period ends. Today counts, because a rule
    // due today has not posted yet; one that already has is in the ledger, and so
    // already part of the spend to date.
    var committed = 0;
    var ruleCount = 0;
    for (final rule in recurringRules) {
      if (!rule.isExpense) {
        continue;
      }
      final due = rule.nextDueOn;
      if (due.isBefore(today) || !due.isBefore(range.to)) {
        continue;
      }
      committed += rule.amountMinor;
      ruleCount++;
    }

    final currentMonth = DateTime(now.year, now.month);
    var windowStart = DateTime(now.year, now.month - months);
    final first = firstRecordedDay;
    if (first != null && first.isAfter(windowStart)) {
      windowStart = first;
    }
    final windowDays = windowStart.isBefore(currentMonth)
        ? currentMonth.difference(windowStart).inDays
        : 0;

    // Daily spend read from the rows, so this method needs no opinion about how
    // the monthly aggregates key their maps.
    final byDay = <DateTime, int>{};
    for (final txn in transactions) {
      if (!txn.isExpense) {
        continue;
      }
      final day = DateTime(txn.date.year, txn.date.month, txn.date.day);
      if (day.isBefore(windowStart) || !day.isBefore(currentMonth)) {
        continue;
      }
      byDay.update(
        day,
        (value) => value + txn.amountMinor,
        ifAbsent: () => txn.amountMinor,
      );
    }

    final dailyTotals = byDay.values.toList(growable: false);
    final activeDayMedian = dailyTotals.isEmpty ? 0 : medianOf(dailyTotals);
    final monthsOfHistory = <int>{
      for (final day in byDay.keys) day.year * 12 + day.month,
    }.length;

    // The expected day is the median day, discounted by how often days actually
    // carry an entry: a median over calendar days collapses to zero for anyone
    // who does not record every single day (C11), and a mean is dragged by one
    // annual bill.
    final dailyRate = windowDays == 0
        ? 0
        : (activeDayMedian * byDay.length) ~/ windowDays;

    return PeriodProjection(
      range: range,
      spentMinor: compositionFor(range).expenseMinor,
      committedMinor: committed,
      dailyRateMinor: dailyRate,
      activeDayMedianMinor: activeDayMedian,
      daysRemaining: daysRemaining < 0 ? 0 : daysRemaining,
      monthsOfHistory: monthsOfHistory,
      recordedDays: byDay.length,
      ruleCount: ruleCount,
    );
  }

  /// The total of the monthly spending limits that apply to [range], scaled by
  /// the whole months it covers.
  ///
  /// Zero for a week, which contains no whole month: a daily allowance invented
  /// from a monthly limit stretched over seven days is a figure nobody agreed to,
  /// and the same rule already governs the budget bars.
  int budgetLimitIn(StatsRange range) {
    final scale = range.period.monthsCovered;
    if (scale == 0) {
      return 0;
    }
    var total = 0;
    for (final category in categories) {
      if (category.isSpending && category.budgetMinor > 0) {
        total += category.budgetMinor * scale;
      }
    }
    return total;
  }

  /// Each limited category read at the pace [range] has actually been spent,
  /// worst first.
  ///
  /// Empty for a period that is over or has only just begun: there is no pace to
  /// read, and "heading for" about a finished period is a statement about the
  /// past dressed up as a warning (C4, C6).
  List<BudgetPace> budgetPaceIn(StatsRange range) {
    if (!range.contains(now)) {
      return const <BudgetPace>[];
    }
    final today = DateTime(now.year, now.month, now.day);
    final daysRemaining =
        range.days - (today.difference(range.from).inDays + 1);
    if (daysRemaining <= 0) {
      return const <BudgetPace>[];
    }
    final elapsed = range.elapsedFraction(now);
    if (elapsed <= 0 || elapsed >= 1) {
      return const <BudgetPace>[];
    }

    final paces = budgetStatusesIn(range)
        .where((status) => status.hasLimit)
        .map(
          (status) => BudgetPace(
            category: status.category,
            spentMinor: status.spentMinor,
            limitMinor: status.budgetMinor,
            elapsedFraction: elapsed,
            daysRemaining: daysRemaining,
          ),
        )
        .toList();
    paces.sort((a, b) {
      if (a.isProjectedOver != b.isProjectedOver) {
        return a.isProjectedOver ? -1 : 1;
      }
      final byOvershoot = b.overshootMinor.compareTo(a.overshootMinor);
      // Ties broken by name so the order is deterministic rather than whatever
      // order the budget card happened to build.
      return byOvershoot != 0 ? byOvershoot : a.category.compareTo(b.category);
    });
    return paces;
  }

  /// Month-end balances across every account, oldest first.
  ///
  /// Reconstructed by replaying each account's opening balance and every recorded
  /// movement, so an earlier month end is available and not only today's. A
  /// balance is a *stock*: the point for the month in progress is today's
  /// balance rather than a fraction of one, because C6's rule about part-periods
  /// is about flows.
  ///
  /// `transfer` legs are skipped, exactly as the account query skips them: an
  /// always-positive amount with a transfer direction carries no sign to add
  /// (C2), so including them would mean inventing a direction. Investments are
  /// counted at cost, what was paid for them (C3).
  List<NetWorthPoint> netWorthSeries(StatsRange range) {
    final today = DateTime(now.year, now.month, now.day);
    final movements =
        transactions
            .where((txn) => txn.direction != TxDirection.transfer)
            .toList(growable: false)
          ..sort((a, b) => a.date.compareTo(b.date));

    NetWorthPoint at(DateTime month, DateTime cutoff) {
      var liquid = 0;
      var card = 0;
      var invested = 0;
      for (final account in accounts) {
        var balance = account.openingBalanceMinor;
        for (final txn in movements) {
          if (txn.accountId != account.id || txn.date.isAfter(cutoff)) {
            continue;
          }
          balance += txn.direction == TxDirection.income
              ? txn.amountMinor
              : -txn.amountMinor;
        }
        if (account.isCreditCard) {
          card += balance;
        } else {
          liquid += balance;
        }
      }
      for (final txn in movements) {
        if (txn.isInvestment && !txn.date.isAfter(cutoff)) {
          invested += txn.amountMinor;
        }
      }
      return NetWorthPoint(
        month: month,
        liquidMinor: liquid,
        cardMinor: card,
        investedMinor: invested,
      );
    }

    final lastMonth = range.contains(now)
        ? DateTime(now.year, now.month)
        : DateTime(range.to.year, range.to.month - 1);
    final points = <NetWorthPoint>[];
    var month = DateTime(range.from.year, range.from.month);
    // Months before the first recorded entry are not history: they would draw the
    // account's opening balance as a line the user never had (C7).
    final first = firstRecordedDay;
    if (first != null && first.isAfter(month)) {
      month = DateTime(first.year, first.month);
    }
    while (!month.isAfter(lastMonth)) {
      final monthEnd = DateTime(month.year, month.month + 1);
      // The last day of the month, except for the month in progress, where it is
      // today: a balance that has not happened yet is not a balance.
      final cutoff = monthEnd.isAfter(today)
          ? today
          : monthEnd.subtract(const Duration(days: 1));
      points.add(at(month, cutoff));
      month = monthEnd;
    }
    return points;
  }

  /// Today's net worth at cost.
  ///
  /// Derived from [netWorthSeries] rather than summed again, so the line and any
  /// headline read off it cannot disagree.
  NetWorthPoint get currentNetWorth =>
      netWorthSeries(StatsRange.containing(StatsPeriod.month, now)).last;
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
