import 'package:flutter/foundation.dart';

/// One weekday's slice of a range's spending.
@immutable
class WeekdaySpend {
  const WeekdaySpend({
    required this.weekday,
    required this.totalMinor,
    required this.days,
  });

  /// [DateTime.monday] (1) through [DateTime.sunday] (7).
  final int weekday;

  final int totalMinor;

  /// How many of this weekday the range actually covers.
  ///
  /// Carried so a partial first week cannot make a Monday look quiet: comparing
  /// totals would, comparing per-day averages does not.
  final int days;

  /// Mean spend for this weekday, rounded down to whole minor units. Zero when
  /// the range covers none of it.
  int get averageMinor => days == 0 ? 0 : totalMinor ~/ days;
}

/// How spending falls across the days of the week, over a range.
///
/// Every figure here describes the *ledger*, not behaviour (C11). A day with no
/// entry is a day nothing was recorded, which is not the same as a day nothing
/// was spent: cash does not pass through this app between deposits, and the
/// wording throughout says "recorded" for that reason.
@immutable
class SpendingRhythm {
  const SpendingRhythm({
    required this.byWeekday,
    required this.totalMinor,
    required this.activeDays,
    required this.recordedDays,
  });

  /// Always seven entries, Monday first, including weekdays the range covers
  /// no day of.
  final List<WeekdaySpend> byWeekday;

  final int totalMinor;

  /// Days in the range with at least one expense recorded.
  final int activeDays;

  /// Days of the range that have happened: all of them for a range that is
  /// over, up to and including today for the one in progress.
  final int recordedDays;

  /// Days with nothing recorded.
  ///
  /// Named for the ledger rather than for behaviour — the doc's "no-spend day"
  /// would claim something about the user's life that this data cannot support
  /// (C11).
  int get quietDays => (recordedDays - activeDays).clamp(0, recordedDays);

  /// Mean spend across the days something was recorded on.
  ///
  /// Over active days rather than over every day: a weekly average that
  /// included days the user simply did not open the app would fall every time
  /// they recorded less, which reads as good news and is not (C11).
  int get averagePerActiveDayMinor =>
      activeDays == 0 ? 0 : totalMinor ~/ activeDays;

  /// The weekday with the highest average, or null when nothing was recorded.
  ///
  /// Null when the range recorded nothing at all rather than "Monday, ₹0": a
  /// busiest day only means something if there was a day busier than the others.
  WeekdaySpend? get busiest {
    if (!hasData) {
      return null;
    }
    WeekdaySpend? best;
    for (final day in byWeekday) {
      if (day.days == 0) {
        continue;
      }
      if (best == null || day.averageMinor > best.averageMinor) {
        best = day;
      }
    }
    return best;
  }

  /// True when at least one expense was recorded in the range.
  bool get hasData => activeDays > 0;
}
