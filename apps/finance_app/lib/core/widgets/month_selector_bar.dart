import 'package:flutter/material.dart';

import '../../data/month_scope.dart';
import '../format/money.dart';

/// Chevrons around the month being shown, for the aggregate screens.
///
/// Sits in the app bar's `bottom` rather than in its title: the row needs the
/// full width for three controls plus the label, and on a narrow phone the title
/// area has none to spare once the screen's own actions are in place.
///
/// Placed on both the overview and trends so one selection drives both. A month
/// picker per screen would let the two show different months while looking
/// identical, which is precisely the confusion it exists to remove.
class MonthSelectorBar extends StatelessWidget {
  const MonthSelectorBar({super.key});

  /// Height the app bar reserves for this bar.
  static const double height = 56;

  @override
  Widget build(BuildContext context) {
    final scope = MonthScope.of(context);
    final theme = Theme.of(context);

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              tooltip: 'Previous month',
              // Disabled at the first month with data rather than allowed into
              // empty months, where every figure would read ₹0 and look like
              // lost data rather than absent data.
              onPressed: scope.canGoBack ? () => scope.step(-1) : null,
            ),
            Expanded(
              child: Text(
                DateLabels.monthYear(scope.month),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              tooltip: 'Next month',
              onPressed: scope.canGoForward ? () => scope.step(1) : null,
            ),
            if (!scope.isCurrentMonth)
              TextButton(
                onPressed: () => scope.onChanged(scope.latest),
                child: const Text('This month'),
              ),
          ],
        ),
      ),
    );
  }
}
