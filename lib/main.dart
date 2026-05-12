import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:todo_app/screens/focus_screen.dart';
import 'package:todo_app/screens/goals_screen.dart';
import 'package:todo_app/screens/widgets/new_goal_sheet.dart';
import 'package:todo_app/services/hive/hive_goal_repository.dart';
import 'services/goal_repository.dart';
import 'services/goal_service.dart';
import 'services/goal_queries.dart';
import 'services/goal_decomposition_service.dart';

void main() async {
  // Required before any async work in main()
  // Ensures Flutter engine is ready before we do anything
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise Hive and open the box before the app starts
  final goalRepository = await HiveGoalRepository.init();

  runApp(TodoApp(goalRepository: goalRepository));
}

class TodoApp extends StatelessWidget {
  final GoalRepository goalRepository;

  const TodoApp({super.key, required this.goalRepository});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Provide the already-initialised repository directly
        ChangeNotifierProvider<GoalRepository>.value(value: goalRepository),

        ProxyProvider<GoalRepository, GoalService>(
          update: (_, repository, __) => GoalService(repository),
        ),
        ProxyProvider<GoalRepository, GoalQueries>(
          update: (_, repository, __) => GoalQueries(repository),
        ),
        Provider(create: (_) => GoalDecompositionService()),
      ],
      child: MaterialApp(
        title: 'Todo App',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          useMaterial3: true,
        ),
        home: const AppShell(),
      ),
    );
  }
}

// Bottom navigation shell — holds the three top-level screens
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  // The three top-level screens — instantiated once, not rebuilt on tab switch
  static const List<Widget> _screens = [
    FocusScreen(),
    GoalsScreen(),
    Center(child: Text('Inbox — coming soon')),
  ];

  FloatingActionButton _buildFab(BuildContext context) {
    // Read services once — not watched, just needed for the action
    final goalService = context.read<GoalService>();
    final decompositionService = context.read<GoalDecompositionService>();

    return FloatingActionButton(
      onPressed: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => NewGoalSheet(
            goalService: goalService,
            decompositionService: decompositionService,
          ),
        );
      },
      child: const Icon(Icons.add),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      floatingActionButton: _buildFab(context),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
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
