import 'package:flutter/material.dart';

/// Maps the stored icon keys to `IconData`.
///
/// The mapping is a switch over constants rather than `IconData(codePoint)`
/// built at runtime, because Flutter's release build tree-shakes the Material
/// icon font and rejects non-constant `IconData`. The database therefore stores
/// a key, and this is where it becomes an icon.
IconData categoryIconForKey(String? iconKey) => switch (iconKey) {
  'home' => Icons.home_rounded,
  'basket' => Icons.shopping_basket_rounded,
  'restaurant' => Icons.restaurant_rounded,
  'bag' => Icons.shopping_bag_rounded,
  'taxi' => Icons.local_taxi_rounded,
  'bolt' => Icons.bolt_rounded,
  'heart' => Icons.favorite_rounded,
  'movie' => Icons.movie_rounded,
  'school' => Icons.school_rounded,
  'more' => Icons.more_horiz_rounded,
  'income' => Icons.south_west_rounded,
  'investments' => Icons.trending_up_rounded,
  'fund' => Icons.savings_rounded,
  'stocks' => Icons.show_chart_rounded,
  'deposit' => Icons.account_balance_rounded,
  _ => Icons.category_rounded,
};

/// Icon for a category, by stored key when available and by name otherwise.
///
/// The name fallback keeps user-created categories rendering sensibly without
/// requiring them to pick an icon first.
IconData categoryIcon({String? iconKey, required String name}) {
  if (iconKey != null && iconKey.isNotEmpty) {
    return categoryIconForKey(iconKey);
  }
  return switch (name) {
    'Income' => Icons.south_west_rounded,
    'Rent' => Icons.home_rounded,
    'Groceries' => Icons.shopping_basket_rounded,
    'Dining Out' => Icons.restaurant_rounded,
    'Shopping' => Icons.shopping_bag_rounded,
    'Transport' => Icons.local_taxi_rounded,
    'Utilities' => Icons.bolt_rounded,
    'Health' => Icons.favorite_rounded,
    'Entertainment' => Icons.movie_rounded,
    'Education' => Icons.school_rounded,
    'Investments' => Icons.trending_up_rounded,
    'Mutual Funds' => Icons.savings_rounded,
    'Stocks' => Icons.show_chart_rounded,
    'Fixed Deposit' => Icons.account_balance_rounded,
    'Other' => Icons.category_rounded,
    _ => Icons.more_horiz_rounded,
  };
}
