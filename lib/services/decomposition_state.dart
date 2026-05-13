import 'package:flutter/foundation.dart';

// Tracks which goals are currently being decomposed by any provider so the
// UI can show a loading indicator without blocking navigation or capture flow.
class DecompositionState extends ChangeNotifier {
  final _inFlight = <String>{};

  bool isDecomposing(String goalId) => _inFlight.contains(goalId);

  void begin(String goalId) {
    _inFlight.add(goalId);
    notifyListeners();
  }

  void end(String goalId) {
    _inFlight.remove(goalId);
    notifyListeners();
  }
}
