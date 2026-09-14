import 'package:flutter/foundation.dart';

/// One payee's spending inside a range.
///
/// The payee is the string the user typed, verbatim. Nothing in this app merges
/// "AMAZON INDIA" with "Amazon": fusing two spellings invents a merchant
/// identity the ledger never recorded, and the user cannot tell it happened
/// (C8).
@immutable
class PayeeTotal {
  const PayeeTotal({
    required this.payee,
    required this.totalMinor,
    required this.count,
  });

  final String payee;
  final int totalMinor;

  /// How many entries the total covers.
  final int count;

  /// Mean entry size, rounded down to whole minor units.
  int get averageMinor => count == 0 ? 0 : totalMinor ~/ count;
}

/// One month of a single payee's spending, for the drill-down series.
@immutable
class PayeeMonthTotal {
  const PayeeMonthTotal({
    required this.month,
    required this.totalMinor,
    required this.count,
  });

  /// The month, at its first instant.
  final DateTime month;

  final int totalMinor;
  final int count;
}
