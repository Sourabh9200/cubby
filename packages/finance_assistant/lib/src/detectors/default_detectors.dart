/// The default detector set for an Indian personal-finance dataset.
///
/// Order is fixed so that pipeline output is deterministic, which makes the
/// privacy test suite meaningful: a reordering that changes redaction results
/// should show up as a test failure rather than as a silent behavioural drift.
library;

import '../pii.dart';
import 'india_account_detectors.dart';
import 'india_detectors.dart';
import 'keyword_detector.dart';
import 'network_detectors.dart';
import 'structured_detectors.dart';

/// Every detector enabled by default, most-specific first.
List<PiiDetector> defaultDetectors({
  Iterable<String> denyList = const <String>[],
  Iterable<PiiDetector> extra = const <PiiDetector>[],
}) {
  final detectors = <PiiDetector>[
    // Credentials first: a leaked key is immediately exploitable.
    const SecretDetector(),
    // Inherently-sensitive identifiers.
    const PaymentCardDetector(),
    const IbanDetector(),
    const AadhaarDetector(),
    const PanDetector(),
    const GstinDetector(),
    const UpiVpaDetector(),
    const IfscDetector(),
    const EmailDetector(),
    const PhoneDetector(),
    // Context-anchored, so lower recall by design but very high precision.
    const BankAccountDetector(),
    const BankReferenceDetector(),
    // Ambient metadata.
    const IpAddressDetector(),
    const MacAddressDetector(),
    ...extra,
  ];
  if (denyList.isNotEmpty) {
    detectors.add(KeywordDetector(denyList));
  }
  return List<PiiDetector>.unmodifiable(detectors);
}
