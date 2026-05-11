import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:todo_app/services/sample_data.dart';
import '../models/goal.dart';

abstract class GoalRepository extends ChangeNotifier {
  void save(Goal goal);

  void delete(String goalId);

  Goal? findById(String goalId);

  List<Goal> get all;
}

class InMemoryGoalRepository extends GoalRepository {
  final List<Goal> _goals = List.from(SampleData.goals);

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
}
