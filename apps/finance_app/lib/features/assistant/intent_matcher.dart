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

  /// Where the period is heading, and what that leaves per day (Tier 1.1–1.2).
  forecast,

  /// What repeats, and what it costs over a year (Tier 1.3).
  subscriptions,

  /// The places the money went, as recorded (Tier 0.4).
  payees,

  /// This month against the same month a year earlier (Tier 0.3).
  yearOverYear,
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
    // Most specific first. A comparison with a year ago, what repeats, and the
    // places money went all contain words the broader intents also match
    // ("top places" contains "top"), so they are tested before those.
    if (_hasAny(query, _yearAgoWords)) {
      return const MatchedIntent(AssistantIntent.yearOverYear);
    }
    if (_hasAny(query, _subscriptionWords)) {
      return const MatchedIntent(AssistantIntent.subscriptions);
    }
    if (_hasAny(query, _payeeWords)) {
      return const MatchedIntent(AssistantIntent.payees);
    }
    // Ahead of the budget check on purpose: "will I be over budget this month"
    // is a question about the projection, not about where the month stands now.
    if (_hasAny(query, _forecastWords)) {
      return const MatchedIntent(AssistantIntent.forecast);
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

  /// Where the period is heading. "Will I" is here rather than under the budget
  /// check because the question it introduces is always about what is coming.
  static const List<String> _forecastWords = <String>[
    'on track',
    'forecast',
    'projection',
    'projected',
    'end up',
    'will i',
    'heading',
    'safe to spend',
  ];

  /// What repeats, and what it costs a year.
  static const List<String> _subscriptionWords = <String>[
    'subscription',
    'recurring',
    'repeats',
    'repeat',
    'committed',
    'annualised',
    'every month',
  ];

  /// The places money went. Words rather than "where", which belongs to the
  /// breakdown question, and checked before "top", which belongs to the biggest
  /// expense.
  static const List<String> _payeeWords = <String>[
    'payee',
    'payees',
    'merchant',
    'merchants',
    'shop',
    'shops',
    'store',
    'places',
  ];

  /// The same month a year earlier.
  static const List<String> _yearAgoWords = <String>[
    'last year',
    'year over year',
    'year on year',
    'a year ago',
    'same month last',
  ];

  static bool _hasAny(String haystack, List<String> needles) =>
      needles.any(haystack.contains);
}
