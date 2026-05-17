import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/models/enums.dart';
import 'package:todo_app/services/llm/llm_client.dart';
import 'package:todo_app/services/llm/llm_config.dart';
import 'package:todo_app/services/llm/openai_decomposition_client.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _FakeLlmClient extends LlmClient {
  String? capturedSystemPrompt;
  String? capturedUserPrompt;
  Map<String, dynamic>? capturedSchema;
  final String _response;

  _FakeLlmClient({String response = '["step 1", "step 2", "step 3"]'})
    : _response = response,
      super(const LlmConfig(baseUrl: '', model: ''));

  @override
  Future<String> complete(
    String systemPrompt,
    String userPrompt, {
    Map<String, dynamic>? responseSchema,
  }) async {
    capturedSystemPrompt = systemPrompt;
    capturedUserPrompt = userPrompt;
    capturedSchema = responseSchema;
    return _response;
  }
}

OpenAiDecompositionClient _client(_FakeLlmClient llm, {
  int easyMin = 3,
  int easyMax = 6,
  int hardMin = 10,
  int hardMax = 20,
  int impossibleMin = 30,
  int impossibleMax = 50,
}) => OpenAiDecompositionClient(
  llm,
  easyMin: easyMin,
  easyMax: easyMax,
  hardMin: hardMin,
  hardMax: hardMax,
  impossibleMin: impossibleMin,
  impossibleMax: impossibleMax,
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('OpenAiDecompositionClient.decompose — difficulty bounds', () {
    test('null difficulty uses easy bounds (3–6)', () async {
      final llm = _FakeLlmClient();
      await _client(llm).decompose('Learn Swift');
      expect(llm.capturedSchema!['minItems'], 3);
      expect(llm.capturedSchema!['maxItems'], 6);
      expect(llm.capturedSystemPrompt, contains('3 and 6'));
    });

    test('easy difficulty uses easy bounds (3–6)', () async {
      final llm = _FakeLlmClient();
      await _client(llm).decompose('Learn Swift', difficulty: GoalDifficulty.easy);
      expect(llm.capturedSchema!['minItems'], 3);
      expect(llm.capturedSchema!['maxItems'], 6);
      expect(llm.capturedSystemPrompt, contains('3 and 6'));
    });

    test('hard difficulty uses hard bounds (10–20)', () async {
      final llm = _FakeLlmClient(
        response:
            '["s1","s2","s3","s4","s5","s6","s7","s8","s9","s10"]',
      );
      await _client(llm).decompose('Build a portfolio', difficulty: GoalDifficulty.hard);
      expect(llm.capturedSchema!['minItems'], 10);
      expect(llm.capturedSchema!['maxItems'], 20);
      expect(llm.capturedSystemPrompt, contains('10 and 20'));
    });

    test('impossible difficulty uses impossible bounds (30–50)', () async {
      final items = List.generate(30, (i) => '"s${i + 1}"').join(',');
      final llm = _FakeLlmClient(response: '[$items]');
      await _client(llm).decompose('Impossible goal', difficulty: GoalDifficulty.impossible);
      expect(llm.capturedSchema!['minItems'], 30);
      expect(llm.capturedSchema!['maxItems'], 50);
      expect(llm.capturedSystemPrompt, contains('30 and 50'));
    });

    test('custom ranges override the defaults', () async {
      final llm = _FakeLlmClient();
      await _client(llm, easyMin: 5, easyMax: 8).decompose(
        'Some goal',
        difficulty: GoalDifficulty.easy,
      );
      expect(llm.capturedSchema!['minItems'], 5);
      expect(llm.capturedSchema!['maxItems'], 8);
      expect(llm.capturedSystemPrompt, contains('5 and 8'));
    });
  });

  group('OpenAiDecompositionClient.decompose — response parsing', () {
    test('parses a plain JSON array', () async {
      final llm = _FakeLlmClient(response: '["step A", "step B"]');
      final result = await _client(llm).decompose('Do something');
      expect(result, ['step A', 'step B']);
    });

    test('strips markdown fences before parsing', () async {
      final llm = _FakeLlmClient(
        response: '```json\n["step A", "step B"]\n```',
      );
      final result = await _client(llm).decompose('Do something');
      expect(result, ['step A', 'step B']);
    });

    test('extracts an array embedded in leading prose', () async {
      final llm = _FakeLlmClient(
        response: 'Sure, here are the steps:\n["step A", "step B"]',
      );
      final result = await _client(llm).decompose('Do something');
      expect(result, ['step A', 'step B']);
    });
  });

  group('OpenAiDecompositionClient.decompose — completedSteps', () {
    test('appends completed steps to the user prompt when provided', () async {
      final llm = _FakeLlmClient();
      await _client(llm).decompose(
        'Build a portfolio',
        completedSteps: ['Choose tech stack', 'Set up repo'],
      );
      expect(llm.capturedUserPrompt, contains('Steps already completed'));
      expect(llm.capturedUserPrompt, contains('1. Choose tech stack'));
      expect(llm.capturedUserPrompt, contains('2. Set up repo'));
    });

    test('does not append completed steps section when list is empty', () async {
      final llm = _FakeLlmClient();
      await _client(llm).decompose('Build a portfolio', completedSteps: []);
      expect(llm.capturedUserPrompt, isNot(contains('Steps already completed')));
    });

    test('does not append completed steps section when null', () async {
      final llm = _FakeLlmClient();
      await _client(llm).decompose('Build a portfolio');
      expect(llm.capturedUserPrompt, isNot(contains('Steps already completed')));
    });
  });

  group('OpenAiDecompositionClient.breakdown', () {
    test('uses fixed 1–3 schema when no difficulty is provided', () async {
      final llm = _FakeLlmClient(response: '["sub-step 1"]');
      await _client(llm).breakdown('An overwhelming subtask');
      expect(llm.capturedSchema!['minItems'], 1);
      expect(llm.capturedSchema!['maxItems'], 3);
    });

    test('uses difficulty-based schema when difficulty is provided (easy)', () async {
      final llm = _FakeLlmClient(response: '["sub-step 1", "sub-step 2"]');
      await _client(llm, easyMin: 3, easyMax: 6).breakdown(
        'An overwhelming subtask',
        difficulty: GoalDifficulty.easy,
      );
      expect(llm.capturedSchema!['minItems'], 3);
      expect(llm.capturedSchema!['maxItems'], 6);
    });

    test('uses difficulty-based schema when difficulty is provided (hard)', () async {
      final items = List.generate(10, (i) => '"s${i + 1}"').join(',');
      final llm = _FakeLlmClient(response: '[$items]');
      await _client(llm, hardMin: 10, hardMax: 20).breakdown(
        'An overwhelming subtask',
        difficulty: GoalDifficulty.hard,
      );
      expect(llm.capturedSchema!['minItems'], 10);
      expect(llm.capturedSchema!['maxItems'], 20);
    });
  });
}
