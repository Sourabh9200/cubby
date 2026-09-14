import 'package:flutter/foundation.dart';

import 'models.dart';

/// A live rule read as a subscription: what it costs, and what that is in a year.
///
/// The annual figure is the point. "₹499 a month" is a decision nobody makes;
/// "₹5,988 a year" is one they do, which is why the doc calls annualising the
/// thing that makes anyone act.
///
/// A rule is still only a habit: a monthly reimbursement from an employer is also
/// a rule, so this is a list of what repeats, not proof of what is subscribed
/// (C14). Income rules are deliberately not here — this is a list of what it
/// costs.
@immutable
class Subscription {
  const Subscription({
    required this.ruleId,
    required this.category,
    required this.payee,
    required this.amountMinor,
    required this.direction,
    required this.nextDueOn,
  });

  final String ruleId;
  final String category;

  /// The payee the rule posts under, `''` for a rule made without one.
  final String payee;

  final int amountMinor;
  final TxDirection direction;
  final DateTime nextDueOn;

  /// How many times the rule posts in a year.
  ///
  /// Monthly is the only cadence the app has, and this constant is the single
  /// place that assumption lives — adding a cadence means changing this and the
  /// occurrence arithmetic, not hunting for a `* 12`.
  static const int periodsPerYear = 12;

  /// What this rule costs over a year.
  int get annualMinor => amountMinor * periodsPerYear;

  bool get isExpense => direction == TxDirection.expense;

  /// True for a contribution, which is money put away rather than spent (C1).
  bool get isInvestment => direction == TxDirection.investment;
}
