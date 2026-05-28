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
  static const _focusWidgetShowAllGoalsKey = 'focus_widget_show_all_goals';
  static const _showTimeEstimatesKey = 'show_time_estimates';
  static const _nudgesEnabledKey = 'nudges_enabled';
  static const _nudgeHeartbeatMinutesKey = 'nudge_heartbeat_minutes';
  static const _rewordPromptTemplateKey = 'reword_prompt_template';

  /// Default style-guide fragment for the inactivity reword feature.
  /// Editable in Settings → AI Assistant → Generation → Reword prompt.
  /// The fixed JSON-format instruction is appended automatically at request
  /// time — the user only controls tone and style here.
  static const defaultRewordPromptTemplate =
      'You rephrase task steps to make them more compelling and immediate. '
      'Keep the same core action but change the wording to be more enticing '
      'and easier to start. '
      'Do not add emojis, punctuation flair, or motivational clichés.';

  final Box<String> _box;
  GoalSortOrder _sortOrder;
  GoalListLayout _layout;
  FocusLayout _focusScreenLayout;
  FocusLayout _focusWidgetLayout;
  bool _focusWidgetShowAllGoals;
  bool _showTimeEstimates;
  bool _nudgesEnabled;
  int _nudgeHeartbeatMinutes;
  String _rewordPromptTemplate;

  DisplayPreferences._({
    required Box<String> box,
    required GoalSortOrder sortOrder,
    required GoalListLayout layout,
    required FocusLayout focusScreenLayout,
    required FocusLayout focusWidgetLayout,
    required bool focusWidgetShowAllGoals,
    required bool showTimeEstimates,
    required bool nudgesEnabled,
    required int nudgeHeartbeatMinutes,
    required String rewordPromptTemplate,
  })  : _box = box,
        _sortOrder = sortOrder,
        _layout = layout,
        _focusScreenLayout = focusScreenLayout,
        _focusWidgetLayout = focusWidgetLayout,
        _focusWidgetShowAllGoals = focusWidgetShowAllGoals,
        _showTimeEstimates = showTimeEstimates,
        _nudgesEnabled = nudgesEnabled,
        _nudgeHeartbeatMinutes = nudgeHeartbeatMinutes,
        _rewordPromptTemplate = rewordPromptTemplate;

  GoalSortOrder get sortOrder => _sortOrder;
  GoalListLayout get layout => _layout;

  /// Layout for the in-app Focus tab. Independent of [focusWidgetLayout].
  FocusLayout get focusScreenLayout => _focusScreenLayout;

  /// Layout for the home-screen widget. Independent of [focusScreenLayout].
  FocusLayout get focusWidgetLayout => _focusWidgetLayout;

  /// When true the widget shows the current step of every focused goal instead
  /// of only the topmost one. Defaults to false (single-goal mode).
  bool get focusWidgetShowAllGoals => _focusWidgetShowAllGoals;

  /// Global default for time-estimate visibility on subtasks and goal headers.
  /// Defaults to false — opt-in feature. Individual goals may override this
  /// via [Goal.showTimeEstimatesOverride] (resolved by [showEstimatesForGoal]).
  bool get showTimeEstimates => _showTimeEstimates;

  /// Whether the inactivity nudge feature is enabled. Defaults to false.
  /// When enabled, the home-screen widget shows an LLM-generated motivational
  /// message above the current step of any focused goal that has been idle for
  /// longer than [nudgeHeartbeatDuration].
  bool get nudgesEnabled => _nudgesEnabled;

  /// How long a focused goal must be idle before a nudge is shown.
  Duration get nudgeHeartbeatDuration =>
      Duration(minutes: _nudgeHeartbeatMinutes);

  /// The system prompt template used when rewriting subtasks. Editable in
  /// Settings → Generation → Reword prompt. Defaults to
  /// [defaultRewordPromptTemplate].
  String get rewordPromptTemplate => _rewordPromptTemplate;

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

  Future<void> setFocusWidgetShowAllGoals(bool value) async {
    _focusWidgetShowAllGoals = value;
    await _box.put(_focusWidgetShowAllGoalsKey, value.toString());
    notifyListeners();
  }

  Future<void> setShowTimeEstimates(bool value) async {
    _showTimeEstimates = value;
    await _box.put(_showTimeEstimatesKey, value.toString());
    notifyListeners();
  }

  Future<void> setNudgesEnabled(bool value) async {
    _nudgesEnabled = value;
    await _box.put(_nudgesEnabledKey, value.toString());
    notifyListeners();
  }

  Future<void> setNudgeHeartbeatMinutes(int minutes) async {
    _nudgeHeartbeatMinutes = minutes;
    await _box.put(_nudgeHeartbeatMinutesKey, minutes.toString());
    notifyListeners();
  }

  Future<void> setRewordPromptTemplate(String value) async {
    _rewordPromptTemplate = value;
    await _box.put(_rewordPromptTemplateKey, value);
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

    FocusLayout readFocusLayout(
      String key,
      FocusLayout fallback, {
      Set<FocusLayout> exclude = const {},
    }) {
      final name = box.get(key);
      if (name == null) return fallback;
      final parsed = FocusLayout.values.firstWhere(
        (e) => e.name == name,
        orElse: () => fallback,
      );
      // Silently upgrade prefs that point at a now-unsupported option for
      // this surface (e.g. an old Compact value for the home-screen widget,
      // which no longer exposes Compact in its picker).
      return exclude.contains(parsed) ? fallback : parsed;
    }

    final showAllGoalsRaw = box.get(_focusWidgetShowAllGoalsKey);
    final showAllGoals = showAllGoalsRaw == 'true';

    final showTimeEstimatesRaw = box.get(_showTimeEstimatesKey);
    final showTimeEstimates = showTimeEstimatesRaw == 'true';

    final nudgesEnabledRaw = box.get(_nudgesEnabledKey);
    final nudgesEnabled = nudgesEnabledRaw == 'true';

    final nudgeHeartbeatRaw = box.get(_nudgeHeartbeatMinutesKey);
    final nudgeHeartbeatMinutes =
        int.tryParse(nudgeHeartbeatRaw ?? '') ?? 60;

    final rewordPromptTemplate =
        box.get(_rewordPromptTemplateKey) ?? defaultRewordPromptTemplate;

    return DisplayPreferences._(
      box: box,
      sortOrder: sortOrder,
      layout: layout,
      focusScreenLayout:
          readFocusLayout(_focusScreenLayoutKey, FocusLayout.currentPlus2),
      focusWidgetLayout: readFocusLayout(
        _focusWidgetLayoutKey,
        FocusLayout.currentPlus2,
        exclude: const {FocusLayout.compact},
      ),
      focusWidgetShowAllGoals: showAllGoals,
      showTimeEstimates: showTimeEstimates,
      nudgesEnabled: nudgesEnabled,
      nudgeHeartbeatMinutes: nudgeHeartbeatMinutes,
      rewordPromptTemplate: rewordPromptTemplate,
    );
  }
}
