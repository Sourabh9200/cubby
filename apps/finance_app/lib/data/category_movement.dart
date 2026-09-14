/// One category's spend against its own historical average.
class CategoryMovement {
  const CategoryMovement({
    required this.category,
    required this.currentMinor,
    required this.averageMinor,
  });

  final String category;
  final int currentMinor;
  final int averageMinor;

  /// Percentage change against the average, or null when the average is zero
  /// and the change is therefore undefined rather than infinite.
  double? get deltaPercent => averageMinor == 0
      ? null
      : (currentMinor - averageMinor) / averageMinor * 100;

  /// True when the movement is small enough to be noise rather than signal.
  ///
  /// Five percent on a single household month is well inside normal variance,
  /// so flagging it would train the user to ignore the flag entirely.
  bool get isFlat => (deltaPercent ?? 0).abs() < 5;
}
