/// UPI virtual payment addresses and bank account numbers.
///
/// UPI is the highest-volume payment rail in India, so merchant strings
/// routinely arrive as `merchant@psp` rather than a human-readable name.
library;

import '../pii.dart';

/// UPI VPAs, discriminated from email addresses structurally.
///
/// The discriminator is the dot: every routable email domain contains one
/// (`gmail.com`), while UPI handles never do (`okhdfcbank`, `ybl`). That gives
/// a clean split without needing to hardcode an exhaustive PSP list, which
/// would go stale as new payment-service providers launch.
class UpiVpaDetector extends RegexDetector {
  const UpiVpaDetector();

  /// Well-known PSP handles. Used to raise confidence, not as a gate.
  static const Set<String> knownHandles = <String>{
    'ybl',
    'ibl',
    'axl',
    'apl',
    'upi',
    'paytm',
    'ptyes',
    'ptaxis',
    'ptsbi',
    'pthdfc',
    'okaxis',
    'okhdfcbank',
    'okicici',
    'oksbi',
    'okbizaxis',
    'okyes',
    'sbi',
    'hdfcbank',
    'icici',
    'kotak',
    'axisbank',
    'yesbank',
    'barodampay',
    'jupiteraxis',
    'fam',
    'freecharge',
    'airtel',
    'airtelpaymentsbank',
    'idfcbank',
    'indus',
    'federal',
    'rbl',
    'dbs',
    'timecosmos',
    'waaxis',
    'wahdfcbank',
    'waicici',
    'wasbi',
    'naviaxis',
    'slice',
    'superyes',
    'amazonpay',
    'navi',
  };

  @override
  PiiKind get kind => PiiKind.upiVpa;

  @override
  RegExp get pattern => RegExp(r'[A-Za-z0-9._\-]{2,}@[A-Za-z]{2,}');

  @override
  bool validate(RegExpMatch match) {
    // The pattern cannot see past its own end, so `ramesh@gmail.com` would
    // otherwise match as `ramesh@gmail`. A following dot means this is an email
    // domain, which the email detector owns.
    if (isDotAt(match, match.end)) {
      return false;
    }
    final value = match.group(0)!;
    final domain = value.substring(value.lastIndexOf('@') + 1).toLowerCase();
    if (domain.contains('.')) {
      return false;
    }
    if (knownHandles.contains(domain)) {
      return true;
    }
    // Unknown PSPs are accepted only if the handle is long enough to be a real
    // provider name rather than noise.
    return domain.length >= 4;
  }

  @override
  String normalize(RegExpMatch match) => match.group(0)!.toLowerCase();
}

/// Bank account and card numbers, but only when a label introduces them.
///
/// A bare 9-to-18 digit run is hopeless to classify: it could be an account
/// number, a cheque number, an amount in paise, or a reference. Requiring a
/// nearby anchor such as `a/c` makes this precise enough to enable by default.
/// Masked forms (`XXXX1234`) are covered too, since that is how most bank
/// statements actually print account numbers.
class BankAccountDetector extends ContextAnchoredDetector {
  const BankAccountDetector();

  @override
  PiiKind get kind => PiiKind.bankAccount;

  @override
  List<String> get anchors => const <String>[
    'a/c',
    'ac no',
    'acct',
    'account',
    'acc no',
    'ac no.',
    'card no',
    'card ending',
    'card ends',
    'ending in',
    'ending with',
    'ending',
    'aadhaar linked',
    'mmid',
    'customer id',
    'cif',
  ];

  @override
  int get anchorWindow => 32;

  @override
  RegExp get pattern => RegExp(r'\d{9,18}|[xX\*•]{2,}[\s\-]?\d{2,4}');

  @override
  bool validate(RegExpMatch match) {
    if (!hasNoAdjacentDigit(match)) {
      return false;
    }
    return super.validate(match);
  }
}

/// Bank and payment reference numbers (UTR, RRN, cheque numbers).
///
/// These are quasi-identifiers rather than direct identifiers, but they are
/// sufficient to look up a real transaction in a bank portal, so they should
/// not be shipped to a third party either.
class BankReferenceDetector extends ContextAnchoredDetector {
  const BankReferenceDetector();

  @override
  PiiKind get kind => PiiKind.bankReference;

  @override
  List<String> get anchors => const <String>[
    'utr',
    'rrn',
    'ref no',
    'refno',
    'ref:',
    'ref ',
    'reference',
    'txn id',
    'txnid',
    'transaction id',
    'cheque',
    'chq',
    'ch no',
    'neft',
    'imps',
    'rtgs',
    'upi ref',
    'order id',
    'arn',
  ];

  @override
  RegExp get pattern =>
      RegExp(r'(?=[A-Za-z0-9]*\d)[A-Za-z0-9]{6,22}', caseSensitive: false);

  @override
  bool validate(RegExpMatch match) {
    if (!hasNoAdjacentDigit(match)) {
      return false;
    }
    // Require a digit so that ordinary words following "ref " are not eaten.
    if (!RegExp(r'\d').hasMatch(match.group(0)!)) {
      return false;
    }
    return super.validate(match);
  }

  @override
  String normalize(RegExpMatch match) => match.group(0)!.toUpperCase();
}
