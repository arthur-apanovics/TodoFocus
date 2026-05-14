import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:todo_app/services/sample_data.dart';
import '../models/goal.dart';

abstract class GoalRepository extends ChangeNotifier {
  void save(Goal goal);

  void delete(String goalId);

  Future<void> clear();

  Goal? findById(String goalId);

  List<Goal> get all;

  List<Map<String, dynamic>> exportToJson();

  Future<({int imported, int skipped})> importFromJson(List<dynamic> data);
}

class InMemoryGoalRepository extends GoalRepository {
  final List<Goal> _goals;

  InMemoryGoalRepository() : _goals = List.from(SampleData.goals);

  InMemoryGoalRepository.empty() : _goals = [];

  @override
  List<Goal> get all => List.unmodifiable(_goals);

  @override
  Goal? findById(String goalId) =>
      _goals.firstWhereOrNull((g) => g.goalId == goalId);

  @override
  void save(Goal goal) {
    final index = _goals.indexWhere((g) => g.goalId == goal.goalId);
    if (index >= 0) {
      _goals[index] = goal;
    } else {
      _goals.add(goal);
    }
    notifyListeners();
  }

  @override
  void delete(String goalId) {
    _goals.removeWhere((g) => g.goalId == goalId);
    notifyListeners();
  }

  @override
  Future<void> clear() async {
    _goals.clear();
    notifyListeners();
  }

  @override
  List<Map<String, dynamic>> exportToJson() =>
      _goals.map((g) => g.toJson()).toList();

  @override
  Future<({int imported, int skipped})> importFromJson(List<dynamic> data) async {
    int imported = 0;
    int skipped = 0;
    _goals.clear();
    for (final item in data) {
      try {
        _goals.add(Goal.fromJson(item as Map<String, dynamic>));
        imported++;
      } catch (_) {
        skipped++;
      }
    }
    notifyListeners();
    return (imported: imported, skipped: skipped);
  }
}
