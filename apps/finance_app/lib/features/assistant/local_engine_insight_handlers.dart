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

  /// Where this month is heading, with its basis stated (C5).
  AssistantReply forecast() {
    final range = snapshot.currentRange(StatsPeriod.month);
    final projection = snapshot.projectionFor(range);
    if (projection == null) {
      return const AssistantReply(
        text: 'This month is over, so there is nothing left to project.',
        intent: 'forecast',
      );
    }
    if (!projection.hasBasis) {
      // Not enough history is the honest answer, never an estimate (C5, C11).
      return const AssistantReply(
        text:
            'Not enough history to project this month yet. Record a few weeks '
            'and I can tell you where the month is heading — and what that '
            'leaves you per day.',
        intent: 'forecast',
      );
    }

    final limit = snapshot.budgetLimitIn(range);
    final verdict = limit == 0
        ? 'No limits are set for this month, so there is nothing to stay inside.'
        : projection.overshoots(limit)
        ? 'That is '
              '${Money.format(projection.projectedTotalMinor - limit, decimals: false)} '
              'past your ${Money.format(limit, decimals: false)} of limits.'
        : '${Money.format(projection.safePerDayMinor(limit))} a day for the '
              'remaining ${projection.daysRemaining} days keeps you inside your '
              '${Money.format(limit, decimals: false)} of limits.';
    final months = projection.monthsOfHistory;
    final rules = projection.ruleCount;
    final basis = months == 0
        ? 'no complete month of history yet, and $rules '
              '${rules == 1 ? 'rule' : 'rules'} still to post'
        : '$months ${months == 1 ? 'month' : 'months'} of history, '
              '${projection.recordedDays} recorded '
              '${projection.recordedDays == 1 ? 'day' : 'days'}, and $rules '
              '${rules == 1 ? 'rule' : 'rules'} still to post';

    return AssistantReply(
      text:
          'At this rate you land at '
          '${Money.format(projection.projectedTotalMinor, decimals: false)} this '
          'month: ${Money.format(projection.spentMinor, decimals: false)} spent '
          'so far, '
          '${Money.format(projection.committedMinor, decimals: false)} still to '
          'post, and about '
          '${Money.format(projection.projectedVariableMinor, decimals: false)} '
          'for the rest. $verdict\n\nA projection from what you have recorded, '
          'not a promise — based on $basis.',
      intent: 'forecast',
    );
  }

  /// What repeats, and what it costs over a year (Tier 1.3).
  AssistantReply subscriptions() {
    final items = snapshot.subscriptions;
    if (items.isEmpty) {
      return const AssistantReply(
        text:
            'Nothing repeats yet. Record an entry with Repeat switched on and I '
            'can total what it costs you in a year — a monthly figure hides the '
            'annual cost that makes a subscription worth cancelling.',
        intent: 'subscriptions',
      );
    }
    final lines = items
        .take(4)
        .map(
          (item) =>
              '${item.payee.isEmpty ? item.category : item.payee} — '
              '${Money.format(item.amountMinor, decimals: false)} a month, '
              '${Money.format(item.annualMinor, decimals: false)} a year',
        )
        .join('\n');
    final rest = items.length > 4 ? '\n\n…and ${items.length - 4} more.' : '';
    return AssistantReply(
      text:
          '${items.length} ${items.length == 1 ? 'thing repeats' : 'things repeat'}, '
          'costing '
          '${Money.format(snapshot.annualSubscriptionsMinor, decimals: false)} '
          'a year:\n\n$lines$rest',
      intent: 'subscriptions',
      sources: items.take(4).map((item) => item.category).toList(),
    );
  }

  /// Where the money went, by payee as recorded (Tier 0.4, and C8).
  AssistantReply payees() {
    final top = snapshot.topPayeesIn(
      snapshot.currentRange(StatsPeriod.year),
      limit: 4,
    );
    if (top.isEmpty) {
      return const AssistantReply(
        text: 'No spending with a payee recorded this year yet.',
        intent: 'payees',
      );
    }
    final lines = top
        .map(
          (payee) =>
              '${payee.payee} — '
              '${Money.format(payee.totalMinor, decimals: false)} across '
              '${payee.count} ${payee.count == 1 ? 'entry' : 'entries'}',
        )
        .join('\n');
    return AssistantReply(
      text: 'This year, most of your money went to:\n\n$lines',
      intent: 'payees',
      // The names exactly as recorded: nothing is merged (C8).
      sources: top.map((payee) => payee.payee).toList(),
    );
  }

  /// This month against the same month a year earlier (Tier 0.3).
  AssistantReply yearOverYear() {
    final range = snapshot.currentRange(StatsPeriod.month);
    final comparison = snapshot.yearOverYearFor(range);
    if (comparison == null) {
      return const AssistantReply(
        text:
            'I need the whole of the same month a year ago before I can compare. '
            'This ledger does not reach back that far yet, and comparing against '
            'part of a month would read as a change that never happened.',
        intent: 'year_over_year',
      );
    }
    final previous = DateTime(range.from.year - 1, range.from.month);
    String change(double? percent) => percent == null
        ? 'nothing to compare'
        : '${percent >= 0 ? 'up' : 'down'} '
              '${percent.abs().toStringAsFixed(0)}%';

    return AssistantReply(
      text:
          '${DateLabels.monthYear(range.from)} against the same days of '
          '${DateLabels.monthYear(previous)}: spending '
          '${change(comparison.expenseChangePercent)}, income '
          '${change(comparison.incomeChangePercent)}, investing '
          '${change(comparison.investmentChangePercent)}. Last year is scaled '
          'to the same point in the month, because a part-month against a whole '
          'one would read as a change every time.',
      intent: 'year_over_year',
    );
  }
}
