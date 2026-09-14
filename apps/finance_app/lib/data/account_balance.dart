import 'package:flutter/foundation.dart';

/// An account and its computed balance.
@immutable
class AccountBalance {
  const AccountBalance({
    required this.id,
    required this.name,
    required this.type,
    required this.balanceMinor,
    this.openingBalanceMinor = 0,
  });

  final String id;
  final String name;
  final String type;

  /// Opening balance plus every recorded movement. Signed, because a credit
  /// card balance is normally negative.
  final int balanceMinor;

  /// What the account started with, before any recorded movement.
  ///
  /// Carried so a balance can be reconstructed at an earlier point in time and
  /// not only today: a net-worth line is a series of balances, and only the last
  /// of them is [balanceMinor].
  final int openingBalanceMinor;

  /// True when the account owes money, which changes how the number should be
  /// presented rather than merely whether it is negative.
  bool get isLiability => balanceMinor < 0;

  /// True for a credit card, whose balance is money owed rather than money held.
  ///
  /// The stored type is the schema's `AccountType.name`, resolved here so no
  /// widget has to know the string.
  bool get isCreditCard => type == 'creditCard';
}
