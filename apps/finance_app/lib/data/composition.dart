import 'package:flutter/foundation.dart';

import 'models.dart';

/// One period's income, split into what was spent, what was invested, and what
/// was left.
///
/// Three slices plus a remainder rather than two figures, because the whole
/// point of this view is the *allocation*: "where did the year go?" is answered
/// by how income was divided, not by how much of it there was. Folding expense
/// and investment into one "money out" figure is the error C1 exists to prevent
/// — it understates the savings rate by exactly the amount invested — and
/// showing only spent-versus-received leaves the money that went nowhere at all
/// invisible.
///
/// Extends [PeriodTotals] rather than restating the three figures, so the
/// savings rate and the change in cash stay one implementation.
@immutable
class CompositionTotals extends PeriodTotals {
  const CompositionTotals({
    required super.expenseMinor,
    required super.incomeMinor,
    super.investmentMinor,
  });

  /// The composition of [totals], for callers that already have the three
  /// figures.
  factory CompositionTotals.from(PeriodTotals totals) => CompositionTotals(
    expenseMinor: totals.expenseMinor,
    incomeMinor: totals.incomeMinor,
    investmentMinor: totals.investmentMinor,
  );

  /// Income neither consumed nor invested: the change in cash across the
  /// period.
  ///
  /// Negative when the period spent and invested more than it earned. That is a
  /// real state — a month carried by savings — so it is reported as it is
  /// rather than floored at zero, which would hide the month it happened.
  int get unallocatedMinor => cashLeftMinor;

  /// Everything that left the account, consumed or invested.
  ///
  /// A cash-out figure, never a substitute for [expenseMinor] in anything that
  /// means "spending" (C1).
  int get outflowMinor => expenseMinor + investmentMinor;

  /// True when the period recorded nothing at all.
  bool get isEmpty =>
      incomeMinor == 0 && expenseMinor == 0 && investmentMinor == 0;

  /// True when spending and investing together exceeded what came in.
  bool get isOverdrawn => unallocatedMinor < 0;

  /// [partMinor] as a percentage of income, or null when no income was
  /// recorded.
  ///
  /// Null rather than zero: a share of nothing is undefined, and "0%" beside a
  /// period with no income reads as *you spent none of it*, which is the
  /// opposite of what happened.
  double? shareOfIncome(int partMinor) =>
      incomeMinor == 0 ? null : partMinor / incomeMinor * 100;
}

/// One month's composition, for the columns that show allocation over time.
@immutable
class CompositionPoint {
  const CompositionPoint({
    required this.month,
    required this.totals,
    required this.isPartial,
  });

  /// The month, at its first instant.
  final DateTime month;

  final CompositionTotals totals;

  /// True for the month in progress.
  ///
  /// Its column has to be marked rather than drawn like a whole one, or a
  /// half-finished month reads as a collapse in saving that never happened
  /// (C6).
  final bool isPartial;
}
