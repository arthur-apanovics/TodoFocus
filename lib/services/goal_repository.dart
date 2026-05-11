import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import '../models/goal.dart';

class GoalRepository extends ChangeNotifier {
  final List<Goal> _goals = [];

  List<Goal> get all => List.unmodifiable(_goals);

  Goal? findById(String goalId) =>
      _goals.firstWhereOrNull((g) => g.goalId == goalId);

  void save(Goal goal) {
    final index = _goals.indexWhere((g) => g.goalId == goal.goalId);
    if (index >= 0) {
      _goals[index] = goal;
    } else {
      _goals.add(goal);
    }
    notifyListeners();
  }

  void delete(String goalId) {
    _goals.removeWhere((g) => g.goalId == goalId);
    notifyListeners();
  }
}