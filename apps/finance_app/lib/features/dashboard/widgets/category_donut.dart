import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/indicators.dart';
import '../../../data/models.dart';

/// Donut chart of spend by category, with a legend that carries the numbers.
///
/// The legend is not decoration: a donut communicates proportion well and
/// magnitude badly, so every slice's actual amount is printed beside it. The
/// total sits in the hole, where the eye already goes.
class CategoryDonut extends StatelessWidget {
  const CategoryDonut({required this.spends, this.maxSlices = 7, super.key});

  final List<CategorySpend> spends;

  /// Categories beyond this count are merged into a single "Other" slice so the
  /// ring stays readable — beyond roughly seven arcs the eye cannot compare them
  /// anyway.
  ///
  /// The *legend* is not capped: it lists every category, with the merged ones
  /// drawn in the "Other" colour. A legend that omitted the tail is how a
  /// category the user had just spent from disappeared from this screen, which
  /// reads as a lost entry rather than as a chart simplification.
  final int maxSlices;

  @override
  Widget build(BuildContext context) {
    if (spends.isEmpty) {
      return const SizedBox(
        height: 180,
        child: EmptyState(
          dense: true,
          icon: Icons.pie_chart_outline_rounded,
          title: 'No spending yet',
          message: 'Add a transaction to see where your money is going.',
        ),
      );
    }

    final visible = spends.take(maxSlices).toList();
    final hidden = spends.skip(maxSlices).toList();
    final merged = <CategorySpend>[
      ...visible,
      if (hidden.isNotEmpty)
        CategorySpend(
          category: 'Other',
          totalMinor: hidden.fold(0, (sum, item) => sum + item.totalMinor),
          txnCount: hidden.fold(0, (sum, item) => sum + item.txnCount),
        ),
    ];

    final total = merged.fold(0, (sum, item) => sum + item.totalMinor);
    final theme = Theme.of(context);
    // The colour the ring gives the merged tail, so a legend row past the cap
    // carries the colour of the arc it was drawn inside.
    final otherColor = CategoryPalette.forLabel(context, 'Other');

    return Column(
      children: <Widget>[
        SizedBox(
          height: 196,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 62,
                  startDegreeOffset: -90,
                  sections: merged
                      .map(
                        (item) => PieChartSectionData(
                          value: item.totalMinor.toDouble(),
                          color: CategoryPalette.forLabel(
                            context,
                            item.category,
                          ),
                          radius: 26,
                          showTitle: false,
                        ),
                      )
                      .toList(),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'This month',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    Money.compact(total),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        // Every category, not just the slices. The ordering matches the ring
        // (largest first), so a row past the cap is one of the arcs drawn inside
        // "Other" — and it carries the "Other" colour so the two still agree.
        for (var index = 0; index < spends.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: <Widget>[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: index < maxSlices
                        ? CategoryPalette.forLabel(
                            context,
                            spends[index].category,
                          )
                        : otherColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    spends[index].category,
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${spends[index].shareOf(total).toStringAsFixed(0)}%',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 84,
                  child: Text(
                    Money.format(spends[index].totalMinor, decimals: false),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (hidden.isNotEmpty)
          Text(
            'The ring draws the ${hidden.length} smallest of these as one '
            '"Other" slice. Every category is listed above.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
