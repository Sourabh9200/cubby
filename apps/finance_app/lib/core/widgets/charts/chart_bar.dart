import 'package:flutter/material.dart';

/// A single bar, guaranteed to have a width.
///
/// A `Container` given only a height collapses to zero width inside a `Column`:
/// `Container` wraps a childless box in a `LimitedBox(maxWidth: 0)`, so a bar
/// built that way is invisible — with no error, nothing in the semantics tree,
/// and nothing for a test that is not looking at geometry to catch. A device run
/// found exactly that in the weekday chart. This widget states the trap once, in
/// the one place that has to get it right, and makes the bars findable by type.
///
/// The height is the caller's: a chart that reserves a fixed area for its bars
/// and lets the labels take their own height cannot overflow when a label wraps
/// on a narrow screen.
class ChartBar extends StatelessWidget {
  const ChartBar({
    required this.height,
    required this.color,
    this.radius = const BorderRadius.vertical(top: Radius.circular(4)),
    super.key,
  });

  final double height;
  final Color color;

  /// Rounded on top by default, because a bar is read as growing upward.
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, borderRadius: radius),
      ),
    );
  }
}
