import 'package:flutter/foundation.dart';

import 'models.dart';
import 'monthly_extremes.dart';
import 'payee_totals.dart';
import 'period_comparison.dart';
import 'stats_period.dart';

/// A year described in a handful of statements rather than a table.
///
/// Almost entirely presentation over figures the earlier tiers already compute —
/// which is why it belongs at the end of the plan. What it deliberately does not
/// do is invent a figure to fill a slot: every optional field is null when the
/// year has nothing to say about it, and the screen reads null as "nothing here"
/// rather than drawing a zero. A review that said "biggest month: ₹0" would be
/// describing the absence of data as a fact about the user's year.
@immutable
class YearInReview {
  const YearInReview({
    required this.year,
    required this.range,
    required this.isComplete,
    required this.totals,
    required this.entries,
    required this.monthsRecorded,
    required this.biggestMonth,
    required this.topCategory,
    required this.largestPayee,
    required this.frequentPayee,
    required this.monthsInsideLimits,
    required this.monthsComparedToLimits,
    required this.committedMonthlyMinor,
    required this.change,
  });

  /// The calendar year these figures cover.
  final int year;

  /// The year's bounds, for the drill-downs and the composition card.
  final StatsRange range;

  /// False for the year still in progress, so the screen can say "so far" rather
  /// than implying the year is over.
  final bool isComplete;

  /// Income, spend and investing for the whole year.
  final PeriodTotals totals;

  /// How many live entries the year holds.
  final int entries;

  /// Months of the year with anything recorded in them.
  ///
  /// A count of *recording* months, matching [monthlyExtremes]: a month the app
  /// did not exist for is not part of the year the user had.
  final int monthsRecorded;

  /// The year's heaviest spending month, or null when nothing was spent.
  final MonthPeak? biggestMonth;

  /// The category most money went to, or null when nothing was spent.
  final CategorySpend? topCategory;

  /// The payee paid the most, or null when nothing was paid.
  final PayeeTotal? largestPayee;

  /// The payee paid the most *often*, which is a different answer to a different
  /// question, and usually a different row.
  final PayeeTotal? frequentPayee;

  /// Months whose categories with limits all stayed inside them.
  final int monthsInsideLimits;

  /// Months compared against limits at all: the months that had spend *and* at
  /// least one limit set. Zero means the year has no limits to report against,
  /// and the screen says so rather than claiming twelve clean months.
  ///
  /// Measured against today's limits, because the app does not keep a budget
  /// history — a limit edited last week is applied to January here, and the
  /// screen states that limitation rather than hiding it (C4).
  final int monthsComparedToLimits;

  /// What the standing rules cost a month *now*.
  ///
  /// A figure about today carried into a review of last year, and labelled as
  /// such on the screen: repeating rules are a current commitment, not something
  /// the year recorded.
  final int committedMonthlyMinor;

  /// The year against the one before it, or null when the ledger does not hold a
  /// full year of history before this one (C7).
  final PeriodComparison? change;

  /// True when the year holds no entries at all.
  bool get isEmpty => entries == 0;

  /// True when there are limits set and at least one month was compared against
  /// them, which is what makes a streak a meaningful thing to report.
  bool get hasLimitRecord => monthsComparedToLimits > 0;

  /// Every month compared stayed inside its limits.
  bool get stayedInsideEveryMonth =>
      hasLimitRecord && monthsInsideLimits == monthsComparedToLimits;
}
