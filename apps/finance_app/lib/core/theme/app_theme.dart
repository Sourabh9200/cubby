import 'package:flutter/material.dart';

/// Semantic colors for money.
///
/// Kept separate from the Material scheme because "income" and "expense" are
/// domain meanings, not theme roles. A green that reads as "positive" in light
/// mode can look neon in dark mode, so each is defined per brightness.
class MoneyColors {
  const MoneyColors({
    required this.income,
    required this.expense,
    required this.investment,
    required this.warning,
    required this.neutral,
  });

  final Color income;
  final Color expense;

  /// Money moved into an asset.
  ///
  /// A third hue rather than reusing income's green: an investment is not money
  /// arriving, and drawing it in the same colour would make a month of heavy
  /// investing look like a month of heavy earning on every chart.
  final Color investment;

  final Color warning;
  final Color neutral;

  static const MoneyColors light = MoneyColors(
    income: Color(0xFF0F9D58),
    expense: Color(0xFFD93025),
    investment: Color(0xFF1A73E8),
    warning: Color(0xFFE8710A),
    neutral: Color(0xFF5F6368),
  );

  static const MoneyColors dark = MoneyColors(
    income: Color(0xFF4ADE80),
    expense: Color(0xFFF87171),
    investment: Color(0xFF60A5FA),
    warning: Color(0xFFFBBF24),
    neutral: Color(0xFF9AA0A6),
  );

  static MoneyColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// Fixed, ordered palette for category charts.
///
/// Order matters: adjacent slices in a pie or stacked bar must be
/// distinguishable, so the sequence alternates warm and cool hues rather than
/// running through a single gradient. Both variants were checked for
/// sufficient contrast against their respective surfaces.
class CategoryPalette {
  const CategoryPalette._();

  static const List<Color> light = <Color>[
    Color(0xFF4F46E5), // indigo
    Color(0xFFF59E0B), // amber
    Color(0xFF059669), // emerald
    Color(0xFFDB2777), // pink
    Color(0xFF0284C7), // sky
    Color(0xFF9333EA), // purple
    Color(0xFFCA8A04), // gold
    Color(0xFFDC2626), // red
    Color(0xFF0D9488), // teal
    Color(0xFF7C3AED), // violet
  ];

  static const List<Color> dark = <Color>[
    Color(0xFF818CF8),
    Color(0xFFFCD34D),
    Color(0xFF34D399),
    Color(0xFFF472B6),
    Color(0xFF38BDF8),
    Color(0xFFC084FC),
    Color(0xFFFACC15),
    Color(0xFFFCA5A5),
    Color(0xFF2DD4BF),
    Color(0xFFA78BFA),
  ];

  static List<Color> of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  /// Deterministic color for a category name, so the same category keeps the
  /// same color across sessions and across charts.
  static Color forLabel(BuildContext context, String label) {
    final colors = of(context);
    var hash = 0;
    for (final unit in label.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return colors[hash % colors.length];
  }
}

/// App-wide theming.
class AppTheme {
  const AppTheme._();

  static const Color _seed = Color(0xFF4F46E5);

  /// Corner radius used by cards, sheets, and inputs.
  static const double radius = 16;

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    final base = ThemeData(colorScheme: scheme, brightness: brightness);

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide.none,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        space: 1,
        thickness: 1,
      ),
    );
  }
}
