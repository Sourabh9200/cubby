import 'package:flutter/foundation.dart';

/// The length of time a screen is showing.
///
/// Every period is a whole number of calendar units rather than a number of
/// days, so "this quarter" means July to September and not "the last 91 days".
/// A rolling window would be defensible for a chart and wrong for a ledger: two
/// entries on either side of a boundary would move between periods as the days
/// passed, and a total that changes without a new entry is a total nobody trusts.
enum StatsPeriod {
  week,
  month,
  quarter,
  year;

  /// How many months this period covers, for scaling a monthly budget.
  ///
  /// Zero for a week, which contains no whole month. That zero is what stops the
  /// overview from drawing a weekly bar against a monthly limit: scaling 31 days
  /// down to 7 is arithmetic that looks precise and is simply wrong, and a
  /// budget bar that is wrong is worse than no bar.
  int get monthsCovered => switch (this) {
    StatsPeriod.week => 0,
    StatsPeriod.month => 1,
    StatsPeriod.quarter => 3,
    StatsPeriod.year => 12,
  };
}

/// A half-open date range, `[from, to)`, plus the period it represents.
///
/// Half-open because every date comparison in this app already is: `occurred_on
/// >= from AND occurred_on < to` is what the aggregation queries use, and a range
/// whose end was inclusive would double-count an entry dated the last day.
@immutable
class StatsRange {
  const StatsRange({
    required this.period,
    required this.from,
    required this.to,
  });

  final StatsPeriod period;

  /// Inclusive, at local midnight.
  final DateTime from;

  /// Exclusive, at local midnight.
  final DateTime to;

  /// The period of [period] that contains [day].
  static StatsRange containing(StatsPeriod period, DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    switch (period) {
      case StatsPeriod.week:
        // Monday, because that is the first day of a week in India and the app
        // is INR-only. `weekday` is 1 for Monday, so this never shifts a Monday.
        final start = date.subtract(Duration(days: date.weekday - 1));
        return StatsRange(
          period: period,
          from: start,
          to: DateTime(start.year, start.month, start.day + 7),
        );
      case StatsPeriod.month:
        return StatsRange(
          period: period,
          from: DateTime(date.year, date.month),
          to: DateTime(date.year, date.month + 1),
        );
      case StatsPeriod.quarter:
        final firstMonth = ((date.month - 1) ~/ 3) * 3 + 1;
        return StatsRange(
          period: period,
          from: DateTime(date.year, firstMonth),
          to: DateTime(date.year, firstMonth + 3),
        );
      case StatsPeriod.year:
        return StatsRange(
          period: period,
          from: DateTime(date.year),
          to: DateTime(date.year + 1),
        );
    }
  }

  /// The same period [count] periods earlier or later.
  ///
  /// Stepping in whole periods rather than in days is what keeps a week starting
  /// on a Monday and a quarter starting in April whatever the current day is.
  StatsRange step(int count) {
    switch (period) {
      case StatsPeriod.week:
        final start = DateTime(from.year, from.month, from.day + 7 * count);
        return StatsRange(
          period: period,
          from: start,
          to: DateTime(start.year, start.month, start.day + 7),
        );
      case StatsPeriod.month:
        return StatsRange(
          period: period,
          from: DateTime(from.year, from.month + count),
          to: DateTime(from.year, from.month + count + 1),
        );
      case StatsPeriod.quarter:
        return StatsRange(
          period: period,
          from: DateTime(from.year, from.month + 3 * count),
          to: DateTime(from.year, from.month + 3 * count + 3),
        );
      case StatsPeriod.year:
        return StatsRange(
          period: period,
          from: DateTime(from.year + count),
          to: DateTime(from.year + count + 1),
        );
    }
  }

  /// True when [date] falls inside the range. [to] is excluded.
  bool contains(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(from) && day.isBefore(to);
  }

  /// How many days the range spans.
  int get days => to.difference(from).inDays;

  /// How much of the range has happened by [now], as a fraction from 0 to 1.
  ///
  /// Used to compare a period that is still running against a whole one. A
  /// quarter compared against a completed quarter would read as a saving every
  /// time until its last day.
  double elapsedFraction(DateTime now) {
    if (!contains(now)) {
      return now.isBefore(from) ? 0 : 1;
    }
    final through =
        DateTime(now.year, now.month, now.day).difference(from).inDays + 1;
    return (through / days).clamp(0, 1);
  }

  /// True when both ranges cover exactly the same dates.
  bool sameDatesAs(StatsRange other) => from == other.from && to == other.to;

  @override
  bool operator ==(Object other) =>
      other is StatsRange &&
      other.period == period &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(period, from, to);

  @override
  String toString() => '${period.name}[$from, $to)';
}
