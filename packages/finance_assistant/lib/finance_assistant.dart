/// Privacy boundary for every LLM call in the finance app.
///
/// ## Why this package exists
///
/// Financial data is personal data. Sending it to a hosted model means it is
/// logged, retained, and — on the free tiers of most providers — potentially
/// used to improve their products. So the app treats "leave the device" as a
/// privileged operation with exactly one door.
///
/// ## The guarantee
///
/// This package deliberately has **zero runtime dependencies**, and it does not
/// import the database package. The only payload type a transport may accept is
/// [SanitizedContext], which structurally cannot hold a payee, a note, an
/// account identifier, or a transaction id. Raw rows therefore have no
/// type-level route to the network.
///
/// ## The layers
///
/// 1. **Schema** — the query behind [RawCategoryAggregate] never selects PII
///    columns in the first place.
/// 2. **Type** — [SanitizedContext] is the only thing a transport accepts.
/// 3. **Value** — [Redactor] scrubs free text that must pass through, such as
///    user-authored category names.
/// 4. **Aggregate** — amounts are bucketed and small groups are merged.
/// 5. **Egress** — [PayloadGuard] re-scans the finished payload and rejects
///    unknown fields. This is the layer that catches our own mistakes.
/// 6. **Verification** — the privacy test suite injects unique canary values
///    into every field and asserts none of them reach the payload.
///
/// ## What this is not
///
/// Not a guarantee. Detection is excellent for structured identifiers and
/// deliberately conservative for free text, so an unregistered proper noun can
/// still slip through. Register those with `KeywordDetector`, keep
/// [Granularity] coarse, and treat this as risk reduction rather than
/// absolution.
library;

export 'src/checksums.dart' show isValidIban, mod97, passesLuhn, passesVerhoeff;
export 'src/detectors/default_detectors.dart' show defaultDetectors;
export 'src/detectors/india_account_detectors.dart'
    show BankAccountDetector, BankReferenceDetector, UpiVpaDetector;
export 'src/detectors/india_detectors.dart'
    show AadhaarDetector, GstinDetector, IfscDetector, PanDetector;
export 'src/detectors/keyword_detector.dart' show KeywordDetector;
export 'src/detectors/network_detectors.dart'
    show
        IbanDetector,
        IpAddressDetector,
        MacAddressDetector,
        PaymentCardDetector,
        SecretDetector;
export 'src/detectors/structured_detectors.dart'
    show EmailDetector, PhoneDetector;
export 'src/egress/guard_report.dart'
    show GuardReport, GuardViolation, PiiLeakException, ViolationKind;
export 'src/egress/payload_guard.dart' show PayloadGuard;
export 'src/pii.dart'
    show
        ContextAnchoredDetector,
        PiiDetector,
        PiiKind,
        PiiKindLabel,
        PiiSpan,
        RegexDetector;
export 'src/pii_vault.dart' show IssuedToken, PiiVault;
export 'src/redaction/context_builder.dart' show SanitizedContextBuilder;
export 'src/redactor.dart' show RedactionResult, Redactor;
export 'src/sanitized_context.dart'
    show CategoryTotal, Granularity, RawCategoryAggregate, SanitizedContext;
