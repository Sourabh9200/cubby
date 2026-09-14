import 'finance_snapshot.dart';
import 'models.dart';
import 'subscription.dart';
import 'upcoming_due.dart';

/// What the recurring rules say is coming.
///
/// A rule describes a habit — money that left the account on this day before and
/// is expected to again — so every figure here means *scheduled*. A rule is not
/// an obligation and not a guarantee, and the wording throughout says so (C14).
/// A stopped rule leaves these sums immediately, because the snapshot carries
/// only live rows.
extension ScheduledViews on FinanceSnapshot {
  /// Rules that post spending every month.
  List<RecurringRule> get scheduledExpenseRules =>
      _rulesOf(TxDirection.expense);

  /// How much of an average month recurring expenses already account for.
  ///
  /// This is the figure that answers "how much of this month is already spoken
  /// for" — and it is deliberately only the spending rules.
  int get committedMonthlyMinor => _sumAmounts(scheduledExpenseRules);

  /// How much of an average month goes into investments by rule.
  ///
  /// Kept apart from [committedMonthlyMinor] rather than added to it: a SIP is
  /// not consumption, and one combined figure would overstate spending by the
  /// size of every contribution (C1).
  int get committedInvestmentMinor =>
      _sumAmounts(_rulesOf(TxDirection.investment));

  /// How much income recurring rules post in an average month.
  ///
  /// A habit, never a promise: a salary rule repeats because it has happened
  /// before (C14).
  int get committedIncomeMinor => _sumAmounts(_rulesOf(TxDirection.income));

  /// Live expense rules as subscriptions, biggest annual cost first.
  ///
  /// The annual figure is the reason this list exists, so it is the order too: a
  /// user deciding what to cancel wants the ₹18,000-a-year line above the
  /// ₹1,000-a-year one, not whichever happens to be due soonest.
  List<Subscription> get subscriptions {
    final list = _rulesOf(TxDirection.expense)
        .map(
          (rule) => Subscription(
            ruleId: rule.id,
            category: rule.category,
            payee: rule.payee,
            amountMinor: rule.amountMinor,
            direction: rule.direction,
            nextDueOn: rule.nextDueOn,
          ),
        )
        .toList();
    list.sort((a, b) {
      final byAnnual = b.annualMinor.compareTo(a.annualMinor);
      // Ties broken by name so the order is deterministic rather than whatever
      // order the rule query happened to return.
      return byAnnual != 0 ? byAnnual : a.category.compareTo(b.category);
    });
    return list;
  }

  /// What every recurring expense costs over a year, across all rules.
  int get annualSubscriptionsMinor =>
      subscriptions.fold(0, (total, item) => total + item.annualMinor);

  /// Every live rule due within the next [days] days, soonest first.
  ///
  /// Today counts, because a rule that falls due today has not posted yet. Rules
  /// are materialised on open (`DatabaseOpener`), so a live rule's due date is
  /// never in the past — the window therefore has no lower anomaly to report.
  List<UpcomingDue> upcomingDues({int days = 30}) {
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day + days);
    final dues = <UpcomingDue>[];
    for (final rule in recurringRules) {
      final due = rule.nextDueOn;
      if (due.isBefore(today) || !due.isBefore(end)) {
        continue;
      }
      dues.add(
        UpcomingDue(
          ruleId: rule.id,
          payee: rule.payee,
          category: rule.category,
          amountMinor: rule.amountMinor,
          dueOn: due,
          direction: rule.direction,
        ),
      );
    }
    dues.sort((a, b) {
      final byDate = a.dueOn.compareTo(b.dueOn);
      // Ties broken by category so the order is deterministic rather than
      // whatever order the rule query happened to return.
      return byDate != 0 ? byDate : a.category.compareTo(b.category);
    });
    return dues;
  }

  /// Every live rule that posts in [direction].
  List<RecurringRule> _rulesOf(TxDirection direction) => recurringRules
      .where((rule) => rule.direction == direction)
      .toList(growable: false);

  /// Sums the amounts of [rules].
  static int _sumAmounts(List<RecurringRule> rules) {
    var total = 0;
    for (final rule in rules) {
      total += rule.amountMinor;
    }
    return total;
  }
}
