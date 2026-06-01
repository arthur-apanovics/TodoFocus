import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:todo_app/models/enums.dart';
import 'package:todo_app/screens/focus_screen.dart';
import 'package:todo_app/screens/goal_planning_screen.dart';
import 'package:todo_app/screens/goals_screen.dart';
import 'package:todo_app/screens/inbox_screen.dart';
import 'package:todo_app/screens/settings_screen.dart';
import 'package:todo_app/screens/widgets/new_goal_sheet.dart';
import 'package:todo_app/services/hive/hive_goal_repository.dart';
import 'package:todo_app/services/notification_service.dart';
import 'package:todo_app/theme/app_palette.dart';
import 'services/backup_service.dart';
import 'services/google_drive_backup_service.dart';
import 'services/daily_reset_service.dart';
import 'services/decomposition_state.dart';
import 'services/display_preferences.dart';
import 'services/draft_service.dart';
import 'services/focus_list_service.dart';
import 'services/focus_widget_service.dart';
import 'services/goal_decomposition_service.dart';
import 'services/goal_queries.dart';
import 'services/goal_repository.dart';
import 'services/goal_service.dart';
import 'services/scheduling_service.dart';
import 'services/settings/llm_settings_service.dart';
import 'services/theme_controller.dart';
import 'screens/widgets/icon_catalog.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final goalRepository = await HiveGoalRepository.init();
  final llmSettingsService = await LlmSettingsService.init();
  final focusListService = await FocusListService.init();
  final dailyResetService = await DailyResetService.init(focusListService);
  final displayPreferences = await DisplayPreferences.init();
  final themeController = await ThemeController.init();

  final tabNotifier = ValueNotifier<int>(0);
  final goalNavNotifier =
      ValueNotifier<({String goalId, int seq, bool breakdown})?>(null);

  final notificationService = NotificationService(
    goalNavNotifier: goalNavNotifier,
    repository: goalRepository,
    focus: focusListService,
  );
  await notificationService.init();

  // Single source of truth for time-elapsed transitions (snooze wake-ups
  // and recurrence resets). Run it once at startup so any state we missed
  // while the app was closed is applied before the UI renders.
  final schedulingService = SchedulingService(goalRepository);
  schedulingService.checkAndProcess();

  final googleDriveBackupService = await GoogleDriveBackupService.init(
    goals: goalRepository,
    settings: llmSettingsService,
    focus: focusListService,
  );

  // Home-screen widget bridge. Mirrors the notification: re-rendered whenever
  // focus or goal data changes, or the widget layout preference is edited.
  final focusWidgetService = FocusWidgetService(
    repository: goalRepository,
    focus: focusListService,
    prefs: displayPreferences,
  );
  await FocusWidgetService.registerBackgroundCallback();

  // Re-post the notification AND re-render the home-screen widget whenever the
  // focus list or the underlying goal data changes. Either source can shift
  // which subtask is "current".
  void refreshFocusSurfaces() {
    notificationService.update(
      focusListService.resolveGroups(goalRepository),
      showEmptyPrompt: dailyResetService.morningPromptEnabled,
    );
    focusWidgetService.update();
  }

  goalRepository.addListener(refreshFocusSurfaces);
  focusListService.addListener(refreshFocusSurfaces);
  // The widget layout preference also changes what the widget renders.
  displayPreferences.addListener(focusWidgetService.update);
  refreshFocusSurfaces();

  runApp(
    TodoApp(
      goalRepository: goalRepository,
      llmSettingsService: llmSettingsService,
      focusListService: focusListService,
      dailyResetService: dailyResetService,
      displayPreferences: displayPreferences,
      themeController: themeController,
      notificationService: notificationService,
      focusWidgetService: focusWidgetService,
      schedulingService: schedulingService,
      googleDriveBackupService: googleDriveBackupService,
      tabNotifier: tabNotifier,
      goalNavNotifier: goalNavNotifier,
    ),
  );
}

class TodoApp extends StatelessWidget {
  final GoalRepository goalRepository;
  final LlmSettingsService llmSettingsService;
  final FocusListService focusListService;
  final DailyResetService dailyResetService;
  final DisplayPreferences displayPreferences;
  final ThemeController themeController;
  final NotificationService notificationService;
  final FocusWidgetService focusWidgetService;
  final SchedulingService schedulingService;
  final GoogleDriveBackupService googleDriveBackupService;
  final ValueNotifier<int> tabNotifier;
  final ValueNotifier<({String goalId, int seq, bool breakdown})?>
  goalNavNotifier;

  const TodoApp({
    super.key,
    required this.goalRepository,
    required this.llmSettingsService,
    required this.focusListService,
    required this.dailyResetService,
    required this.displayPreferences,
    required this.themeController,
    required this.notificationService,
    required this.focusWidgetService,
    required this.schedulingService,
    required this.googleDriveBackupService,
    required this.tabNotifier,
    required this.goalNavNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<GoalRepository>.value(value: goalRepository),
        ChangeNotifierProvider<LlmSettingsService>.value(
          value: llmSettingsService,
        ),
        ChangeNotifierProvider<FocusListService>.value(
          value: focusListService,
        ),
        ProxyProvider2<GoalRepository, FocusListService, GoalService>(
          update: (_, repository, focus, _) => GoalService(repository, focus),
        ),
        ProxyProvider<GoalRepository, GoalQueries>(
          update: (_, repository, _) => GoalQueries(repository),
        ),
        ProxyProvider<LlmSettingsService, GoalDecompositionService>(
          update: (_, settings, _) => GoalDecompositionService(
            client: settings.buildClient(),
            generateEmojis: settings.generateEmojis,
            iconNames: iconByName.keys.toList(),
          ),
        ),
        ChangeNotifierProvider<DecompositionState>(
          create: (_) => DecompositionState(),
        ),
        Provider<DraftService>(create: (_) => DraftService()),
        ChangeNotifierProvider<DailyResetService>.value(
          value: dailyResetService,
        ),
        ChangeNotifierProvider<DisplayPreferences>.value(
          value: displayPreferences,
        ),
        ChangeNotifierProvider<ThemeController>.value(
          value: themeController,
        ),
        ProxyProvider3<GoalRepository, LlmSettingsService, FocusListService,
            BackupService>(
          update: (_, goals, settings, focus, _) => BackupService(
            goals: goals,
            settings: settings,
            focus: focus,
          ),
        ),
        ChangeNotifierProvider<GoogleDriveBackupService>.value(
          value: googleDriveBackupService,
        ),
        // Exposed so AppShell can re-post the notification on resume.
        Provider<NotificationService>.value(value: notificationService),
        // Exposed so AppShell can re-render the home-screen widget on resume.
        Provider<FocusWidgetService>.value(value: focusWidgetService),
        // Exposed so AppShell can re-run the snooze / recurrence sweep on
        // resume, and so screens can call setRecurrence / snooze flows.
        ChangeNotifierProvider<SchedulingService>.value(
          value: schedulingService,
        ),
      ],
      child: Consumer<ThemeController>(
        builder: (context, theme, _) => MaterialApp(
          title: 'Todo App',
          theme: AppTheme.light(theme.color),
          darkTheme: AppTheme.dark(theme.color),
          themeMode: theme.mode,
          home: AppShell(
            tabNotifier: tabNotifier,
            goalNavNotifier: goalNavNotifier,
          ),
        ),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  final ValueNotifier<int> tabNotifier;
  final ValueNotifier<({String goalId, int seq, bool breakdown})?>
  goalNavNotifier;

  const AppShell({
    super.key,
    required this.tabNotifier,
    required this.goalNavNotifier,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.tabNotifier.value,
    );
    _tabController.addListener(_onTabControllerChanged);
    widget.tabNotifier.addListener(_onExternalTabChange);
    widget.goalNavNotifier.addListener(_onGoalNavRequested);
    WidgetsBinding.instance.addObserver(this);
    // Cold-start: notification action fired before AppShell was mounted.
    final pending = widget.goalNavNotifier.value;
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted)
          _navigateToGoal(pending.goalId, breakdown: pending.breakdown);
      });
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabControllerChanged);
    _tabController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    widget.tabNotifier.removeListener(_onExternalTabChange);
    widget.goalNavNotifier.removeListener(_onGoalNavRequested);
    super.dispose();
  }

  // Fires on every animation frame during a swipe and once when settled.
  // Only sync the notifier when the animation has fully settled to avoid
  // triggering side-effects (e.g. notification updates) mid-swipe.
  void _onTabControllerChanged() {
    if (!_tabController.indexIsChanging &&
        widget.tabNotifier.value != _tabController.index) {
      widget.tabNotifier.value = _tabController.index;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkResetAndUpdateNotification();
    }
  }

  Future<void> _checkResetAndUpdateNotification() async {
    final repo = context.read<GoalRepository>();
    final focus = context.read<FocusListService>();
    final notif = context.read<NotificationService>();
    final focusWidget = context.read<FocusWidgetService>();
    final resetService = context.read<DailyResetService>();
    final scheduling = context.read<SchedulingService>();

    // Apply any pending wake-ups / recurrence resets first so the focus
    // list resolves against the freshest state. Order matters here: the
    // scheduling sweep may add or remove a goal's "current" subtask, which
    // changes what the notification should show.
    scheduling.checkAndProcess();

    // Run the daily reset before resolving groups — it may clear the focus
    // list, which flips the notification to its empty state.
    await resetService.checkAndReset();
    final groups = focus.resolveGroups(repo);
    await notif.update(
      groups,
      showEmptyPrompt: resetService.morningPromptEnabled,
    );
    // Keep the home-screen widget in step with whatever the resume sweep did.
    await focusWidget.update();

    // Auto-backup to Google Drive if signed in and the last backup is stale.
    // Fire-and-forget: we don't await to avoid blocking the resume path.
    context.read<GoogleDriveBackupService>().autoBackupIfStale();
  }

  void _onExternalTabChange() {
    if (mounted && widget.tabNotifier.value != _tabController.index) {
      _tabController.animateTo(widget.tabNotifier.value);
    }
  }

  void _onGoalNavRequested() {
    final request = widget.goalNavNotifier.value;
    if (!mounted || request == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted)
        _navigateToGoal(request.goalId, breakdown: request.breakdown);
    });
  }

  void _navigateToGoal(String goalId, {bool breakdown = false}) {
    // Notifications only ever fire for goals in the today queue, which are
    // by definition active — route straight to the execution view. The
    // breakdown flag carries through so the "Break it down" notification
    // action triggers immediately on arrival.
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            GoalPlanningScreen(goalId: goalId, triggerBreakdown: breakdown),
      ),
    );
  }

  // Opens the new-goal bottom sheet. "Save" closes the sheet silently
  // (goal lives in Planning tab); "Plan" returns the goalId so we push
  // straight into the planning screen for subtask shaping.
  Future<void> _openNewGoalSheet() async {
    // Read inside the method so we always get current instances — reading at
    // build time would capture stale refs when ProxyProvider rebuilds.
    final goalService = context.read<GoalService>();
    final decompositionService = context.read<GoalDecompositionService>();
    final draftService = context.read<DraftService>();

    final goalId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => NewGoalSheet(
        goalService: goalService,
        decompositionService: decompositionService,
        draftService: draftService,
      ),
    );
    if (goalId != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => GoalPlanningScreen(goalId: goalId)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Tab titles live in the toolbar itself (no app title, no bottom
        // strip) so the three screens get the vertical space back.
        titleSpacing: 0,
        title: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: 'Focus'),
            const Tab(text: 'Goals'),
            // Badge showing how many goals are still in the Inbox waiting to
            // be planned/queued. Rebuilds via context.watch on the repo so
            // it stays in sync when goals are added, queued, or deleted.
            Tab(child: _PlanningTabLabel()),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                FocusScreen(),
                GoalsScreen(),
                InboxScreen(),
              ],
            ),
          ),
          _NewGoalHandle(onOpen: _openNewGoalSheet),
        ],
      ),
    );
  }
}

/// Thin handle strip at the bottom of the AppShell body. Tapping or swiping
/// up opens the new-goal sheet. Sits in-flow (below the TabBarView), so it
/// doesn't float over any screen content.
///
/// Sized + positioned so the *swipe-detection* area lives well clear of
/// the OS gesture-nav swipe-up zone at the very bottom of the screen.
/// Without the SafeArea pad-out + the generous height, the system gesture
/// (home / back) wins every upward fling before this handle's
/// `onVerticalDragEnd` ever sees it.
class _NewGoalHandle extends StatelessWidget {
  final VoidCallback onOpen;

  const _NewGoalHandle({required this.onOpen});

  // Total height of the gesture-capture area. Material's BottomSheet has
  // a ~64dp default drag header; we match that so the swipe target is at
  // least as comfortable as a system sheet's. The visible pill stays
  // small (the height is mostly invisible padding around it).
  static const double _captureHeight = 44;

  // Visible pill — sized like the AppBottomSheet handle so the two read
  // as the same affordance: "this is something you can pull on".
  static const double _pillWidth = 68;
  static const double _pillHeight = 4;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      // Push the handle ABOVE any system gesture inset at the bottom
      // (e.g. the home-indicator zone on gesture-nav devices). Without
      // this, the bottom slice of the handle overlaps the gesture bar
      // and the OS swipe wins.
      top: false,
      child: GestureDetector(
        onTap: onOpen,
        onVerticalDragUpdate: (details) {
          // Any noticeable upward motion opens the sheet — don't wait for
          // the gesture to "end", so the user gets feedback the moment
          // their finger starts moving instead of after lift-off.
          if ((details.primaryDelta ?? 0) < -2) onOpen();
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: _captureHeight,
          // The thin top divider mimics a sheet's edge so the strip reads
          // as the "lip" of a hidden sheet, hinting at what comes up.
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
          ),
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: _pillWidth,
                  height: _pillHeight,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'New goal',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Planning" tab label with a Material badge showing how many goals are
/// sitting in the inbox waiting to be planned. The badge only renders when
/// the count is > 0, so an empty inbox shows a plain label.
class _PlanningTabLabel extends StatelessWidget {
  const _PlanningTabLabel();

  @override
  Widget build(BuildContext context) {
    // Watching the repository (not GoalQueries) because GoalQueries is a
    // pass-through and isn't itself a ChangeNotifier — the repo is the real
    // source of mutations.
    final repo = context.watch<GoalRepository>();
    final inboxCount =
        repo.all.where((g) => g.status == GoalStatus.inbox).length;
    if (inboxCount == 0) return const Text('Planning');
    return Badge(
      label: Text('$inboxCount'),
      backgroundColor: context.palette.accent,
      child: const Padding(
        padding: EdgeInsets.only(right: 10),
        child: Text('Planning'),
      ),
    );
  }
}
