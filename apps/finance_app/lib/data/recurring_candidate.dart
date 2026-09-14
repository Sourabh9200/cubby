import 'package:flutter/foundation.dart';

import 'models.dart';

/// A payee that looks like it repeats, offered as a rule the user may accept.
///
/// A proposal and never a silent write: three similar payments to the same place
/// is evidence of a habit, not proof of one (C14), and the app has no business
/// creating a rule nobody asked for. The heuristic's tolerances are stated in the
/// UI rather than hidden, because the known false positive — two payments to the
/// same shop on the same day each month — is exactly what a user needs to be able
/// to judge for themselves (C8).
@immutable
class RecurringCandidate {
  const RecurringCandidate({
    required this.payee,
    required this.category,
    required this.categoryId,
    required this.accountId,
    required this.direction,
    required this.typicalAmountMinor,
    required this.occurrences,
    required this.lastDate,
  });

  /// The payee string exactly as the user recorded it — never a merged name.
  final String payee;

  final String category;
  final String categoryId;
  final String accountId;

  /// The direction of the entries, which is what the rule would post.
  final TxDirection direction;

  /// The median of the matching amounts: what a typical occurrence costs.
  final int typicalAmountMinor;

  final int occurrences;

  /// The most recent occurrence, which is what the rule would be anchored to.
  final DateTime lastDate;

  /// How many entries it takes before anything is suggested at all.
  static const int minimumOccurrences = 3;

  /// The spacing the heuristic looks for, and how far it will stretch.
  static const int cadenceDays = 30;
  static const int toleranceDays = 3;

  /// How long after the last occurrence a payee stops looking like a live habit.
  ///
  /// Two cycles plus the tolerance: something last seen three months ago is a
  /// subscription that was cancelled, and proposing it would be proposing
  /// history.
  static const int staleAfterDays = cadenceDays * 2 + toleranceDays;
}
