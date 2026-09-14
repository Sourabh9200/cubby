part of 'local_engine.dart';

/// One handler per intent.
///
/// In a part file so the handlers stay private to the engine while the file
/// stays short enough to read in one sitting. Each handler returns exact figures
/// computed from local aggregates.
extension LocalEngineHandlers on LocalEngine {
  AssistantReply monthTotal() {
    final month = snapshot.currentMonth;
    final delta = snapshot.expenseChangePercent;
    final trailing = delta == null
        ? ''
        : ' That is ${delta.abs().toStringAsFixed(1)}% '
              '${delta > 0 ? 'ahead of' : 'behind'} your pace last month.';
    return AssistantReply(
      text:
          'You have spent ${Money.format(month.expenseMinor, decimals: false)} '
          'this month across ${month.byCategory.length} categories.$trailing',
      intent: 'month_total',
    );
  }

  AssistantReply categoryTotal(String? category) {
    if (category == null) {
      return breakdown();
    }
    final spends = snapshot.spendByCategory(snapshot.currentMonth.month);
    final match = spends.where((spend) => spend.category == category).toList();
    if (match.isEmpty) {
      return AssistantReply(
        text: 'Nothing recorded under $category this month.',
        intent: 'category_total',
      );
    }
    final spend = match.first;
    final total = spends.fold(0, (sum, item) => sum + item.totalMinor);
    return AssistantReply(
      text:
          '${Money.format(spend.totalMinor, decimals: false)} on $category this '
          'month, across ${spend.txnCount} transactions — '
          '${spend.shareOf(total).toStringAsFixed(0)}% of your total spend.',
      intent: 'category_total',
      sources: <String>[category],
    );
  }

  AssistantReply breakdown() {
    final spends = snapshot.spendByCategory(snapshot.currentMonth.month);
    if (spends.isEmpty) {
      return const AssistantReply(
        text: 'No spending recorded this month yet.',
        intent: 'breakdown',
      );
    }
    final total = spends.fold(0, (sum, item) => sum + item.totalMinor);
    final lines = spends
        .take(4)
        .map(
          (spend) =>
              '${spend.category} — '
              '${Money.format(spend.totalMinor, decimals: false)} '
              '(${spend.shareOf(total).toStringAsFixed(0)}%)',
        )
        .join('\n');
    return AssistantReply(
      text: 'Where it went this month:\n\n$lines',
      intent: 'breakdown',
      sources: spends.take(4).map((spend) => spend.category).toList(),
    );
  }

  AssistantReply fallback() => const AssistantReply(
    text:
        'I can answer questions about totals, categories, budgets, trends, and '
        'your savings rate. I read only your own local data, and this engine '
        'sends nothing anywhere.',
    intent: 'fallback',
  );
}
