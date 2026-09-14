import 'package:flutter/foundation.dart';

import 'models.dart';

/// A recurring rule's next occurrence, ready for a due list.
///
/// Wording matters here: a rule describes what has happened before repeating,
/// so a due date is *scheduled*, never *owed* (C14).
@immutable
class UpcomingDue {
  const UpcomingDue({
    required this.ruleId,
    required this.payee,
    required this.category,
    required this.amountMinor,
    required this.dueOn,
    required this.direction,
  });

  final String ruleId;

  /// The payee the rule posts under, which is `''` for a rule made without one.
  final String payee;

  final String category;
  final int amountMinor;
  final DateTime dueOn;
  final TxDirection direction;

  /// True for a rule that posts spending.
  bool get isExpense => direction == TxDirection.expense;

  /// True for a rule that posts a contribution. Kept apart from spending
  /// because it is not consumption (C1).
  bool get isInvestment => direction == TxDirection.investment;

  /// True for a rule that posts income. Not a guarantee of anything: a salary
  /// rule is a habit, not a contract (C14).
  bool get isIncome => direction == TxDirection.income;
}
