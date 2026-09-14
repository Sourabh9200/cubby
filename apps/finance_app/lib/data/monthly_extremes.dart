/// Which of the three measures a [MetricExtremes] entry describes.
///
/// Bare, with no labels or colours attached: wording and hue are the screen's
/// business, and a data type that carried them would have to change every time
/// the wording did.
enum MetricMeasure { expense, income, investment }

/// One month's figure for a measure, at the point where it was highest or
/// lowest.
class MonthPeak {
  const MonthPeak({required this.month, required this.totalMinor});

  /// The month, at its first instant.
  final DateTime month;

  final int totalMinor;
}

/// The highest and lowest month on record for one measure.
///
/// [highest] and [lowest] are null rather than zero when no month recorded the
/// measure at all. A brand-new install has spent nothing, and reporting "lowest
/// spend: ₹0 in September" would be a statement about the absence of data
/// dressed up as a statement about the user's money.
class MetricExtremes {
  const MetricExtremes({
    required this.measure,
    this.highest,
    this.lowest,
    this.averageMinor = 0,
  });

  final MetricMeasure measure;

  final MonthPeak? highest;
  final MonthPeak? lowest;

  /// Mean figure across the months that recorded this measure, rounded down to
  /// whole minor units.
  ///
  /// An average over *recording* months rather than over every month, so a month
  /// the app did not exist for cannot drag the figure toward zero.
  final int averageMinor;

  /// True when at least one month recorded this measure.
  bool get hasData => highest != null && lowest != null;

  /// True when every recording month had the same figure — a fixed salary, for
  /// instance — so an average beside it would just repeat the same number.
  bool get isFlat => !hasData || highest!.totalMinor == lowest!.totalMinor;
}
