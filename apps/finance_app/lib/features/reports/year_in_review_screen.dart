import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/indicators.dart';
import '../../core/widgets/section_card.dart';
import '../../data/repository_scope.dart';
import '../../data/snapshot_analytics.dart';
import '../../data/year_in_review.dart';
import '../trends/payee_detail_screen.dart';
import 'widgets/figure_row.dart';

/// A year told as a handful of statements.
///
/// The last item of the plan, and almost entirely presentation: every figure
/// comes from `SnapshotAnalytics.yearInReview`, which is itself built out of the
/// methods the other screens already use. What this adds is the reading — a year
/// is not a table, and "you paid the coffee shop 47 times" is the kind of line
/// someone repeats, where a bar chart of the same fact is not.
class YearInReviewScreen extends StatefulWidget {
  const YearInReviewScreen({required this.year, super.key});

  /// The year to review, in progress or complete.
  final int year;

  @override
  State<YearInReviewScreen> createState() => _YearInReviewScreenState();
}

class _YearInReviewScreenState extends State<YearInReviewScreen> {
  late int _year = widget.year;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = MoneyColors.of(context);
    final snapshot = RepositoryScope.of(context);
    final review = snapshot.yearInReview(_year);
    final first = snapshot.firstRecordedDay;
    final canGoBack = first != null && first.year < _year;
    final canGoForward = _year < snapshot.now.year;

    // The two payee facts get their own rows only when they name different
    // payees. Repeating one name under two headings with the same total would
    // read as a bug in a screen whose whole job is to be believable.
    final frequent = review.frequentPayee;
    final showFrequent =
        frequent != null && frequent.payee != review.largestPayee?.payee;

    return Scaffold(
      appBar: AppBar(
        title: Text('$_year in review'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Previous year',
            onPressed: canGoBack ? () => setState(() => _year--) : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Next year',
            onPressed: canGoForward ? () => setState(() => _year++) : null,
          ),
        ],
      ),
      body: review.isEmpty
          ? EmptyState(
              icon: Icons.event_note_rounded,
              title: 'Nothing recorded in $_year',
              message:
                  'A year in review is written from the entries themselves. '
                  'There are none in $_year, so there is no year to describe.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: <Widget>[
                SectionCard(
                  title: 'The year in one breath',
                  trailing: Pill(
                    text: review.isComplete ? 'complete' : 'so far',
                    color: theme.colorScheme.primary,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _headline(review),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _supporting(review),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SectionCard(
                  title: 'What stood out',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (review.biggestMonth case final peak?)
                        FigureRow(
                          label: 'Biggest month',
                          value: Money.format(peak.totalMinor, decimals: false),
                          color: money.expense,
                          detail:
                              '${DateLabels.monthYear(peak.month)} · '
                              '${_share(peak.totalMinor, review.totals.expenseMinor)} '
                              'of the year',
                        ),
                      if (review.topCategory case final spend?)
                        FigureRow(
                          label: 'Where most of it went',
                          value: Money.format(
                            spend.totalMinor,
                            decimals: false,
                          ),
                          detail:
                              '${spend.category} · '
                              '${_share(spend.totalMinor, review.totals.expenseMinor)} '
                              'of spending in ${_entryCount(spend.txnCount)}',
                        ),
                      if (review.largestPayee case final payee?)
                        FigureRow(
                          label: 'Paid the most',
                          value: Money.format(
                            payee.totalMinor,
                            decimals: false,
                          ),
                          detail:
                              '${payee.payee} · ${_entryCount(payee.count)} at '
                              'an average of '
                              '${Money.format(payee.averageMinor, decimals: false)}',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  PayeeDetailScreen(payee: payee.payee),
                            ),
                          ),
                        ),
                      if (showFrequent)
                        FigureRow(
                          label: 'Paid most often',
                          value: '${frequent.count} entries',
                          detail:
                              '${frequent.payee} · '
                              '${Money.format(frequent.totalMinor, decimals: false)} '
                              'in total',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  PayeeDetailScreen(payee: frequent.payee),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SectionCard(
                  title: 'What you kept',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      FigureRow(
                        label: 'Savings rate',
                        value: review.totals.savingsRate == null
                            ? '—'
                            : '${review.totals.savingsRate!.toStringAsFixed(0)}%',
                        color: money.income,
                        detail: review.totals.savingsRate == null
                            ? 'Nothing came in this year, so there is no rate to '
                                  'read: a rate needs income to be a rate of'
                            : 'Of the '
                                  '${Money.format(review.totals.incomeMinor, decimals: false)} '
                                  'that came in, after spending — money invested '
                                  'counts as kept, because it is still yours',
                      ),
                      FigureRow(
                        label: 'Routed into investments',
                        value: review.totals.investmentRate == null
                            ? '—'
                            : '${review.totals.investmentRate!.toStringAsFixed(0)}%',
                        color: money.investment,
                        detail:
                            '${Money.format(review.totals.investmentMinor, decimals: false)} '
                            'moved into assets, which is not spending and is not '
                            'income either',
                      ),
                      FigureRow(
                        label: 'Left in cash',
                        value: Money.format(
                          review.totals.cashLeftMinor,
                          decimals: false,
                        ),
                        color: review.totals.cashLeftMinor < 0
                            ? money.expense
                            : null,
                        detail:
                            'What is left of income once spending and investing '
                            'are both taken out',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SectionCard(
                  title: 'Against your limits',
                  child: review.hasLimitRecord
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            FigureRow(
                              label: 'Months inside their limits',
                              value: review.stayedInsideEveryMonth
                                  ? 'all ${review.monthsComparedToLimits}'
                                  : '${review.monthsInsideLimits} of '
                                        '${review.monthsComparedToLimits}',
                              color: review.stayedInsideEveryMonth
                                  ? money.income
                                  : null,
                              detail: review.stayedInsideEveryMonth
                                  ? 'Every month with a limit set stayed inside '
                                        'it — judged against today\'s limits, '
                                        'because the app keeps no budget history'
                                  : 'A month counts when it had spending and at '
                                        'least one limit to measure against',
                            ),
                            FigureRow(
                              label: 'On repeating rules now',
                              value:
                                  '${Money.format(review.committedMonthlyMinor, decimals: false)}/month',
                              detail:
                                  'A figure about today, carried here because it '
                                  'is what this year set up — not something the '
                                  'year recorded',
                            ),
                          ],
                        )
                      : const EmptyState(
                          dense: true,
                          icon: Icons.savings_outlined,
                          title: 'No limits to measure against',
                          message:
                              'A year of limits appears here once a monthly '
                              'limit is set on a category. Months are judged '
                              'against today\'s limits, because the app does not '
                              'keep a budget history.',
                        ),
                ),
                const SizedBox(height: 14),
                SectionCard(
                  title: 'Against last year',
                  child: review.change == null
                      ? const EmptyState(
                          dense: true,
                          icon: Icons.history_rounded,
                          title: 'Not enough history',
                          message:
                              'Comparing years needs the whole of the year '
                              'before this one. This ledger does not reach back '
                              'that far yet — the comparison appears when it '
                              'does.',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            FigureRow(
                              label: 'Spent',
                              value: Money.format(
                                review.totals.expenseMinor,
                                decimals: false,
                              ),
                              color: money.expense,
                              detail: _against(
                                review.change!.expenseChangePercent,
                                review.change!.comparableExpenseMinor,
                              ),
                            ),
                            FigureRow(
                              label: 'Received',
                              value: Money.format(
                                review.totals.incomeMinor,
                                decimals: false,
                              ),
                              color: money.income,
                              detail: _against(
                                review.change!.incomeChangePercent,
                                review.change!.comparableIncomeMinor,
                              ),
                            ),
                            FigureRow(
                              label: 'Invested',
                              value: Money.format(
                                review.totals.investmentMinor,
                                decimals: false,
                              ),
                              color: money.investment,
                              detail: _against(
                                review.change!.investmentChangePercent,
                                review.change!.comparableInvestmentMinor,
                              ),
                            ),
                            if (!review.isComplete)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'This year is still running, so last year is '
                                  'scaled to the same point in it before '
                                  'comparing. Against a whole year, every one '
                                  'of these would read as a saving.',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Payees are matched exactly as they were typed, never merged, '
                  'so a rent recorded as "Rent" and "Rent - Jul" counts as two '
                  'payees here. Categories are the ones the entries carry, so '
                  'this review says the same things the ledger would.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }

  /// The year in one sentence, in the tense it deserves.
  String _headline(YearInReview review) {
    final spent = Money.format(review.totals.expenseMinor, decimals: false);
    final entries = _entryCount(review.entries);
    final months = review.monthsRecorded == 1
        ? 'one month of entries'
        : '${review.monthsRecorded} months of entries';
    return review.isComplete
        ? 'In ${review.year} you spent $spent across $entries, over $months.'
        : 'So far in ${review.year} you have spent $spent across $entries, over '
              '$months.';
  }

  /// What came in, and what the rates are rates of — or why there is none.
  String _supporting(YearInReview review) {
    final income = Money.format(review.totals.incomeMinor, decimals: false);
    final rate = review.totals.savingsRate;
    if (rate == null) {
      return '$income is what the ledger recorded coming in, so there is no '
          'savings rate to read: a rate needs income to be a rate of.';
    }
    return '$income came in, so you kept ${rate.toStringAsFixed(0)}% of it. The '
        'rest either went out or moved into investments.';
  }

  /// A share of a total, as a whole percentage.
  String _share(int part, int whole) =>
      whole == 0 ? '0%' : '${(part / whole * 100).toStringAsFixed(0)}%';

  String _entryCount(int count) => count == 1 ? '1 entry' : '$count entries';

  /// "12% more than last year · ₹73,000 then", or why nothing compares.
  ///
  /// The earlier figure is stated alongside the change because a percentage on
  /// its own hides the size of what it is a percentage of: 12% more than a small
  /// year is still a small year.
  String _against(double? percent, int comparableMinor) {
    if (percent == null) {
      return 'Nothing recorded in the same span last year to compare with';
    }
    final magnitude = percent.abs();
    final rounded = magnitude < 10
        ? magnitude.toStringAsFixed(1)
        : magnitude.toStringAsFixed(0);
    return '$rounded% ${percent >= 0 ? 'more' : 'less'} than last year · '
        '${Money.format(comparableMinor, decimals: false)} then';
  }
}
