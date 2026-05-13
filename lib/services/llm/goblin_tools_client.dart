import 'dart:convert';
import 'package:http/http.dart' as http;
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
  Future<List<String>> decompose(String title, {String? description}) async {
    final response = await _http
        .post(
          Uri.parse(_url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'Text': title,
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
