import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SortOption { releaseNewest, releaseOldest, ratingHighToLow, aToZ, zToA }

extension SortOptionLabel on SortOption {
  String get label => switch (this) {
        SortOption.releaseNewest => 'Release Date (Newest)',
        SortOption.releaseOldest => 'Release Date (Oldest)',
        SortOption.ratingHighToLow => 'Critic Rating',
        SortOption.aToZ => 'A-Z',
        SortOption.zToA => 'Z-A',
      };

  String get jellyfinSortBy => switch (this) {
        SortOption.releaseNewest || SortOption.releaseOldest => 'PremiereDate,SortName',
        SortOption.ratingHighToLow => 'CommunityRating,SortName',
        SortOption.aToZ || SortOption.zToA => 'SortName',
      };

  String get jellyfinSortOrder => switch (this) {
        SortOption.releaseNewest || SortOption.ratingHighToLow || SortOption.zToA => 'Descending',
        SortOption.releaseOldest || SortOption.aToZ => 'Ascending',
      };
}

class AccentColorOption {
  const AccentColorOption(this.name, this.color);
  final String name;
  final Color color;
}

const accentColorOptions = [
  AccentColorOption('Crimson', Color(0xFFE53935)),
  AccentColorOption('Azure', Color(0xFF2196F3)),
  AccentColorOption('Emerald', Color(0xFF2E7D32)),
  AccentColorOption('Violet', Color(0xFF8E24AA)),
  AccentColorOption('Amber', Color(0xFFFF9800)),
  AccentColorOption('Teal', Color(0xFF00897B)),
  AccentColorOption('Rose', Color(0xFFEC407A)),
  AccentColorOption('Silver', Color(0xFFB0BEC5)),
];

class SettingsController extends ChangeNotifier {
  static const _accentColorKey = 'settings.accentColor';
  static const _categorySortPrefix = 'settings.sort.';

  Color _accentColor = accentColorOptions.first.color;
  Color get accentColor => _accentColor;

  final Map<String, SortOption> _categorySort = {};

  SortOption sortFor(String categoryId) => _categorySort[categoryId] ?? SortOption.releaseNewest;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final storedColor = prefs.getInt(_accentColorKey);
    if (storedColor != null) _accentColor = Color(storedColor);
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_categorySortPrefix)) continue;
      final id = key.substring(_categorySortPrefix.length);
      final value = prefs.getString(key);
      final match = SortOption.values.where((o) => o.name == value);
      if (match.isNotEmpty) _categorySort[id] = match.first;
    }
    notifyListeners();
  }

  Future<void> setAccentColor(Color color) async {
    _accentColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_accentColorKey, color.toARGB32());
  }

  Future<void> setSortFor(String categoryId, SortOption option) async {
    _categorySort[categoryId] = option;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_categorySortPrefix$categoryId', option.name);
  }
}
