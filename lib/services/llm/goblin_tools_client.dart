import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/enums.dart';
import 'decomposition_client.dart';

// Goblin Tools Magic ToDo API — https://goblin.tools
// No API key required. Spiciness (1–3) controls the number of subtasks returned.
// Description is ignored; the API only accepts the task title.
class GoblinToolsDecompositionClient implements DecompositionClient {
  static const _url = 'https://goblin.tools/api/todo/';

  final int spiciness;
  final http.Client _http;

  GoblinToolsDecompositionClient({
    required this.spiciness,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  @override
  Future<List<String>> decompose(
    String title, {
    String? description,
    String? additionalInstructions,
    GoalDifficulty? difficulty,
  }) =>
      _post(additionalInstructions ?? title, spiciness);

  // Breakdown reuses the same endpoint with spiciness=1 — the API has no
  // separate "break this subtask down further" mode, so we just request the
  // minimum granularity to get a small number of fine-grained steps.
  @override
  Future<List<String>> breakdown(String subtaskDescription, {String? additionalInstructions}) =>
      _post(additionalInstructions ?? subtaskDescription, 1);

  Future<List<String>> _post(String text, int spiciness) async {
    final response = await _http
        .post(
          Uri.parse(_url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'Text': text,
            'Spiciness': spiciness,
            'Ancestors': [],
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Goblin Tools request failed: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is List) return decoded.cast<String>();
    throw const FormatException('Unexpected Goblin Tools response format');
  }
}
