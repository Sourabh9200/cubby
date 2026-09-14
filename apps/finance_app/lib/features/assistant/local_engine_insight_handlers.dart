part of 'local_engine.dart';

/// Handlers that compare one thing against another: budgets against limits,
/// categories against their own history, this month against the last.
extension LocalEngineInsightHandlers on LocalEngine {
  AssistantReply budgetCheck() {
    final statuses = snapshot.budgetStatuses();
    final over = statuses.where((status) => status.isOver).toList();
    if (over.isEmpty) {
      final closest = statuses.first;
      return AssistantReply(
        text:
            'You are inside every budget. Closest is ${closest.category} at '
            '${(closest.fraction * 100).toStringAsFixed(0)}% used.',
        intent: 'budget_check',
        sources: <String>[closest.category],
      );
    }
    final lines = over
        .map(
          (status) =>
              '${status.category} — over by '
              '${Money.format(status.remainingMinor.abs(), decimals: false)}',
        )
        .join('\n');
    return AssistantReply(
      text:
          'You are over budget in ${over.length} '
          '${over.length == 1 ? 'category' : 'categories'}:\n\n$lines',
      intent: 'budget_check',
      sources: over.map((status) => status.category).toList(),
    );
  }

  AssistantReply biggestExpense() {
    final top = snapshot.topExpenses(limit: 1);
    if (top.isEmpty) {
      return const AssistantReply(
        text: 'No expenses recorded this month.',
        intent: 'biggest_expense',
      );
    }
    final txn = top.first;
    final spends = snapshot.spendByCategory(snapshot.currentMonth.month);
    final total = spends.fold(0, (sum, item) => sum + item.totalMinor);
    final share = total == 0 ? 0.0 : txn.amountMinor / total * 100;
    return AssistantReply(
      text:
          'Your largest expense was ${Money.format(txn.amountMinor)} to '
          '${txn.payee} on ${DateLabels.dayMonth(txn.date)} — '
          '${share.toStringAsFixed(0)}% of the month on its own.',
      intent: 'biggest_expense',
      sources: <String>[txn.payee],
    );
  }

  AssistantReply comparison() {
    final rising = snapshot
        .categoryMovement(snapshot.currentMonth.month)
        .where(
          (movement) => !movement.isFlat && (movement.deltaPercent ?? 0) > 0,
        )
        .toList();
    if (rising.isEmpty) {
      return const AssistantReply(
        text:
            'Nothing is running meaningfully above your own average — '
            'everything is within about 5% of normal.',
        intent: 'comparison',
      );
    }
    final lines = rising
        .take(3)
        .map(
          (movement) =>
              '${movement.category} is '
              '${movement.deltaPercent!.toStringAsFixed(0)}% above normal '
              '(${Money.format(movement.currentMinor, decimals: false)} vs '
              '${Money.format(movement.averageMinor, decimals: false)} average)',
        )
        .join('\n');
    return AssistantReply(
      text: 'Against your own monthly average:\n\n$lines',
      intent: 'comparison',
      sources: rising.take(3).map((movement) => movement.category).toList(),
    );
  }

  AssistantReply savingsRate() {
    final rates = snapshot.monthlySummaries
        .map((summary) => summary.savingsRate)
        .whereType<double>()
        .toList();
    if (rates.isEmpty) {
      return const AssistantReply(
        text: 'Not enough history to work out a savings rate yet.',
        intent: 'savings_rate',
      );
    }
    final average = rates.reduce((a, b) => a + b) / rates.length;
    return AssistantReply(
      text:
          'You kept ${rates.last.toStringAsFixed(1)}% of your income this '
          'month. Across ${rates.length} months your average is '
          '${average.toStringAsFixed(1)}%.',
      intent: 'savings_rate',
    );
  }
}
