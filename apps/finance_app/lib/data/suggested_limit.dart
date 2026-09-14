import 'package:flutter/foundation.dart';

/// A limit derived from what the user has actually spent, offered as a proposal.
///
/// A suggestion, never a decision: a figure read off someone's own spending is
/// not a budget they agreed to (C4). Nothing in the app writes it without the
/// user confirming it, and below [minimumMonths] of history the honest output is
/// nothing at all rather than a limit invented from two months (C7).
@immutable
class SuggestedLimit {
  const SuggestedLimit({
    required this.category,
    required this.medianMinor,
    required this.p90Minor,
    required this.monthsRecorded,
  });

  final String category;

  /// The middle month of the window: what a normal month costs.
  final int medianMinor;

  /// The month at the 90th percentile: what the expensive ones cost, for a user
  /// who would rather not be caught out.
  final int p90Minor;

  /// Recording months the figures rest on, shown as the basis.
  final int monthsRecorded;

  /// The proposal itself: the median, because a limit set at the p90 would
  /// leave the user "within budget" while consistently overspending.
  int get suggestedMinor => medianMinor;

  /// True when even the expensive end of the window fits the median, so offering
  /// two figures would be offering the same figure twice.
  bool get hasSpread => p90Minor > medianMinor;
}
