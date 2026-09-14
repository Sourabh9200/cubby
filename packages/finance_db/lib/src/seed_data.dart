import 'package:drift/drift.dart';

import 'database.dart';
import 'seed_keys.dart';
import 'tables.dart';

/// Current seed revision, so a later release can add categories without
/// duplicating the ones a user already has.
///
/// Version 2 added the investment categories. Bumping this is what makes an
/// existing install — which has no investment category, and therefore no way to
/// record an investment at all — gain them on the next open.
const int currentSeedVersion = 2;

/// The account a new install starts with.
const List<(String, String, AccountType, int)> _seedAccounts =
    <(String, String, AccountType, int)>[
      (SeedIds.accountCash, 'Cash', AccountType.cash, 0),
      (SeedIds.accountHdfc, 'HDFC Savings', AccountType.bank, 1),
      (
        SeedIds.accountCreditCard,
        'ICICI Credit Card',
        AccountType.creditCard,
        2,
      ),
    ];

/// Expense categories: id, name, icon key, colour key, monthly budget in rupees.
const List<(String, String, String, String, int)> _seedExpenseCategories =
    <(String, String, String, String, int)>[
      (
        SeedIds.categoryRent,
        'Rent',
        CategoryIcons.home,
        CategoryColors.indigo,
        18000,
      ),
      (
        SeedIds.categoryGroceries,
        'Groceries',
        CategoryIcons.basket,
        CategoryColors.emerald,
        9000,
      ),
      (
        SeedIds.categoryDining,
        'Dining Out',
        CategoryIcons.restaurant,
        CategoryColors.amber,
        5000,
      ),
      (
        SeedIds.categoryShopping,
        'Shopping',
        CategoryIcons.bag,
        CategoryColors.pink,
        6000,
      ),
      (
        SeedIds.categoryTransport,
        'Transport',
        CategoryIcons.taxi,
        CategoryColors.sky,
        3000,
      ),
      (
        SeedIds.categoryUtilities,
        'Utilities',
        CategoryIcons.bolt,
        CategoryColors.purple,
        3500,
      ),
      (
        SeedIds.categoryHealth,
        'Health',
        CategoryIcons.heart,
        CategoryColors.red,
        2500,
      ),
      (
        SeedIds.categoryEntertainment,
        'Entertainment',
        CategoryIcons.movie,
        CategoryColors.gold,
        2000,
      ),
      (
        SeedIds.categoryEducation,
        'Education',
        CategoryIcons.school,
        CategoryColors.teal,
        1500,
      ),
      (
        SeedIds.categoryMisc,
        'Misc',
        CategoryIcons.more,
        CategoryColors.violet,
        1500,
      ),
    ];

/// Investment categories: id, name, icon key, colour key, monthly target in rupees.
///
/// Seeded because "investment" is a third kind of money movement, and a user who
/// cannot find an investment category will record their SIP as an expense — which
/// quietly makes every spending total in the app wrong. The target on Mutual
/// Funds is a plain starting value the user can change; zero means "no target",
/// never "no investing".
const List<(String, String, String, String, int)> _seedInvestmentCategories =
    <(String, String, String, String, int)>[
      (
        SeedIds.categoryInvestments,
        'Investments',
        CategoryIcons.investments,
        CategoryColors.teal,
        0,
      ),
      (
        SeedIds.categoryMutualFunds,
        'Mutual Funds',
        CategoryIcons.fund,
        CategoryColors.violet,
        20000,
      ),
      (
        SeedIds.categoryStocks,
        'Stocks',
        CategoryIcons.stocks,
        CategoryColors.sky,
        0,
      ),
      (
        SeedIds.categoryDeposits,
        'Fixed Deposit',
        CategoryIcons.deposit,
        CategoryColors.gold,
        0,
      ),
    ];

/// Inserts the accounts, categories, and settings a new install starts with.
///
/// Called from `onCreate`, so it runs exactly once per database lifetime.
Future<void> seedDefaults(AppDatabase db) async {
  final now = DateTime.now();

  // One batch, so the whole seed is a single transaction and a failure part-way
  // through cannot leave a half-populated database.
  await db.batch(
    (Batch batch) => batch
      ..insertAll(db.accounts, <AccountsCompanion>[
        for (final (id, name, type, sortOrder) in _seedAccounts)
          AccountsCompanion.insert(
            id: id,
            name: name,
            type: type,
            currency: 'INR',
            sortOrder: Value<int>(sortOrder),
            createdAt: now,
            updatedAt: now,
          ),
      ])
      ..insertAll(db.categories, <CategoriesCompanion>[
        for (final (id, name, iconKey, colorKey, budgetRupees)
            in _seedExpenseCategories)
          _category(
            id: id,
            name: name,
            kind: CategoryKind.expense,
            iconKey: iconKey,
            colorKey: colorKey,
            budgetRupees: budgetRupees,
            sortOrder: _seedExpenseCategories.indexWhere((row) => row.$1 == id),
            now: now,
          ),
        for (final (id, name, iconKey, colorKey, budgetRupees)
            in _seedInvestmentCategories)
          _category(
            id: id,
            name: name,
            kind: CategoryKind.investment,
            iconKey: iconKey,
            colorKey: colorKey,
            budgetRupees: budgetRupees,
            sortOrder: _investmentSortOrder(id),
            now: now,
          ),
        CategoriesCompanion.insert(
          id: SeedIds.categoryIncome,
          name: 'Income',
          kind: CategoryKind.income,
          iconKey: CategoryIcons.income,
          colorKey: CategoryColors.emerald,
          isSystem: const Value<bool>(true),
          sortOrder: const Value<int>(100),
          createdAt: now,
          updatedAt: now,
        ),
      ]),
  );

  // Written together rather than awaited one at a time: these are three
  // independent inserts, and a cascade of awaits would be needlessly serial.
  await Future.wait<void>(<Future<void>>[
    db.writeSetting(SettingKeys.currency, 'INR'),
    db.writeSetting(SettingKeys.monthStartDay, '1'),
    db.writeSetting(SettingKeys.seedVersion, '$currentSeedVersion'),
  ]);
}

/// Adds any seed rows that a database created by an older version is missing.
///
/// Returns true when it ran, false when there was nothing to seed into.
///
/// Written to be idempotent rather than to run once: the insert uses
/// `INSERT OR IGNORE` against the tables' primary keys, so a row that already
/// exists is left exactly as it is. That matters because the user may have
/// renamed a seeded category or changed its budget, and a top-up that overwrote
/// those would silently undo their edits on every single launch — a bug that
/// only becomes visible once someone has real data they care about.
Future<bool> seedMissingDefaults(AppDatabase db) async {
  final existing = await db
      .customSelect('SELECT COUNT(*) AS categoryCount FROM categories')
      .getSingle();
  if (existing.read<int>('categoryCount') == 0) {
    // A database that has never been seeded gets the full seed from `onCreate`
    // instead; inserting a partial set here would produce a half-built install.
    return false;
  }

  final now = DateTime.now();
  await db.batch(
    (Batch batch) => batch.insertAll(db.categories, <CategoriesCompanion>[
      for (final (id, name, iconKey, colorKey, budgetRupees)
          in _seedInvestmentCategories)
        _category(
          id: id,
          name: name,
          kind: CategoryKind.investment,
          iconKey: iconKey,
          colorKey: colorKey,
          budgetRupees: budgetRupees,
          sortOrder: _investmentSortOrder(id),
          now: now,
        ),
    ], mode: InsertMode.insertOrIgnore),
  );
  return true;
}

/// Sort position for a seeded investment category.
///
/// Offset past the income category at 100, so the flat ordering the pickers read
/// stays expenses (0-9), then income, then investments.
int _investmentSortOrder(String id) =>
    110 + _seedInvestmentCategories.indexWhere((row) => row.$1 == id);

/// Builds one seeded category row.
CategoriesCompanion _category({
  required String id,
  required String name,
  required CategoryKind kind,
  required String iconKey,
  required String colorKey,
  required int budgetRupees,
  required int sortOrder,
  required DateTime now,
}) => CategoriesCompanion.insert(
  id: id,
  name: name,
  kind: kind,
  iconKey: iconKey,
  colorKey: colorKey,
  monthlyBudgetMinor: Value<int>(budgetRupees * 100),
  isSystem: const Value<bool>(true),
  sortOrder: Value<int>(sortOrder),
  createdAt: now,
  updatedAt: now,
);
