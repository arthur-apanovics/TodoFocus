import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/enums.dart';

/// Persists UI display preferences — how data is presented, not how the app
/// behaves. Currently owns the goals-list sort order and list layout; extend
/// here as other screens grow their own view preferences.
///
/// Uses the shared [app_settings] Hive box. Hive deduplicates open boxes by
/// name, so multiple services can open the same box without conflicts.
class DisplayPreferences extends ChangeNotifier {
  static const _boxName = 'app_settings';
  static const _sortOrderKey = 'goal_sort_order';
  static const _layoutKey = 'goal_list_layout';

  final Box<String> _box;
  GoalSortOrder _sortOrder;
  GoalListLayout _layout;

  DisplayPreferences._({
    required Box<String> box,
    required GoalSortOrder sortOrder,
    required GoalListLayout layout,
  })  : _box = box,
        _sortOrder = sortOrder,
        _layout = layout;

  GoalSortOrder get sortOrder => _sortOrder;
  GoalListLayout get layout => _layout;

  Future<void> setSortOrder(GoalSortOrder order) async {
    _sortOrder = order;
    await _box.put(_sortOrderKey, order.name);
    notifyListeners();
  }

  Future<void> setLayout(GoalListLayout layout) async {
    _layout = layout;
    await _box.put(_layoutKey, layout.name);
    notifyListeners();
  }

  static Future<DisplayPreferences> init() async {
    final box = await Hive.openBox<String>(_boxName);

    final sortOrderName = box.get(_sortOrderKey);
    final sortOrder = sortOrderName != null
        ? GoalSortOrder.values.firstWhere(
            (e) => e.name == sortOrderName,
            orElse: () => GoalSortOrder.smart,
          )
        : GoalSortOrder.smart;

    final layoutName = box.get(_layoutKey);
    final layout = layoutName != null
        ? GoalListLayout.values.firstWhere(
            (e) => e.name == layoutName,
            orElse: () => GoalListLayout.compact,
          )
        : GoalListLayout.compact;

    return DisplayPreferences._(
      box: box,
      sortOrder: sortOrder,
      layout: layout,
    );
  }
}
