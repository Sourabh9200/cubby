import 'package:flutter/widgets.dart';

import 'app_lock.dart';

/// The app-lock state the whole tree shares.
///
/// A [ChangeNotifier] rather than a plain value because turning the lock on in
/// Settings has to reach the gate already mounted above the app. Without that,
/// enabling the lock would appear to do nothing until the next launch — which is
/// exactly when a user would conclude it was broken.
class AppLockController extends ChangeNotifier {
  AppLockController({required this.lock});

  /// The platform prompt the gate and the settings toggle both go through.
  final AppLock lock;

  /// Off until [setEnabled] says otherwise.
  ///
  /// Assigned rather than passed to the constructor so the field can stay
  /// private: an `enabled` that anyone can set directly is one that can be
  /// changed without the gate being told.
  bool _enabled = false;

  /// Whether the gate is on.
  bool get enabled => _enabled;

  /// Called after the setting has been persisted, so the tree and the database
  /// never disagree.
  void setEnabled(bool value) {
    if (_enabled == value) {
      return;
    }
    _enabled = value;
    notifyListeners();
  }
}

/// Provides the [AppLockController], rebuilding dependents when the lock is
/// turned on or off.
///
/// `InheritedNotifier` rather than `InheritedWidget` so the gate does not need a
/// `setState` plumbed down to it from Settings.
class AppLockScope extends InheritedNotifier<AppLockController> {
  const AppLockScope({
    required AppLockController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static AppLockController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppLockScope>();
    assert(scope != null, 'No AppLockScope found in the widget tree.');
    return scope!.notifier!;
  }
}
