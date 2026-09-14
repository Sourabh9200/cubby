import 'package:flutter/material.dart';

/// A horizontal row of single-select chips.
///
/// Used for both the category and the account picker on the quick-add sheet.
/// A horizontally scrolling chip row is faster than a dropdown here: everything
/// is one tap, and the current selection stays visible while the amount pad is
/// in use.
class ChipSelector<T> extends StatelessWidget {
  const ChipSelector({
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.valueOf,
    required this.onSelected,
    this.height = 44,
    super.key,
  });

  final List<T> options;

  /// The currently selected value, or null when nothing is chosen yet.
  final String? selected;

  final String Function(T option) labelOf;
  final String Function(T option) valueOf;
  final ValueChanged<T> onSelected;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          return ChoiceChip(
            label: Text(labelOf(option)),
            selected: valueOf(option) == selected,
            onSelected: (_) => onSelected(option),
          );
        },
      ),
    );
  }
}
