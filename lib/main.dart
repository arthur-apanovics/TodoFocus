import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:todo_app/screens/goals_screen.dart';
import 'package:todo_app/screens/widgets/new_goal_sheet.dart';
import 'services/goal_repository.dart';
import 'services/goal_service.dart';
import 'services/goal_queries.dart';
import 'services/goal_decomposition_service.dart';

void main() {
  runApp(const TodoApp());
}

class TodoApp extends StatelessWidget {
  const TodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    // MultiProvider is your DI container registration — like Program.cs
    // Order matters: if service A depends on B, register B first
    return MultiProvider(
      providers: [
        // ChangeNotifierProvider — use this for anything the UI reacts to
        // GoalRepository is the source of truth, so it drives reactivity
        ChangeNotifierProvider<GoalRepository>(
          create: (_) => InMemoryGoalRepository(),
        ),

        // ProxyProvider — like ASP.NET DI resolving a dependency from the container
        // GoalService depends on GoalRepository, so we resolve it here
        ProxyProvider<GoalRepository, GoalService>(
          update: (_, repository, __) => GoalService(repository),
        ),

        // GoalQueries also depends on GoalRepository
        ProxyProvider<GoalRepository, GoalQueries>(
          update: (_, repository, __) => GoalQueries(repository),
        ),

        // No dependencies — plain Provider is fine
        Provider(create: (_) => GoalDecompositionService()),
      ],
      child: MaterialApp(
        title: 'Todo',
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
    Center(child: Text('Focus — coming soon')),
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
  }}
