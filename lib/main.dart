import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:todo_app/screens/focus_screen.dart';
import 'package:todo_app/screens/goal_active_screen.dart';
import 'package:todo_app/screens/goal_planning_screen.dart';
import 'package:todo_app/screens/goals_screen.dart';
import 'package:todo_app/screens/inbox_screen.dart';
import 'package:todo_app/screens/settings_screen.dart';
import 'package:todo_app/screens/widgets/new_goal_sheet.dart';
import 'package:todo_app/services/hive/hive_goal_repository.dart';
import 'package:todo_app/services/notification_service.dart';
import 'models/enums.dart';
import 'services/backup_service.dart';
import 'services/daily_reset_service.dart';
import 'services/decomposition_state.dart';
import 'services/display_preferences.dart';
import 'services/draft_service.dart';
import 'services/goal_decomposition_service.dart';
import 'services/goal_queries.dart';
import 'services/goal_repository.dart';
import 'services/goal_service.dart';
import 'services/settings/llm_settings_service.dart';
import 'screens/widgets/icon_catalog.dart';
import 'theme/app_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final goalRepository = await HiveGoalRepository.init();
  final llmSettingsService = await LlmSettingsService.init();
  final dailyResetService = await DailyResetService.init(goalRepository);
  final displayPreferences = await DisplayPreferences.init();

  final tabNotifier = ValueNotifier<int>(0);
  final goalNavNotifier =
      ValueNotifier<({String goalId, int seq, bool breakdown})?>(null);

  final notificationService = NotificationService(
    goalNavNotifier: goalNavNotifier,
    repository: goalRepository,
  );
  await notificationService.init();

  // Schedule morning prompt if configured.
  if (dailyResetService.morningPromptEnabled) {
    final t = dailyResetService.morningPromptTime;
    await notificationService.scheduleMorningPrompt(t.hour, t.minute);
  }

  goalRepository.addListener(() {
    notificationService.update(GoalQueries(goalRepository).todayQueue);
  });

  // Show initial state on startup (covers app restart with focused goals).
  notificationService.update(GoalQueries(goalRepository).todayQueue);

  runApp(
    TodoApp(
      goalRepository: goalRepository,
      llmSettingsService: llmSettingsService,
      dailyResetService: dailyResetService,
      displayPreferences: displayPreferences,
      notificationService: notificationService,
      tabNotifier: tabNotifier,
      goalNavNotifier: goalNavNotifier,
    ),
  );
}

class TodoApp extends StatelessWidget {
  final GoalRepository goalRepository;
  final LlmSettingsService llmSettingsService;
  final DailyResetService dailyResetService;
  final DisplayPreferences displayPreferences;
  final NotificationService notificationService;
  final ValueNotifier<int> tabNotifier;
  final ValueNotifier<({String goalId, int seq, bool breakdown})?>
  goalNavNotifier;

  const TodoApp({
    super.key,
    required this.goalRepository,
    required this.llmSettingsService,
    required this.dailyResetService,
    required this.displayPreferences,
    required this.notificationService,
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
        ProxyProvider<GoalRepository, GoalService>(
          update: (_, repository, _) => GoalService(repository),
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
        ProxyProvider2<GoalRepository, LlmSettingsService, BackupService>(
          update: (_, goals, settings, _) =>
              BackupService(goals: goals, settings: settings),
        ),
        // Exposed so AppShell can re-post the notification on resume.
        Provider<NotificationService>.value(value: notificationService),
      ],
      child: MaterialApp(
        title: 'Todo App',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: AppColors.accent),
          useMaterial3: true,
        ),
        home: AppShell(
          tabNotifier: tabNotifier,
          goalNavNotifier: goalNavNotifier,
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
  late final ValueNotifier<bool> _goalsShowCompleted;

  static const _tabTitles = ['Today', 'Goals', 'Planning'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.tabNotifier.value,
    );
    _goalsShowCompleted = ValueNotifier(false);
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
    _goalsShowCompleted.dispose();
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
    final notif = context.read<NotificationService>();
    final resetService = context.read<DailyResetService>();

    final wasReset = await resetService.checkAndReset();
    final queue = GoalQueries(repo).todayQueue;

    if (wasReset && queue.isEmpty) {
      await notif.showAssignTasksPrompt();
    } else {
      await notif.update(queue);
    }
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
            GoalActiveScreen(goalId: goalId, triggerBreakdown: breakdown),
      ),
    );
  }

  void _onDestinationSelected(int index) {
    _tabController.animateTo(index);
    widget.tabNotifier.value = index;
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

  Widget _buildFab(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: _openNewGoalSheet,
      icon: const Icon(Icons.add),
      label: const Text('Create goal'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inboxCount = context.watch<GoalQueries>().inbox.length;
    return AnimatedBuilder(
      animation: Listenable.merge([_tabController, _goalsShowCompleted]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(_tabTitles[_tabController.index]),
          actions: [
            if (_tabController.index == 1) ...[
              _GoalsFilterButton(
                showCompleted: _goalsShowCompleted.value,
                onChanged: (v) => _goalsShowCompleted.value = v,
              ),
              _SortButton(),
              _LayoutButton(),
            ],
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
        body: TabBarView(
          controller: _tabController,
          children: [
            const FocusScreen(),
            GoalsScreen(showCompletedNotifier: _goalsShowCompleted),
            const InboxScreen(),
          ],
        ),
        floatingActionButton: _buildFab(context),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tabController.index,
          onDestinationSelected: _onDestinationSelected,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.bolt_outlined),
              selectedIcon: Icon(Icons.bolt),
              label: 'Focus',
            ),
            const NavigationDestination(
              icon: Icon(Icons.flag_outlined),
              selectedIcon: Icon(Icons.flag),
              label: 'Goals',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: inboxCount > 0,
                label: Text('$inboxCount'),
                child: const Icon(Icons.edit_note_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: inboxCount > 0,
                label: Text('$inboxCount'),
                child: const Icon(Icons.edit_note),
              ),
              label: 'Planning',
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Goals tab — filter toggle (Active / Done) + sort button + sort sheet
// ---------------------------------------------------------------------------

class _GoalsFilterButton extends StatelessWidget {
  final bool showCompleted;
  final ValueChanged<bool> onChanged;

  const _GoalsFilterButton({
    required this.showCompleted,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SegmentedButton<bool>(
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: Theme.of(context).textTheme.labelSmall,
        ),
        segments: const [
          ButtonSegment(value: false, label: Text('Active')),
          ButtonSegment(value: true, label: Text('Done')),
        ],
        selected: {showCompleted},
        onSelectionChanged: (s) => onChanged(s.first),
        showSelectedIcon: false,
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final order = context.watch<DisplayPreferences>().sortOrder;
    return IconButton(
      icon: const Icon(Icons.sort),
      tooltip: 'Sort goals',
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        builder: (_) => _SortSheet(
          current: order,
          onSelected: context.read<DisplayPreferences>().setSortOrder,
        ),
      ),
    );
  }
}

class _SortSheet extends StatelessWidget {
  final GoalSortOrder current;
  final void Function(GoalSortOrder) onSelected;

  const _SortSheet({required this.current, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              'Sort goals',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          _SortTile(
            label: 'Date added',
            subtitle: 'Oldest first',
            icon: Icons.calendar_today_outlined,
            selected: current == GoalSortOrder.dateAdded,
            onTap: () {
              onSelected(GoalSortOrder.dateAdded);
              Navigator.pop(context);
            },
          ),
          _SortTile(
            label: 'Urgency',
            subtitle: 'Near deadlines → previously assigned → rest',
            icon: Icons.priority_high,
            selected: current == GoalSortOrder.urgency,
            onTap: () {
              onSelected(GoalSortOrder.urgency);
              Navigator.pop(context);
            },
          ),
          _SortTile(
            label: 'Smart',
            subtitle: 'Same as urgency — recommended default',
            icon: Icons.auto_awesome_outlined,
            selected: current == GoalSortOrder.smart,
            onTap: () {
              onSelected(GoalSortOrder.smart);
              Navigator.pop(context);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SortTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SortTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: selected ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(
        label,
        style: selected
            ? TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              )
            : null,
      ),
      subtitle: Text(subtitle),
      trailing: selected ? const Icon(Icons.check) : null,
      onTap: onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// Layout button — toggles how many subtask steps are shown inline per goal
// ---------------------------------------------------------------------------

class _LayoutButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final layout = context.watch<DisplayPreferences>().layout;
    final setLayout = context.read<DisplayPreferences>().setLayout;
    return PopupMenuButton<GoalListLayout>(
      icon: Icon(Icons.view_list_outlined),
      tooltip: 'List layout',
      onSelected: setLayout,
      itemBuilder: (_) => [
        _item(GoalListLayout.compact, 'Compact', layout),
        _item(GoalListLayout.current, 'Current step', layout),
        _item(GoalListLayout.currentPlus2, 'Current + 2 next', layout),
        _item(GoalListLayout.currentPlus4, 'Current + 4 next', layout),
      ],
    );
  }

  PopupMenuItem<GoalListLayout> _item(
    GoalListLayout value,
    String label,
    // IconData icon,
    GoalListLayout current,
  ) {
    return PopupMenuItem(
      value: value,
      child: ListTile(
        // leading: Icon(icon),
        title: Text(label),
        trailing: current == value ? const Icon(Icons.check, size: 18) : null,
        contentPadding: EdgeInsets.zero,
        dense: true,
        minLeadingWidth: 24,
      ),
    );
  }
}
