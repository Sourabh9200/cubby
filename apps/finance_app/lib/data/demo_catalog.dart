import 'dart:math' as math;

/// Small deterministic PRNG for the demo dataset.
///
/// `dart:math`'s [math.Random] with a fixed seed would also work, but a
/// hand-rolled generator keeps the dataset identical across Dart versions, so
/// a chart looks the same every time the app restarts.
class DemoRng {
  DemoRng(this._state);

  int _state;

  int _advance() {
    _state = (_state * 1103515245 + 12345) & 0x7FFFFFFF;
    return _state;
  }

  /// Inclusive on both ends.
  int nextInt(int min, int max) => min + _advance() % (max - min + 1);

  double nextUnit() => _advance() / 0x7FFFFFFF;

  T pick<T>(List<T> items) => items[_advance() % items.length];
}

/// How many transactions a category tends to have per month, and roughly how
/// much it totals. Shapes the demo data into something that looks like a real
/// household rather than uniform noise.
class CategoryProfile {
  const CategoryProfile({
    required this.category,
    required this.payees,
    required this.txnsPerMonth,
    required this.monthlyRupees,
  });

  final String category;
  final List<String> payees;
  final int txnsPerMonth;
  final int monthlyRupees;
}

/// Accounts the demo ledger spreads across.
const List<String> demoAccounts = <String>[
  'HDFC Savings',
  'ICICI Credit Card',
  'Paytm Wallet',
];

/// Monthly spending profiles, in Indian rupees.
const List<CategoryProfile> demoProfiles = <CategoryProfile>[
  CategoryProfile(
    category: 'Rent',
    payees: <String>['Monthly rent transfer'],
    txnsPerMonth: 1,
    monthlyRupees: 18000,
  ),
  CategoryProfile(
    category: 'Groceries',
    payees: <String>[
      'BigBasket',
      'DMart',
      'Zepto',
      'Blinkit',
      'More Supermarket',
    ],
    txnsPerMonth: 7,
    monthlyRupees: 8200,
  ),
  CategoryProfile(
    category: 'Dining Out',
    payees: <String>['Swiggy', 'Zomato', 'Third Wave Coffee', 'Sagar Ratna'],
    txnsPerMonth: 9,
    monthlyRupees: 4600,
  ),
  CategoryProfile(
    category: 'Shopping',
    payees: <String>['Amazon', 'Flipkart', 'Myntra', 'Decathlon'],
    txnsPerMonth: 3,
    monthlyRupees: 4200,
  ),
  CategoryProfile(
    category: 'Transport',
    payees: <String>['Uber', 'Ola', 'Indian Oil', 'Namma Metro'],
    txnsPerMonth: 8,
    monthlyRupees: 2600,
  ),
  CategoryProfile(
    category: 'Utilities',
    payees: <String>['Airtel Postpaid', 'BESCOM', 'BWSSB'],
    txnsPerMonth: 3,
    monthlyRupees: 3100,
  ),
  CategoryProfile(
    category: 'Health',
    payees: <String>['Apollo Pharmacy', '1mg', 'Practo'],
    txnsPerMonth: 2,
    monthlyRupees: 1600,
  ),
  CategoryProfile(
    category: 'Entertainment',
    payees: <String>['Netflix', 'Spotify', 'PVR Cinemas'],
    txnsPerMonth: 3,
    monthlyRupees: 1400,
  ),
  CategoryProfile(
    category: 'Education',
    payees: <String>['Udemy', 'Coursera'],
    txnsPerMonth: 1,
    monthlyRupees: 1200,
  ),
  CategoryProfile(
    category: 'Misc',
    payees: <String>['Local kirana', 'ATM charges', 'Salon'],
    txnsPerMonth: 4,
    monthlyRupees: 1500,
  ),
];

/// Monthly investing profiles, in Indian rupees.
///
/// Separate from [demoProfiles] because a SIP is not jittered spending: it is
/// the same debit on the same day every month. Generating it with the random
/// jitter the expense profiles use would produce an investing trend that looks
/// like noise, which is the opposite of what a systematic investment plan is.
const List<CategoryProfile> demoInvestmentProfiles = <CategoryProfile>[
  CategoryProfile(
    category: 'Mutual Funds',
    payees: <String>['Parag Parikh Flexi Cap', 'Nifty 50 Index Fund'],
    txnsPerMonth: 1,
    monthlyRupees: 20000,
  ),
  CategoryProfile(
    category: 'Stocks',
    payees: <String>['Zerodha', 'Groww'],
    txnsPerMonth: 1,
    monthlyRupees: 8000,
  ),
];

/// Short month names, so the demo layer has no dependency on the formatting
/// layer and cannot drift from it.
const List<String> monthShortNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
