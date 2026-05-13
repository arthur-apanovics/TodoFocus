import 'package:flutter/foundation.dart';

// Tracks which goals are currently being decomposed by any provider so the
// UI can show a loading indicator without blocking navigation or capture flow.
// Also tracks goals where the LLM was attempted but fell back to keyword
// templates, so the goal detail screen can surface a notification.
class DecompositionState extends ChangeNotifier {
  final _inFlight = <String>{};
  final _fallbacks = <String>{};

  bool isDecomposing(String goalId) => _inFlight.contains(goalId);
  bool hasFallback(String goalId) => _fallbacks.contains(goalId);

  void begin(String goalId) {
    _inFlight.add(goalId);
    notifyListeners();
  }

  void end(String goalId) {
    _inFlight.remove(goalId);
    notifyListeners();
  }

  // Called when an LLM was configured but failed — keyword templates were used.
  void fail(String goalId) {
    _fallbacks.add(goalId);
    notifyListeners();
  }

  void clearFallback(String goalId) {
    if (_fallbacks.remove(goalId)) notifyListeners();
  }
}
