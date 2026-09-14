import 'package:flutter/widgets.dart';

import 'finance_repository.dart';
import 'finance_snapshot.dart';

/// Provides the current snapshot, and the repository for writes, to the tree.
///
/// Two accessors on purpose. Reads go through an immutable [FinanceSnapshot],
/// which no widget can mutate and which is therefore always internally
/// consistent. Writes go through the repository. A widget that only reads
/// cannot accidentally write, and a write cannot leave a reader holding a
/// half-updated view.
class RepositoryScope extends InheritedWidget {
  const RepositoryScope({
    required this.snapshot,
    required this.repository,
    required super.child,
    super.key,
  });

  final FinanceSnapshot snapshot;
  final FinanceRepository repository;

  /// The current snapshot. Named `of` so existing call sites read unchanged.
  static FinanceSnapshot of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RepositoryScope>();
    assert(scope != null, 'No RepositoryScope found in the widget tree.');
    return scope!.snapshot;
  }

  /// The repository, for screens that need to write.
  static FinanceRepository actions(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RepositoryScope>();
    assert(scope != null, 'No RepositoryScope found in the widget tree.');
    return scope!.repository;
  }

  @override
  bool updateShouldNotify(RepositoryScope oldWidget) =>
      !identical(oldWidget.snapshot, snapshot);
}
