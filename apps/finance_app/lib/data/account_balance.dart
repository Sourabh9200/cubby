import 'package:flutter/foundation.dart';

/// An account and its computed balance.
@immutable
class AccountBalance {
  const AccountBalance({
    required this.id,
    required this.name,
    required this.type,
    required this.balanceMinor,
  });

  final String id;
  final String name;
  final String type;

  /// Opening balance plus every recorded movement. Signed, because a credit
  /// card balance is normally negative.
  final int balanceMinor;

  /// True when the account owes money, which changes how the number should be
  /// presented rather than merely whether it is negative.
  bool get isLiability => balanceMinor < 0;
}
