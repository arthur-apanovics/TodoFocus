import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Todo App",
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightGreen),
        useMaterial3: true,
      ),
      home: const TodoScreen(),
    );
  }
}

class TodoScreen extends StatelessWidget {
  const TodoScreen({super.key});

  static const List<String> _todos = [
    "Pet a doggie",
    "Water plants",
    "Buy crypto",
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Todos")),
      // aka flexbox column
      body: Column(
        children: [
          // flexbox flex:1
          Expanded(
            child: ListView(
              children: [
                // same as .map(() => <JSX/>)
                for (final todo in _todos) TodoItem(label: todo),
              ],
            ),
          ),
          const NewTodoInput(),
        ],
      ),
    );
  }
}

class TodoItem extends StatelessWidget {
  final String label; // "props" - passed in from the parent

  const TodoItem({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.check_box_outline_blank),
      title: Text(label),
    );
  }
}

class NewTodoInput extends StatelessWidget {
  const NewTodoInput({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: "Add a todo...",
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8), // spacer div
            FilledButton(onPressed: null, child: const Text("Add")),
          ],
        ),
      ),
    );
  }
}
