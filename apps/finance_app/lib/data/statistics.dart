/// Order statistics over whole minor units.
///
/// One implementation because two callers need one: the projection reads a
/// typical day, and the suggested limits read a typical month. A second median
/// would be a second definition of "typical", and the two figures sit on the same
/// screen.
library;

/// The median of [values], rounding an even count up.
///
/// Rounded up rather than down because every use here produces a figure the user
/// is asked to accept — a limit, or a daily rate in a projection. Rounding a
/// limit down would make it fail by construction on the very month it came from.
int medianOf(List<int> values) {
  assert(values.isNotEmpty, 'a median needs at least one value');
  final sorted = List<int>.of(values)..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) {
    return sorted[middle];
  }
  return (sorted[middle - 1] + sorted[middle] + 1) ~/ 2;
}

/// The value at [percentile] (0 to 1) of [values], by nearest rank.
///
/// Nearest rank rather than an interpolation: a percentile of *spending* that
/// never happened would be a figure the ledger cannot support, and the point of
/// the p90 here is to say "a month like your worst recent one".
int percentileOf(List<int> values, double percentile) {
  assert(values.isNotEmpty, 'a percentile needs at least one value');
  assert(percentile > 0 && percentile <= 1, 'percentile must be within (0, 1]');
  final sorted = List<int>.of(values)..sort();
  final rank = (percentile * sorted.length).ceil().clamp(1, sorted.length);
  return sorted[rank - 1];
}
