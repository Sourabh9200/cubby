/// Intent recognition for the assistant.
///
/// Kept separate from response generation because this is the one piece a
/// language model would eventually replace. Everything downstream — the SQL,
/// the arithmetic, the wording — stays deterministic either way. A model that
/// only has to pick an intent cannot hallucinate a total.
library;

/// What the user is asking for.
enum AssistantIntent {
  monthTotal,
  categoryTotal,
  breakdown,
  budgetCheck,
  biggestExpense,
  comparison,
  savingsRate,
  fallback,
}

/// An intent plus anything extracted from the question.
class MatchedIntent {
  const MatchedIntent(this.intent, {this.category});

  final AssistantIntent intent;

  /// Canonical category name, when the question named one.
  final String? category;
}

/// Maps a question to an [AssistantIntent] using keyword rules.
///
/// Order matters and is deliberate: a question can contain several trigger
/// words ("how much did I spend on groceries versus my average"), so the more
/// specific intents are tested before the general ones. Category-with-amount is
/// checked first because it is the most common shape of a real question.
class IntentMatcher {
  const IntentMatcher._();

  /// Category names the matcher recognises, longest first so that
  /// "entertainment" is not shadowed by a shorter overlapping name.
  static const List<String> knownCategories = <String>[
    'entertainment',
    'education',
    'groceries',
    'utilities',
    'transport',
    'shopping',
    'dining out',
    'dining',
    'health',
    'rent',
    'misc',
  ];

  static MatchedIntent match(String question) {
    final query = question.toLowerCase().trim();
    if (query.isEmpty) {
      return const MatchedIntent(AssistantIntent.fallback);
    }

    final category = extractCategory(query);

    if (category != null && _hasAny(query, _amountWords)) {
      return MatchedIntent(AssistantIntent.categoryTotal, category: category);
    }
    if (_hasAny(query, _budgetWords)) {
      return const MatchedIntent(AssistantIntent.budgetCheck);
    }
    if (_hasAny(query, _biggestWords)) {
      return const MatchedIntent(AssistantIntent.biggestExpense);
    }
    if (_hasAny(query, _comparisonWords)) {
      return const MatchedIntent(AssistantIntent.comparison);
    }
    if (_hasAny(query, _savingsWords)) {
      return const MatchedIntent(AssistantIntent.savingsRate);
    }
    if (_hasAny(query, _breakdownWords)) {
      return const MatchedIntent(AssistantIntent.breakdown);
    }
    if (_hasAny(query, _amountWords)) {
      return const MatchedIntent(AssistantIntent.monthTotal);
    }
    return MatchedIntent(AssistantIntent.fallback, category: category);
  }

  /// Finds a category name in the question, or null.
  static String? extractCategory(String query) {
    for (final name in knownCategories) {
      if (query.contains(name)) {
        return canonicalCategory(name);
      }
    }
    return null;
  }

  /// Maps a loose match to the canonical display name.
  static String canonicalCategory(String match) => switch (match) {
    'dining' || 'dining out' => 'Dining Out',
    _ => match[0].toUpperCase() + match.substring(1),
  };

  static const List<String> _amountWords = <String>[
    'how much',
    'spend',
    'spent',
    'spending',
  ];

  static const List<String> _budgetWords = <String>[
    'over budget',
    'budget',
    'overspend',
    'limit',
  ];

  static const List<String> _biggestWords = <String>[
    'biggest',
    'largest',
    'most expensive',
    'top',
  ];

  static const List<String> _comparisonWords = <String>[
    'average',
    'usual',
    'normal',
    'compare',
    'versus',
  ];

  static const List<String> _savingsWords = <String>[
    'saving',
    'savings rate',
    'kept',
  ];

  static const List<String> _breakdownWords = <String>[
    'where',
    'going',
    'breakdown',
    'split',
    'category',
    'categories',
  ];

  static bool _hasAny(String haystack, List<String> needles) =>
      needles.any(haystack.contains);
}
