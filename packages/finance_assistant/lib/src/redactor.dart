/// The redaction pipeline entry point.
library;

import 'detectors/default_detectors.dart';
import 'detectors/keyword_detector.dart';
import 'pii.dart';
import 'pii_vault.dart';

/// The outcome of redacting one piece of text.
final class RedactionResult {
  const RedactionResult({
    required this.text,
    required this.spans,
    required this.vault,
  });

  /// The redacted text. This is the only form safe to transmit.
  final String text;

  /// What was found, in source order.
  final List<PiiSpan> spans;

  /// Vault holding the plaintext originals. Never transmit this.
  final PiiVault vault;

  /// True when nothing needed redacting.
  bool get isClean => spans.isEmpty;

  /// Distinct kinds found, for a user-facing summary such as
  /// "2 phone numbers and 1 email were hidden".
  Set<PiiKind> get kinds => spans.map((span) => span.kind).toSet();

  /// Re-hydrates a model reply. Convenience passthrough to [PiiVault.restore].
  String restore(String modelReply) => vault.restore(modelReply);

  @override
  String toString() => 'RedactionResult(${spans.length} spans)';
}

/// Finds and replaces PII before text leaves the device.
///
/// The pipeline is intentionally simple and synchronous: collect candidate
/// spans from every detector, resolve overlaps deterministically, then rewrite
/// in a single left-to-right pass. Because replacement happens in one pass over
/// non-overlapping spans, a redacted token can never be re-scanned, which
/// removes a whole class of idempotency bugs.
class Redactor {
  /// Builds a redactor over [detectors], defaulting to [defaultDetectors].
  ///
  /// [denyList] registers literal strings that must always be hidden — the
  /// user's own name, an employer, a landlord. This is the intended answer to
  /// the fact that pattern detection cannot find a name written in prose, and
  /// it is the highest-value configuration a caller can supply.
  Redactor({
    List<PiiDetector>? detectors,
    Iterable<String> denyList = const <String>[],
  }) : detectors = _compose(detectors, denyList);

  final List<PiiDetector> detectors;

  static List<PiiDetector> _compose(
    List<PiiDetector>? detectors,
    Iterable<String> denyList,
  ) {
    final base = detectors ?? defaultDetectors();
    if (denyList.isEmpty) {
      return List<PiiDetector>.unmodifiable(base);
    }
    return List<PiiDetector>.unmodifiable(<PiiDetector>[
      ...base,
      KeywordDetector(denyList),
    ]);
  }

  /// Redacts [input], reusing [vault] when continuing a conversation so that a
  /// given value keeps the same token across turns.
  RedactionResult redact(String input, {PiiVault? vault}) {
    final effectiveVault = vault ?? PiiVault();
    final spans = _resolveOverlaps(_collect(input));
    if (spans.isEmpty) {
      return RedactionResult(text: input, spans: spans, vault: effectiveVault);
    }
    final buffer = StringBuffer();
    var cursor = 0;
    for (final span in spans) {
      buffer
        ..write(input.substring(cursor, span.start))
        ..write(effectiveVault.tokenFor(span.kind, span.normalized, span.text));
      cursor = span.end;
    }
    buffer.write(input.substring(cursor));
    return RedactionResult(
      text: buffer.toString(),
      spans: spans,
      vault: effectiveVault,
    );
  }

  /// Finds every span reported by any detector.
  ///
  /// A detector that throws is a bug, not a pass: letting the exception escape
  /// is deliberate, because silently continuing would transmit data the
  /// detector was responsible for catching.
  List<PiiSpan> _collect(String input) => detectors
      .expand((detector) => detector.detect(input))
      .toList(growable: false);

  /// Picks a non-overlapping subset of [spans].
  ///
  /// Policy, in order: earliest start wins; then the longest match; then a
  /// context-anchored match; then the higher-precedence kind.
  ///
  /// The context tie-breaker matters in practice. A 14-digit Indian account
  /// number passes the Luhn check about 10% of the time by coincidence, so
  /// without this rule `A/c 50100123456789` would be reported as a card. It is
  /// still redacted either way, but the token prefix is part of the wire
  /// contract and the audit display, so it should be right.
  static List<PiiSpan> _resolveOverlaps(List<PiiSpan> spans) {
    final sorted = List<PiiSpan>.of(spans)
      ..sort((a, b) {
        final byStart = a.start.compareTo(b.start);
        if (byStart != 0) {
          return byStart;
        }
        final byLength = b.length.compareTo(a.length);
        if (byLength != 0) {
          return byLength;
        }
        // Contextual evidence beats a probabilistic property of the value.
        final byContext = (b.contextAnchored ? 1 : 0).compareTo(
          a.contextAnchored ? 1 : 0,
        );
        if (byContext != 0) {
          return byContext;
        }
        return b.kind.precedence.compareTo(a.kind.precedence);
      });
    final accepted = <PiiSpan>[];
    for (final candidate in sorted) {
      final overlaps = accepted.any(
        (kept) => candidate.start < kept.end && kept.start < candidate.end,
      );
      if (!overlaps) {
        accepted.add(candidate);
      }
    }
    accepted.sort((a, b) => a.start.compareTo(b.start));
    return accepted;
  }
}
