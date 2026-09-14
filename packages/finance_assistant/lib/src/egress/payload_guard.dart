// ignore_for_file: prefer_final_locals
//
// The lint fires on switch-pattern bindings (`case String value:`), which
// cannot be annotated `final`. Everything else in this file is final.

/// Last-line-of-defense inspection of an outbound payload.
///
/// Everything upstream is designed to make a leak impossible. This guard exists
/// for the case where that design is wrong. It is deliberately paranoid and
/// deliberately duplicated: it re-runs the full detector set over the final
/// serialized values, and it rejects any field name it does not recognize, so a
/// future refactor that adds a `note` field fails loudly instead of quietly
/// widening the blast radius.
library;

import '../redactor.dart';
import 'guard_report.dart';

/// Validates a payload against the egress policy.
class PayloadGuard {
  /// Creates a guard.
  ///
  /// [allowedKeys] is the recursive key allowlist. [maxNumericDigits] bounds how
  /// long a bare integer may be before it is treated as a possible identifier
  /// rather than an amount.
  PayloadGuard({
    required this.redactor,
    required this.allowedKeys,
    this.maxNumericDigits = 12,
  });

  final Redactor redactor;
  final Set<String> allowedKeys;
  final int maxNumericDigits;

  /// Matches a placeholder token, whose index must not be mistaken for a long
  /// numeric identifier.
  static final RegExp _token = RegExp(r'\[[A-Z]+_\d+\]');

  /// Throws [PiiLeakException] when [payload] is not safe to transmit.
  void assertClean(Map<String, Object?> payload) {
    final report = inspect(payload);
    if (!report.isClean) {
      throw PiiLeakException(report);
    }
  }

  /// Non-throwing inspection, for the review-before-send UI.
  GuardReport inspect(Object? payload) {
    final violations = <GuardViolation>[];
    _walk(payload, r'$', violations);
    return GuardReport(List<GuardViolation>.unmodifiable(violations));
  }

  void _walk(Object? node, String path, List<GuardViolation> out) {
    switch (node) {
      case null || bool():
        return;
      case Map<Object?, Object?> map:
        for (final entry in map.entries) {
          final key = entry.key;
          if (key is! String) {
            out.add(
              GuardViolation(
                kind: ViolationKind.nonStringKey,
                path: path,
                detail:
                    'Key of runtime type ${key.runtimeType} is not a String.',
              ),
            );
            continue;
          }
          if (!allowedKeys.contains(key)) {
            out.add(
              GuardViolation(
                kind: ViolationKind.unknownKey,
                path: '$path.$key',
                detail:
                    'Key "$key" is not in the egress allowlist. Adding a '
                    'field requires updating SanitizedContext.jsonKeys and '
                    'reviewing its privacy impact.',
              ),
            );
          }
          _walk(entry.value, '$path.$key', out);
        }
      case List<Object?> list:
        for (var i = 0; i < list.length; i++) {
          _walk(list[i], '$path[$i]', out);
        }
      case String value:
        _checkText(value, path, out);
      case int value:
        _checkLongNumber(value.toString(), path, out);
      case double value:
        // Money must never be a double: that is both a correctness bug and a
        // precision leak.
        out.add(
          GuardViolation(
            kind: ViolationKind.disallowedType,
            path: path,
            detail:
                'Double value $value found. Money must be integer minor '
                'units.',
          ),
        );
      default:
        out.add(
          GuardViolation(
            kind: ViolationKind.disallowedType,
            path: path,
            detail:
                'Type ${node.runtimeType} is not permitted in a payload. '
                'Only null, String, int, bool, List, and Map are allowed.',
          ),
        );
    }
  }

  void _checkText(String value, String path, List<GuardViolation> out) {
    final result = redactor.redact(value);
    if (!result.isClean) {
      final kinds = result.spans.map((span) => span.kind.name).toSet();
      out.add(
        GuardViolation(
          kind: ViolationKind.piiDetected,
          path: path,
          detail:
              'Detector matched $kinds in value "${preview(value)}", which '
              'means a redaction step was skipped upstream.',
        ),
      );
    }
    _checkLongNumber(value, path, out);
  }

  void _checkLongNumber(String value, String path, List<GuardViolation> out) {
    if (_token.hasMatch(value)) {
      return;
    }
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= maxNumericDigits) {
      return;
    }
    out.add(
      GuardViolation(
        kind: ViolationKind.suspiciousNumber,
        path: path,
        detail:
            'Value "${preview(value)}" holds ${digits.length} digits, '
            'which exceeds the $maxNumericDigits-digit ceiling for an amount.',
      ),
    );
  }

  /// Bounds a value for error messages, so a violation report cannot itself
  /// become a leak into a crash log.
  static String preview(String value) {
    const limit = 24;
    return value.length <= limit ? value : '${value.substring(0, limit)}…';
  }
}
