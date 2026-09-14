/// Stable string keys used by the seed set and by settings lookups.
///
/// Strings rather than code points, so Flutter's release icon tree-shaking
/// keeps working: a runtime-constructed `IconData` disables it and non-constant
/// `IconData` is rejected outright in release builds.
library;

/// Icon lookup keys, resolved to constant `IconData` in the app.
abstract final class CategoryIcons {
  static const String home = 'home';
  static const String basket = 'basket';
  static const String restaurant = 'restaurant';
  static const String bag = 'bag';
  static const String taxi = 'taxi';
  static const String bolt = 'bolt';
  static const String heart = 'heart';
  static const String movie = 'movie';
  static const String school = 'school';
  static const String more = 'more';
  static const String income = 'income';
  static const String investments = 'investments';
  static const String fund = 'fund';
  static const String stocks = 'stocks';
  static const String deposit = 'deposit';
}

/// Palette slot keys, resolved against the app's category palette.
abstract final class CategoryColors {
  static const String indigo = 'indigo';
  static const String amber = 'amber';
  static const String emerald = 'emerald';
  static const String pink = 'pink';
  static const String sky = 'sky';
  static const String purple = 'purple';
  static const String gold = 'gold';
  static const String red = 'red';
  static const String teal = 'teal';
  static const String violet = 'violet';
}

/// Identifiers for seeded rows.
///
/// Deliberately readable slugs rather than UUIDs: seeding stays idempotent and
/// a test can name a row directly. Rows the *user* creates get real UUIDs,
/// where collision-resistance is the property that matters.
abstract final class SeedIds {
  static const String accountCash = 'seed-acc-cash';
  static const String accountHdfc = 'seed-acc-hdfc-savings';
  static const String accountCreditCard = 'seed-acc-icici-card';

  static const String categoryRent = 'seed-cat-rent';
  static const String categoryGroceries = 'seed-cat-groceries';
  static const String categoryDining = 'seed-cat-dining';
  static const String categoryShopping = 'seed-cat-shopping';
  static const String categoryTransport = 'seed-cat-transport';
  static const String categoryUtilities = 'seed-cat-utilities';
  static const String categoryHealth = 'seed-cat-health';
  static const String categoryEntertainment = 'seed-cat-entertainment';
  static const String categoryEducation = 'seed-cat-education';
  static const String categoryMisc = 'seed-cat-misc';
  static const String categoryIncome = 'seed-cat-income';

  static const String categoryInvestments = 'seed-cat-investments';
  static const String categoryMutualFunds = 'seed-cat-mutual-funds';
  static const String categoryStocks = 'seed-cat-stocks';
  static const String categoryDeposits = 'seed-cat-deposits';
}

/// Settings keys.
abstract final class SettingKeys {
  static const String currency = 'currency';
  static const String monthStartDay = 'month_start_day';
  static const String seedVersion = 'seed_version';
}
