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

  final tabNotifier = ValueNotifier<int>(0);
  final goalNavNotifier =
      ValueNotifier<({String goalId, int seq, bool breakdown})?>(null);

  final notificationService = NotificationService(
    tabNotifier: tabNotifier,
    goalNavNotifier: goalNavNotifier,
    repository: goalRepository,
  );
  await notificationService.init();

  goalRepository.addListener(() {
    notificationService.update(GoalQueries(goalRepository).todayQueue);
  });

  // Show initial state on startup (covers app restart with focused goals).
  notificationService.update(GoalQueries(goalRepository).todayQueue);

  runApp(TodoApp(
    goalRepository: goalRepository,
    llmSettingsService: llmSettingsService,
    notificationService: notificationService,
    tabNotifier: tabNotifier,
  ));
}

class TodoApp extends StatelessWidget {
  final GoalRepository goalRepository;
  final LlmSettingsService llmSettingsService;
  final NotificationService notificationService;
  final ValueNotifier<int> tabNotifier;

  const TodoApp({
    super.key,
    required this.goalRepository,
    required this.llmSettingsService,
    required this.notificationService,
    required this.tabNotifier,
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
          update: (_, settings, __) =>
              GoalDecompositionService(client: settings.buildClient()),
        ),
        ChangeNotifierProvider<DecompositionState>(
          create: (_) => DecompositionState(),
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
      // Re-post the notification in case it was cleared while backgrounded.
      // ongoing: true blocks swipe-to-dismiss but not long-press clear or
      // system memory pressure, so we always re-assert it on resume.
      final repo = context.read<GoalRepository>();
      context.read<NotificationService>()
          .update(GoalQueries(repo).todayQueue);
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
    if (goalId != null && context.mounted) {
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
