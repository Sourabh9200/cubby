import 'package:intl/intl.dart';

/// Money formatting for Indian rupees.
///
/// All amounts in this app are integer **minor units** (paise). Floats are
/// never used for money: `0.1 + 0.2 != 0.3` in binary floating point, and a
/// rounding error that silently loses a rupee is exactly the kind of bug that
/// destroys trust in a finance app.
class Money {
  const Money._();

  static const String symbol = '₹';

  /// Indian digit grouping. `en_IN` groups as 1,23,456.78 (lakh/crore style),
  /// not 123,456.78. Using the wrong locale here is a visible correctness bug
  /// to any Indian user.
  static const String locale = 'en_IN';

  static final NumberFormat _twoDecimals = NumberFormat.currency(
    locale: locale,
    symbol: symbol,
    decimalDigits: 2,
  );

  static final NumberFormat _noDecimals = NumberFormat.currency(
    locale: locale,
    symbol: symbol,
    decimalDigits: 0,
  );

  /// `1234567` -> `₹12,345.67`
  static String format(int minor, {bool decimals = true}) =>
      (decimals ? _twoDecimals : _noDecimals).format(minor / 100);

  /// Compact form for chart labels and summary tiles: `₹1.2L`, `₹45K`, `₹2.4Cr`.
  ///
  /// Uses Indian units because "million" is not how anyone reads a salary or a
  /// house price here.
  static String compact(int minor) {
    final rupees = minor / 100;
    final magnitude = rupees.abs();
    final sign = rupees < 0 ? '-' : '';
    if (magnitude >= 10000000) {
      return '$sign$symbol${(magnitude / 10000000).toStringAsFixed(2)}Cr';
    }
    if (magnitude >= 100000) {
      return '$sign$symbol${(magnitude / 100000).toStringAsFixed(1)}L';
    }
    if (magnitude >= 1000) {
      return '$sign$symbol${(magnitude / 1000).toStringAsFixed(0)}K';
    }
    return '$sign$symbol${magnitude.toStringAsFixed(0)}';
  }

  /// Always shows an explicit sign, for ledger rows.
  static String signed(int minor) {
    final prefix = minor > 0 ? '+' : (minor < 0 ? '-' : '');
    return '$prefix${format(minor.abs())}';
  }

  /// Percentage change between two periods, or `null` when [previous] is zero
  /// and the change is therefore undefined rather than infinite.
  static double? percentChange(int current, int previous) {
    if (previous == 0) {
      return null;
    }
    return ((current - previous) / previous.abs()) * 100;
  }
}

/// Date labels used across the ledger and charts.
class DateLabels {
  const DateLabels._();

  static final DateFormat _monthYear = DateFormat('MMMM yyyy');
  static final DateFormat _shortMonth = DateFormat('MMM');
  static final DateFormat _dayMonth = DateFormat('d MMM');
  static final DateFormat _weekday = DateFormat('EEEE');

  static String monthYear(DateTime date) => _monthYear.format(date);
  static String shortMonth(DateTime date) => _shortMonth.format(date);
  static String dayMonth(DateTime date) => _dayMonth.format(date);
  static String weekday(DateTime date) => _weekday.format(date);

  /// "Today" / "Yesterday" / "13 Aug" — how a ledger should actually read.
  static String ledgerHeader(DateTime date, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final difference = today.difference(target).inDays;
    if (difference == 0) {
      return 'Today';
    }
    if (difference == 1) {
      return 'Yesterday';
    }
    return _dayMonth.format(date);
  }
}
