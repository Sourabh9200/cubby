import 'package:flutter/foundation.dart';

/// One category's limit, read at the pace the period has actually been spent.
///
/// This is the difference between "you have ₹3,000 left" and "you are heading for
/// ₹18,000 against ₹15,000, while there is still time to do something about it".
/// It is only meaningful while the period is running, so a closed period
/// produces none.
@immutable
class BudgetPace {
  const BudgetPace({
    required this.category,
    required this.spentMinor,
    required this.limitMinor,
    required this.elapsedFraction,
    required this.daysRemaining,
  });

  final String category;
  final int spentMinor;
  final int limitMinor;

  /// How much of the period has happened, 0 to 1.
  final double elapsedFraction;

  final int daysRemaining;

  /// True when the period is part-way through, which is the only time "heading
  /// for" says anything. On the first day there is no pace yet.
  bool get canProject => elapsedFraction > 0 && elapsedFraction < 1;

  /// Where this category lands if the rest of the period behaves like the part
  /// already spent. The spend to date when there is no pace to read.
  int get projectedMinor =>
      !canProject ? spentMinor : (spentMinor / elapsedFraction).round();

  /// True when the pace takes it past its limit, which is the thing worth
  /// interrupting the user for.
  bool get isProjectedOver =>
      canProject && limitMinor > 0 && projectedMinor > limitMinor;

  /// How far past the limit it is heading, zero when it is not.
  int get overshootMinor => !isProjectedOver ? 0 : projectedMinor - limitMinor;

  /// What is left to spend in this category, at the pace already set.
  int get remainingMinor => limitMinor - spentMinor;

  /// What each remaining day may spend and still finish inside the limit.
  ///
  /// Floored at zero: on a pace that has already spent the limit there is no
  /// daily allowance left, and saying "minus ₹200 a day" would be a number
  /// nobody can act on.
  int get safePerDayMinor {
    if (daysRemaining <= 0) {
      return 0;
    }
    final left = limitMinor - spentMinor;
    return left <= 0 ? 0 : left ~/ daysRemaining;
  }
}
