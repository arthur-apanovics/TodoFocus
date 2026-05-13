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

  final notificationService = NotificationService(
    tabNotifier: tabNotifier,
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
              GoalDecompositionService(llm: settings.buildClient()),
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
        home: AppShell(tabNotifier: tabNotifier),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  final ValueNotifier<int> tabNotifier;

  const AppShell({super.key, required this.tabNotifier});

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
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.tabNotifier.removeListener(_onExternalTabChange);
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

  void _onDestinationSelected(int index) {
    setState(() => _currentIndex = index);
    widget.tabNotifier.value = index;
  }

  FloatingActionButton _buildFab(BuildContext context) {
    return FloatingActionButton(
      onPressed: () async {
        // Read inside onPressed so we always get the current instances —
        // reading at build time would capture stale references when
        // LlmSettingsService notifies and ProxyProvider rebuilds the service.
        final goalService = context.read<GoalService>();
        final decompositionService = context.read<GoalDecompositionService>();

        final goalId = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => NewGoalSheet(
            goalService: goalService,
            decompositionService: decompositionService,
          ),
        );
        if (goalId != null && context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GoalDetailScreen(goalId: goalId),
            ),
          );
        }
      },
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
