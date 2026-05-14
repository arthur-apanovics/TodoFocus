import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:todo_app/screens/focus_screen.dart';
import 'package:todo_app/screens/goal_detail_screen.dart';
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
import 'services/goal_decomposition_service.dart';
import 'services/goal_queries.dart';
import 'services/goal_repository.dart';
import 'services/goal_service.dart';
import 'services/settings/llm_settings_service.dart';
import 'theme/app_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final goalRepository = await HiveGoalRepository.init();
  final llmSettingsService = await LlmSettingsService.init();
  final dailyResetService = await DailyResetService.init(goalRepository);

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

  runApp(TodoApp(
    goalRepository: goalRepository,
    llmSettingsService: llmSettingsService,
    dailyResetService: dailyResetService,
    notificationService: notificationService,
    tabNotifier: tabNotifier,
    goalNavNotifier: goalNavNotifier,
  ));
}

class TodoApp extends StatelessWidget {
  final GoalRepository goalRepository;
  final LlmSettingsService llmSettingsService;
  final DailyResetService dailyResetService;
  final NotificationService notificationService;
  final ValueNotifier<int> tabNotifier;
  final ValueNotifier<({String goalId, int seq, bool breakdown})?> goalNavNotifier;

  const TodoApp({
    super.key,
    required this.goalRepository,
    required this.llmSettingsService,
    required this.dailyResetService,
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
          update: (_, settings, _) =>
              GoalDecompositionService(client: settings.buildClient()),
        ),
        ChangeNotifierProvider<DecompositionState>(
          create: (_) => DecompositionState(),
        ),
        ChangeNotifierProvider<DailyResetService>.value(
          value: dailyResetService,
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
        home: AppShell(tabNotifier: tabNotifier, goalNavNotifier: goalNavNotifier),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  final ValueNotifier<int> tabNotifier;
  final ValueNotifier<({String goalId, int seq, bool breakdown})?> goalNavNotifier;

  const AppShell({
    super.key,
    required this.tabNotifier,
    required this.goalNavNotifier,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  late int _currentIndex;

  static const _tabTitles = ['Today', 'Goals', 'Inbox'];

  static const List<Widget> _screens = [
    FocusScreen(),
    GoalsScreen(),
    InboxScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.tabNotifier.value;
    widget.tabNotifier.addListener(_onExternalTabChange);
    widget.goalNavNotifier.addListener(_onGoalNavRequested);
    WidgetsBinding.instance.addObserver(this);
    // Cold-start: notification action fired before AppShell was mounted.
    final pending = widget.goalNavNotifier.value;
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _navigateToGoal(pending.goalId, breakdown: pending.breakdown);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.tabNotifier.removeListener(_onExternalTabChange);
    widget.goalNavNotifier.removeListener(_onGoalNavRequested);
    super.dispose();
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
    if (mounted && widget.tabNotifier.value != _currentIndex) {
      setState(() => _currentIndex = widget.tabNotifier.value);
    }
  }

  void _onGoalNavRequested() {
    final request = widget.goalNavNotifier.value;
    if (!mounted || request == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _navigateToGoal(request.goalId, breakdown: request.breakdown);
    });
  }

  void _navigateToGoal(String goalId, {bool breakdown = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GoalDetailScreen(
          goalId: goalId,
          triggerBreakdown: breakdown,
        ),
      ),
    );
  }

  void _onDestinationSelected(int index) {
    setState(() => _currentIndex = index);
    widget.tabNotifier.value = index;
  }

  // Opens the new-goal bottom sheet and navigates to the detail screen on
  // success. Called from the FAB and the notification action.
  Future<void> _openNewGoalSheet() async {
    // Read inside the method so we always get current instances — reading at
    // build time would capture stale refs when ProxyProvider rebuilds.
    final goalService = context.read<GoalService>();
    final decompositionService = context.read<GoalDecompositionService>();
    final decompositionState = context.read<DecompositionState>();

    final goalId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => NewGoalSheet(
        goalService: goalService,
        decompositionService: decompositionService,
        decompositionState: decompositionState,
      ),
    );
    if (goalId != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => GoalDetailScreen(goalId: goalId)),
      );
    }
  }

  FloatingActionButton _buildFab(BuildContext context) {
    return FloatingActionButton(
      onPressed: _openNewGoalSheet,
      child: const Icon(Icons.add),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tabTitles[_currentIndex]),
        actions: [
          if (_currentIndex == 1) _SortButton(),
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
      body: _screens[_currentIndex],
      floatingActionButton: _buildFab(context),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bolt_outlined),
            selectedIcon: Icon(Icons.bolt),
            label: 'Focus',
          ),
          NavigationDestination(
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag),
            label: 'Goals',
          ),
          NavigationDestination(
            icon: Icon(Icons.inbox_outlined),
            selectedIcon: Icon(Icons.inbox),
            label: 'Inbox',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sort button + sheet (Goals tab only)
// ---------------------------------------------------------------------------

class _SortButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final order = context.watch<DailyResetService>().sortOrder;
    return IconButton(
      icon: const Icon(Icons.sort),
      tooltip: 'Sort goals',
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        builder: (_) => _SortSheet(
          current: order,
          onSelected: context.read<DailyResetService>().setSortOrder,
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
      leading: Icon(icon,
          color: selected ? Theme.of(context).colorScheme.primary : null),
      title: Text(label,
          style: selected
              ? TextStyle(color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600)
              : null),
      subtitle: Text(subtitle),
      trailing: selected ? const Icon(Icons.check) : null,
      onTap: onTap,
    );
  }
}
