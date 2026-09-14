import '../../core/format/money.dart';
import '../../data/finance_snapshot.dart';
import '../../data/period_views.dart';
import '../../data/scheduled_views.dart';
import '../../data/snapshot_analytics.dart';
import '../../data/snapshot_views.dart';
import '../../data/stats_period.dart';
import 'assistant_reply.dart';
import 'intent_matcher.dart';

part 'local_engine_handlers.dart';
part 'local_engine_insight_handlers.dart';

/// A deterministic, fully offline question answerer.
///
/// This is the always-available fallback in the assistant design, and it is
/// also the honest default: it answers by aggregating local data, never by
/// predicting text. A language model asked to "add up" spending will produce
/// confident, wrong numbers. Here the arithmetic runs in Dart, so the figures
/// are exact and reproducible.
///
/// When a model is wired in later, its job is to choose one of these intents —
/// not to compute the result.
class LocalEngine {
  LocalEngine(this.snapshot);

  final FinanceSnapshot snapshot;

  /// Prompts offered to the user, chosen to map onto distinct intents so that
  /// tapping one never lands on the fallback.
  static const List<String> suggestions = <String>[
    'How much did I spend this month?',
    'Where is most of my money going?',
    'Am I over budget anywhere?',
    'What was my biggest expense?',
    'How does this compare to my average?',
    'What is my savings rate?',
    // The deeper Tier 1 answers, reachable by asking rather than by a card on a
    // screen: the assistant is where an opt-in figure belongs.
    'Will I stay within budget this month?',
    'What repeats every month?',
    'Which shops did I spend the most at?',
    'How does this month compare with last year?',
  ];

  /// Answers [question] from local data only.
  AssistantReply answer(String question) {
    final matched = IntentMatcher.match(question);
    return switch (matched.intent) {
      AssistantIntent.monthTotal => monthTotal(),
      AssistantIntent.categoryTotal => categoryTotal(matched.category),
      AssistantIntent.breakdown => breakdown(),
      AssistantIntent.budgetCheck => budgetCheck(),
      AssistantIntent.biggestExpense => biggestExpense(),
      AssistantIntent.comparison => comparison(),
      AssistantIntent.savingsRate => savingsRate(),
      AssistantIntent.forecast => forecast(),
      AssistantIntent.subscriptions => subscriptions(),
      AssistantIntent.payees => payees(),
      AssistantIntent.yearOverYear => yearOverYear(),
      AssistantIntent.fallback => fallback(),
    };
  }
}
