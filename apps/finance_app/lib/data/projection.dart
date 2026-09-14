import 'package:flutter/foundation.dart';

import 'stats_period.dart';

/// Where a period that is still running is heading.
///
/// A projection of *recorded* data, never a promise (C5), so it carries its own
/// basis — how many months it looked at, how many days those months actually had
/// entries on, and how many rules are still to post — and every screen that shows
/// it is expected to show that basis beside it.
///
/// It exists only for a period that is in progress. A closed period needs no
/// projection, and one would be arithmetic dressed up as a fact.
@immutable
class PeriodProjection {
  const PeriodProjection({
    required this.range,
    required this.spentMinor,
    required this.committedMinor,
    required this.dailyRateMinor,
    required this.activeDayMedianMinor,
    required this.daysRemaining,
    required this.monthsOfHistory,
    required this.recordedDays,
    required this.ruleCount,
  });

  /// The period being projected, which always contains today.
  final StatsRange range;

  /// Spend recorded in the period so far.
  final int spentMinor;

  /// Spending rules that will still post before the period ends.
  ///
  /// Occurrences already posted are inside [spentMinor], so nothing is counted
  /// twice. Investing rules are not here: a contribution is not consumption
  /// (C1), and this is a figure about spending.
  final int committedMinor;

  /// Expected spend per remaining calendar day, from the trailing window.
  final int dailyRateMinor;

  /// Median spend on a day that carried an entry, for the basis line: the rate
  /// is this, discounted by how often the days actually have entries.
  final int activeDayMedianMinor;

  final int daysRemaining;

  /// Complete months the rate is built from, counting only those that recorded
  /// an expense. Reported as the basis, so it is never implied.
  final int monthsOfHistory;

  /// Days in the window that carried an entry — the other half of the basis.
  final int recordedDays;

  /// How many rules make up [committedMinor].
  final int ruleCount;

  /// Spend expected from here to the end of the period.
  int get projectedVariableMinor => dailyRateMinor * daysRemaining;

  /// Where the period lands if nothing changes.
  int get projectedTotalMinor =>
      spentMinor + committedMinor + projectedVariableMinor;

  /// True when the projection rests on something: a rate with a basis behind it,
  /// or at least one rule still to post.
  bool get hasBasis =>
      (monthsOfHistory > 0 && recordedDays > 0) || committedMinor > 0;

  /// True when the period is heading past [limitMinor], which for a limit of
  /// zero is never: no limit is not a limit of nothing.
  bool overshoots(int limitMinor) =>
      limitMinor > 0 && projectedTotalMinor > limitMinor;

  /// What the rest of the period allows per remaining day inside [limitMinor].
  ///
  /// Floored at zero, because "minus ₹400 a day" is not something anyone can act
  /// on — the overshoot is stated separately instead.
  int safePerDayMinor(int limitMinor) {
    if (daysRemaining <= 0) {
      return 0;
    }
    final left = limitMinor - projectedTotalMinor;
    return left <= 0 ? 0 : left ~/ daysRemaining;
  }
}
