/// Violation records produced by the egress guard.
library;

/// Why a payload was rejected.
enum ViolationKind {
  /// A key appeared that is not in the declared allowlist.
  unknownKey,

  /// A detector matched inside a string value.
  piiDetected,

  /// A value's type cannot be safely serialized (for example a `DateTime`,
  /// which would carry more precision than intended).
  disallowedType,

  /// A plain number long enough to be an unmasked account identifier.
  suspiciousNumber,

  /// A non-string key, which would serialize unpredictably.
  nonStringKey,
}

/// One reason a payload was rejected.
final class GuardViolation {
  const GuardViolation({
    required this.kind,
    required this.path,
    required this.detail,
  });

  final ViolationKind kind;

  /// JSON-path-like location, for example `categoryTotals[3].label`.
  final String path;

  final String detail;

  @override
  String toString() => '${kind.name} at $path: $detail';
}

/// The outcome of inspecting a payload.
final class GuardReport {
  const GuardReport(this.violations);

  final List<GuardViolation> violations;

  bool get isClean => violations.isEmpty;

  @override
  String toString() => isClean
      ? 'GuardReport(clean)'
      : 'GuardReport(${violations.length} violations: '
            '${violations.map((v) => v.toString()).join('; ')})';
}

/// Thrown by `PayloadGuard.assertClean`. Carries the full report.
final class PiiLeakException implements Exception {
  const PiiLeakException(this.report);

  final GuardReport report;

  @override
  String toString() => 'PiiLeakException: $report';
}
