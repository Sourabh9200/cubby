import 'category_movement.dart';
import 'finance_snapshot.dart';
import 'models.dart';
import 'monthly_extremes.dart';
import 'period_views.dart';
import 'recurring_candidate.dart';
import 'scheduled_views.dart';
import 'snapshot_views.dart';
import 'statistics.dart';
import 'stats_period.dart';
import 'suggested_limit.dart';
import 'year_in_review.dart';

/// Comparisons against history.
///
/// Kept separate from [SnapshotViews] because these are the computations that
/// belong in a pure, well-tested analytics layer: they take numbers in and
/// return numbers out, with no widget or database dependency.
extension SnapshotAnalytics on FinanceSnapshot {
  /// Month-over-month change in total spend, as a percentage.
  ///
  /// The current month is partial, so the previous month is scaled to the same
  /// day-of-month before comparing. Comparing a part-month against a whole one
  /// would read as a large saving every single time, which is worse than
  /// showing nothing.
  double? get expenseChangePercent => expenseChangeFor(currentMonth.month);

  /// Month-over-month change in total spend for [month].
  ///
  /// An adapter onto [PeriodViews.expenseChangeForRange], so a weekly comparison
  /// and a monthly one are the same arithmetic. A month that is over is compared
  /// whole against the month before it — scaling there would invent a figure that
  /// never happened. Only the month in progress is scaled, because only it is
  /// incomplete.
  double? expenseChangeFor(DateTime month) =>
      expenseChangeForRange(StatsRange.containing(StatsPeriod.month, month));

  /// Mean monthly spend per category across every month present.
  ///
  /// Comparing a month against the user's *own* history is what makes the
  /// figure meaningful. A fixed threshold would be arbitrary, and a peer
  /// comparison is neither available nor appropriate for private data.
  Map<String, double> get categoryMonthlyAverages {
    final totals = <String, int>{};
    for (final byCategory in categorySpendByMonth.values) {
      byCategory.forEach((category, amount) {
        totals.update(
          category,
          (value) => value + amount,
          ifAbsent: () => amount,
        );
      });
    }
    final months = categorySpendByMonth.isEmpty
        ? 1
        : categorySpendByMonth.length;
    return <String, double>{
      for (final entry in totals.entries) entry.key: entry.value / months,
    };
  }

  /// Movement of each category in [month] relative to its own average,
  /// largest increase first.
  ///
  /// Sorted by increase because the user's question is always "what got
  /// expensive", never "what got cheap".
  List<CategoryMovement> categoryMovement(DateTime month) {
    final averages = categoryMonthlyAverages;
    final movements = spendByCategory(month)
        .map(
          (spend) => CategoryMovement(
            category: spend.category,
            currentMinor: spend.totalMinor,
            averageMinor: (averages[spend.category] ?? 0).round(),
          ),
        )
        .toList();
    movements.sort(
      (a, b) => (b.deltaPercent ?? 0).compareTo(a.deltaPercent ?? 0),
    );
    return movements;
  }

  /// Savings rate as a percentage of income for the current month, or null when
  /// there was no income to save from.
  double? get currentSavingsRate => currentMonth.savingsRate;

  /// Highest and lowest month on record for each of the three measures, plus
  /// the average over the months that recorded each one.
  ///
  /// Months with nothing recorded for a measure are skipped rather than counted
  /// as zero. A month in which nothing was invested is not "the month you
  /// invested least" — it is a month with no investing in it at all — and
  /// counting it would report every user's worst investing month as whichever
  /// month they happened to skip a contribution. The same reasoning makes the
  /// average a mean over recording months.
  List<MetricExtremes> get monthlyExtremes => <MetricExtremes>[
    _extremesFor(MetricMeasure.expense, (summary) => summary.expenseMinor),
    _extremesFor(MetricMeasure.income, (summary) => summary.incomeMinor),
    _extremesFor(
      MetricMeasure.investment,
      (summary) => summary.investmentMinor,
    ),
  ];

  MetricExtremes _extremesFor(
    MetricMeasure measure,
    int Function(MonthlySummary) read,
  ) {
    MonthPeak? highest;
    MonthPeak? lowest;
    var total = 0;
    var months = 0;
    for (final summary in monthlySummaries) {
      final value = read(summary);
      if (value <= 0) {
        continue;
      }
      total += value;
      months++;
      if (highest == null || value > highest.totalMinor) {
        highest = MonthPeak(month: summary.month, totalMinor: value);
      }
      if (lowest == null || value < lowest.totalMinor) {
        lowest = MonthPeak(month: summary.month, totalMinor: value);
      }
    }
    return MetricExtremes(
      measure: measure,
      highest: highest,
      lowest: lowest,
      // Integer division, because money in this app never becomes a double.
      averageMinor: months == 0 ? 0 : total ~/ months,
    );
  }

  /// Savings rates for every month on record, oldest first.
  List<double> get savingsRateHistory => monthlySummaries
      .map((summary) => summary.savingsRate)
      .whereType<double>()
      .toList(growable: false);

  /// A limit to propose for each category, from the median and p90 of the last
  /// [months] complete months.
  ///
  /// A suggestion, never a decision: a figure read off someone's own spending is
  /// not a budget they agreed to (C4). Empty when the window is not wholly inside
  /// the ledger's life, because "your average month" computed over months the app
  /// did not exist for is a smaller number than the truth (C7).
  ///
  /// A category whose own median is zero is skipped rather than offered a limit
  /// of nothing, and one used in fewer than two months of the window is skipped
  /// too: six zeros and one expensive month is a one-off, not a monthly habit.
  List<SuggestedLimit> suggestedLimits({
    int months = 6,
    int minimumMonths = 6,
  }) {
    final first = firstRecordedDay;
    if (first == null || months < minimumMonths || months <= 0) {
      return const <SuggestedLimit>[];
    }
    final windowStart = DateTime(now.year, now.month - months);
    if (first.isAfter(windowStart)) {
      return const <SuggestedLimit>[];
    }

    final keys = <String>[
      for (var back = months; back >= 1; back--)
        SnapshotViews.monthKeyOf(DateTime(now.year, now.month - back)),
    ];

    final suggestions = <SuggestedLimit>[];
    for (final category in categories) {
      if (!category.isSpending) {
        continue;
      }
      final perMonth = <int>[];
      var monthsRecorded = 0;
      for (final key in keys) {
        final spend = categorySpendByMonth[key]?[category.name] ?? 0;
        perMonth.add(spend);
        if (spend > 0) {
          monthsRecorded++;
        }
      }
      if (monthsRecorded < 2) {
        continue;
      }
      final median = medianOf(perMonth);
      if (median == 0) {
        continue;
      }
      suggestions.add(
        SuggestedLimit(
          category: category.name,
          medianMinor: median,
          p90Minor: percentileOf(perMonth, 0.9),
          monthsRecorded: monthsRecorded,
        ),
      );
    }
    suggestions.sort((a, b) => b.medianMinor.compareTo(a.medianMinor));
    return suggestions;
  }

  /// Payees that look like they repeat monthly, as proposals for a rule.
  ///
  /// Same payee, similar amount, roughly monthly spacing, at least
  /// [RecurringCandidate.minimumOccurrences] times, and seen recently enough to
  /// still be a habit. Every payee is matched exactly as recorded (C8), a payee
  /// that already has a live rule is skipped (the proposal would be a duplicate),
  /// and the tolerances are carried on the model so the UI can state them rather
  /// than hide them.
  ///
  /// A proposal, never a write: nothing here creates a rule.
  List<RecurringCandidate> recurringCandidates({
    int minimumOccurrences = RecurringCandidate.minimumOccurrences,
  }) {
    final byPayee = <String, List<Transaction>>{};
    for (final txn in transactions) {
      if (!txn.isExpense) {
        continue;
      }
      final payee = txn.payee.trim();
      if (payee.isEmpty) {
        continue;
      }
      byPayee.putIfAbsent(payee, () => <Transaction>[]).add(txn);
    }

    final alreadyRepeating = <String>{
      for (final rule in recurringRules)
        if (rule.payee.trim().isNotEmpty) rule.payee.trim().toLowerCase(),
    };

    final candidates = <RecurringCandidate>[];
    for (final entry in byPayee.entries) {
      if (alreadyRepeating.contains(entry.key.toLowerCase())) {
        continue;
      }
      final occurrences = List<Transaction>.of(entry.value)
        ..sort((a, b) => a.date.compareTo(b.date));
      if (occurrences.length < minimumOccurrences) {
        continue;
      }

      var spaced = true;
      for (var index = 1; index < occurrences.length; index++) {
        final gap = occurrences[index].date
            .difference(occurrences[index - 1].date)
            .inDays;
        if ((gap - RecurringCandidate.cadenceDays).abs() >
            RecurringCandidate.toleranceDays) {
          spaced = false;
          break;
        }
      }
      if (!spaced) {
        continue;
      }

      // The median amount, so one odd month cannot disqualify a real
      // subscription and one large month cannot invent one.
      final typical = medianOf(<int>[
        for (final txn in occurrences) txn.amountMinor,
      ]);
      if (typical == 0) {
        continue;
      }
      final tolerance = (typical * 0.1).round();
      final similar = occurrences.every(
        (txn) => (txn.amountMinor - typical).abs() <= tolerance,
      );
      if (!similar) {
        continue;
      }

      final last = occurrences.last;
      // A payee last seen two cycles ago is a cancelled subscription, and
      // proposing it would be proposing history.
      if (DateTime(now.year, now.month, now.day)
              .difference(
                DateTime(last.date.year, last.date.month, last.date.day),
              )
              .inDays >
          RecurringCandidate.staleAfterDays) {
        continue;
      }

      candidates.add(
        RecurringCandidate(
          payee: entry.key,
          category: last.category,
          categoryId: last.categoryId,
          accountId: last.accountId,
          direction: last.direction,
          typicalAmountMinor: typical,
          occurrences: occurrences.length,
          lastDate: last.date,
        ),
      );
    }

    candidates.sort((a, b) {
      final byTotal = (b.typicalAmountMinor * b.occurrences).compareTo(
        a.typicalAmountMinor * a.occurrences,
      );
      return byTotal != 0 ? byTotal : a.payee.compareTo(b.payee);
    });
    return candidates;
  }

  /// One year told as a handful of statements: the review screen's whole input.
  ///
  /// Every figure is drawn from a method the other tiers already have —
  /// [PeriodViews.totalsFor], [PeriodViews.spendIn], [PeriodViews.payeeTotalsIn],
  /// [SnapshotViews.monthlySummaries], [PeriodViews.budgetStatusesIn],
  /// [ScheduledViews.committedMonthlyMinor] — so the review cannot disagree with
  /// the screens it is summarising. Nothing here is a new sum.
  ///
  /// The year is *complete* or in progress, and the difference matters in exactly
  /// two places: the screen's wording, and the year-over-year scaling, which
  /// [PeriodViews.yearOverYearFor] already handles.
  YearInReview yearInReview(int year) {
    final range = StatsRange.containing(StatsPeriod.year, DateTime(year));
    final totals = totalsFor(range);
    final entries = transactionsIn(range);

    var monthsRecorded = 0;
    MonthPeak? biggestMonth;
    for (final summary in monthlySummaries) {
      if (!range.contains(summary.month)) {
        continue;
      }
      if (summary.expenseMinor > 0) {
        monthsRecorded++;
        if (biggestMonth == null ||
            summary.expenseMinor > biggestMonth.totalMinor) {
          biggestMonth = MonthPeak(
            month: summary.month,
            totalMinor: summary.expenseMinor,
          );
        }
      } else if (summary.incomeMinor > 0 || summary.investmentMinor > 0) {
        // A month that only received or only invested still happened, so it
        // counts as recorded — but it is not a candidate for biggest month,
        // which is a question about spending.
        monthsRecorded++;
      }
    }

    // Limits are monthly, so each month is judged on its own — and only months
    // that have already happened: a month that has not started has no spend, and
    // counting it as "inside the limit" would hand the year a streak it did not
    // earn.
    var monthsComparedToLimits = 0;
    var monthsInsideLimits = 0;
    final currentMonth = DateTime(now.year, now.month);
    var month = DateTime(year);
    while (range.contains(month) && !month.isAfter(currentMonth)) {
      // Only categories that both have a limit and were actually spent from. A
      // fresh install ships categories with limits already set, so counting an
      // empty month as "inside the limit" would report a streak of months that
      // never happened.
      final withLimit =
          budgetStatusesIn(StatsRange.containing(StatsPeriod.month, month))
              .where((status) => status.hasLimit && status.spentMinor > 0)
              .toList(growable: false);
      if (withLimit.isNotEmpty) {
        monthsComparedToLimits++;
        if (withLimit.every((status) => !status.isOver)) {
          monthsInsideLimits++;
        }
      }
      month = DateTime(month.year, month.month + 1);
    }

    final spends = spendIn(range);
    final payees = payeeTotalsIn(range);
    return YearInReview(
      year: year,
      range: range,
      isComplete: !range.contains(now),
      totals: totals,
      entries: entries.length,
      monthsRecorded: monthsRecorded,
      biggestMonth: biggestMonth,
      topCategory: spends.isEmpty ? null : spends.first,
      largestPayee: payees.isEmpty ? null : payees.first,
      frequentPayee: mostFrequentPayeeIn(range),
      monthsInsideLimits: monthsInsideLimits,
      monthsComparedToLimits: monthsComparedToLimits,
      committedMonthlyMinor: committedMonthlyMinor,
      change: yearOverYearFor(range),
    );
  }
}
