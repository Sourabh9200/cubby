/// A generated answer, with the intent that produced it.
///
/// [intent] and [sources] are surfaced in the UI on purpose. An assistant that
/// answers about money should be able to say *how* it knows — which intent
/// matched and which rows it read — rather than presenting an opaque figure.
/// That traceability is also what makes the local engine trustworthy compared
/// with a model that would guess at arithmetic.
class AssistantReply {
  const AssistantReply({
    required this.text,
    required this.intent,
    this.sources = const <String>[],
  });

  final String text;

  /// Which handler ran, for example `category_total`.
  final String intent;

  /// Identifiers or labels the answer was computed from.
  final List<String> sources;
}
