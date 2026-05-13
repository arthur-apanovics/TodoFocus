import 'package:flutter/foundation.dart';

// Tracks which goals are currently being decomposed by any provider so the
// UI can show a loading indicator without blocking navigation or capture flow.
// Also tracks goals where the LLM was attempted but fell back to keyword
// templates, so the goal detail screen can surface a notification.
class DecompositionState extends ChangeNotifier {
  final _inFlight = <String>{};
  // Maps goalId → error message (null when no detail is available).
  final _fallbacks = <String, String?>{};

  bool isDecomposing(String goalId) => _inFlight.contains(goalId);
  bool hasFallback(String goalId) => _fallbacks.containsKey(goalId);
  String? fallbackError(String goalId) => _fallbacks[goalId];

  void begin(String goalId) {
    _inFlight.add(goalId);
    notifyListeners();
  }

  void end(String goalId) {
    _inFlight.remove(goalId);
    notifyListeners();
  }

  // Called when an LLM was configured but failed — keyword templates were used.
  // [errorMessage] is the raw exception string; stored for debug display.
  void fail(String goalId, {String? errorMessage}) {
    _fallbacks[goalId] = errorMessage;
    notifyListeners();
  }

  void clearFallback(String goalId) {
    if (_fallbacks.remove(goalId) != null) notifyListeners();
  }
}
