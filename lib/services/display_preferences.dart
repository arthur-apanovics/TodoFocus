import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/enums.dart';

/// Persists UI display preferences — how data is presented, not how the app
/// behaves. Owns the goals-list sort order and list layout, plus the two
/// focus-surface layouts (in-app Focus tab and the home-screen widget). Each
/// layout is stored under its own key so the surfaces stay independent.
///
/// Uses the shared [app_settings] Hive box. Hive deduplicates open boxes by
/// name, so multiple services can open the same box without conflicts.
class DisplayPreferences extends ChangeNotifier {
  static const _boxName = 'app_settings';
  static const _sortOrderKey = 'goal_sort_order';
  static const _layoutKey = 'goal_list_layout';
  static const _focusScreenLayoutKey = 'focus_screen_layout';
  static const _focusWidgetLayoutKey = 'focus_widget_layout';

  final Box<String> _box;
  GoalSortOrder _sortOrder;
  GoalListLayout _layout;
  FocusLayout _focusScreenLayout;
  FocusLayout _focusWidgetLayout;

  DisplayPreferences._({
    required Box<String> box,
    required GoalSortOrder sortOrder,
    required GoalListLayout layout,
    required FocusLayout focusScreenLayout,
    required FocusLayout focusWidgetLayout,
  })  : _box = box,
        _sortOrder = sortOrder,
        _layout = layout,
        _focusScreenLayout = focusScreenLayout,
        _focusWidgetLayout = focusWidgetLayout;

  GoalSortOrder get sortOrder => _sortOrder;
  GoalListLayout get layout => _layout;

  /// Layout for the in-app Focus tab. Independent of [focusWidgetLayout].
  FocusLayout get focusScreenLayout => _focusScreenLayout;

  /// Layout for the home-screen widget. Independent of [focusScreenLayout].
  FocusLayout get focusWidgetLayout => _focusWidgetLayout;

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

  Future<void> setFocusScreenLayout(FocusLayout layout) async {
    _focusScreenLayout = layout;
    await _box.put(_focusScreenLayoutKey, layout.name);
    notifyListeners();
  }

  Future<void> setFocusWidgetLayout(FocusLayout layout) async {
    _focusWidgetLayout = layout;
    await _box.put(_focusWidgetLayoutKey, layout.name);
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

    FocusLayout readFocusLayout(String key, FocusLayout fallback) {
      final name = box.get(key);
      if (name == null) return fallback;
      return FocusLayout.values.firstWhere(
        (e) => e.name == name,
        orElse: () => fallback,
      );
    }

    return DisplayPreferences._(
      box: box,
      sortOrder: sortOrder,
      layout: layout,
      focusScreenLayout:
          readFocusLayout(_focusScreenLayoutKey, FocusLayout.currentPlus2),
      focusWidgetLayout:
          readFocusLayout(_focusWidgetLayoutKey, FocusLayout.current),
    );
  }
}
