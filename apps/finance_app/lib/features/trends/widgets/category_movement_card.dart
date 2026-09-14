import 'package:flutter/material.dart';

import '../../../data/category_movement.dart';
import '../../../core/format/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/indicators.dart';
import '../../../core/widgets/section_card.dart';

/// Each category's spend against its own historical average.
///
/// This is the closest thing to an "insight" the app can produce without a
/// model, and it is often the most useful: it answers "what got expensive"
/// with the user's own baseline rather than an arbitrary threshold.
class CategoryMovementCard extends StatelessWidget {
  const CategoryMovementCard({required this.movements, super.key});

  final List<CategoryMovement> movements;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);

    return SectionCard(
      title: 'Against your own average',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final movement in movements.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      movement.category,
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    Money.format(movement.currentMinor, decimals: false),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 76,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _DeltaBadge(
                        delta: movement.deltaPercent,
                        isFlat: movement.isFlat,
                        money: money,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Text(
            'A category well above its own average is the first place to look '
            'when a month feels expensive.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  const _DeltaBadge({
    required this.delta,
    required this.isFlat,
    required this.money,
  });

  final double? delta;
  final bool isFlat;
  final MoneyColors money;

  @override
  Widget build(BuildContext context) {
    final value = delta;
    if (value == null) {
      return Text(
        'new',
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: money.neutral),
      );
    }
    // Within 5% is noise on one household month, so it is shown neutral rather
    // than flagged. Crying wolf would train the user to ignore the signal.
    final color = isFlat
        ? money.neutral
        : (value > 0 ? money.expense : money.income);
    return Pill(
      text: '${value >= 0 ? '+' : ''}${value.toStringAsFixed(0)}%',
      color: color,
    );
  }
}
