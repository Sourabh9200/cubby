import 'package:flutter/foundation.dart';

/// What the user owns less what they owe, at one moment.
///
/// A *stock*, not a flow: a month in progress is not partial here the way a
/// spending total is, because a balance is a moment rather than a sum. C6's rule
/// about part-periods applies to flows, and applying it here would turn a correct
/// balance into a misleading fraction.
///
/// Investments are counted at **cost** — what was paid for them. This app has no
/// price feed by design, so a contribution's market value is not knowable
/// offline, and the figure says at cost rather than implying a valuation it
/// cannot support (C3).
@immutable
class NetWorthPoint {
  const NetWorthPoint({
    required this.month,
    required this.liquidMinor,
    required this.cardMinor,
    required this.investedMinor,
  });

  /// The month this point is the end of, at its first instant.
  final DateTime month;

  /// Bank, cash and wallet balances.
  final int liquidMinor;

  /// Credit-card balances, negative when money is owed.
  final int cardMinor;

  /// Contributions to date, at cost.
  final int investedMinor;

  /// Everything owned, less everything owed, with investments at cost.
  int get netWorthMinor => liquidMinor + cardMinor + investedMinor;

  /// The same figure without investments: money that could be spent this week.
  int get liquidNetWorthMinor => liquidMinor + cardMinor;

  /// True when there is nothing to show — no accounts, or nothing in them.
  bool get isEmpty => liquidMinor == 0 && cardMinor == 0 && investedMinor == 0;
}
