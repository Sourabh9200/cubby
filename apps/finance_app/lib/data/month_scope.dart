import 'package:flutter/widgets.dart';

/// The month the aggregate screens are showing.
///
/// One selection shared by the overview and trends rather than one per screen.
/// A per-screen month would let the two disagree while looking identical, which
/// is exactly the confusion the month selector exists to remove.
///
/// Held by the shell rather than by a screen because the shell is what survives a
/// tab change: the ledger keeps its search term there for the same reason, and a
/// month that reset every time the user glanced at another tab would be worse
/// than not having one.
class MonthScope extends InheritedWidget {
  const MonthScope({
    required this.month,
    required this.earliest,
    required this.latest,
    required this.onChanged,
    required super.child,
    super.key,
  });

  /// The month being shown, at its first instant.
  final DateTime month;

  /// Earliest month with data, or null when nothing has been recorded yet.
  ///
  /// Back is blocked at the first month that exists rather than allowed into
  /// empty months where every figure would read as ₹0 — which looks like lost
  /// data rather than an absence of it.
  final DateTime? earliest;

  /// Latest month that may be shown: the month in progress. A future month has
  /// no data by construction, and the entry sheet refuses to record one.
  final DateTime latest;

  final ValueChanged<DateTime> onChanged;

  static MonthScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MonthScope>();
    assert(scope != null, 'No MonthScope found in the widget tree.');
    return scope!;
  }

  bool get canGoBack => earliest != null && month.isAfter(earliest!);

  bool get canGoForward => month.isBefore(latest);

  /// True when the selection is the month in progress.
  bool get isCurrentMonth => !month.isBefore(latest);

  /// Moves [months] forward or back from the current selection.
  void step(int months) =>
      onChanged(DateTime(month.year, month.month + months));

  @override
  bool updateShouldNotify(MonthScope oldWidget) =>
      oldWidget.month != month ||
      oldWidget.earliest != earliest ||
      oldWidget.latest != latest;
}
