import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/models/enums.dart';
import 'package:todo_app/services/decomposition_state.dart';
import 'package:todo_app/services/goal_decomposition_service.dart';
import 'package:todo_app/services/llm/decomposition_client.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _FakeDecompositionClient implements DecompositionClient {
  GoalDifficulty? capturedDifficulty;
  final List<String> _responses;
  final bool shouldThrow;

  _FakeDecompositionClient({
    List<String> responses = const ['step 1', 'step 2', 'step 3'],
    this.shouldThrow = false,
  }) : _responses = responses;

  @override
  Future<List<String>> decompose(
    String title, {
    String? description,
    String? additionalInstructions,
    GoalDifficulty? difficulty,
    List<String>? completedSteps,
  }) async {
    if (shouldThrow) throw Exception('LLM error');
    capturedDifficulty = difficulty;
    return List.of(_responses);
  }

  @override
  Future<List<String>> breakdown(
    String subtaskDescription, {
    String? additionalInstructions,
    GoalDifficulty? difficulty,
  }) async => ['sub-step 1'];
}

Future<List<String>> _runBackground(
  GoalDecompositionService service,
  String title, {
  String? description,
  GoalDifficulty difficulty = GoalDifficulty.easy,
  DecompositionState? state,
}) async {
  state ??= DecompositionState();
  List<String>? result;
  await service.decomposeInBackground(
    goalId: 'g1',
    title: title,
    description: description,
    onResult: (d) => result = d,
    state: state,
    difficulty: difficulty,
  );
  return result!;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // decomposeInBackground — LLM client path
  // -------------------------------------------------------------------------

  group('GoalDecompositionService.decomposeInBackground — with LLM client', () {
    test('forwards difficulty to the decomposition client', () async {
      final fake = _FakeDecompositionClient();
      final service = GoalDecompositionService(client: fake);

      await _runBackground(service, 'Learn Dart', difficulty: GoalDifficulty.hard);

      expect(fake.capturedDifficulty, GoalDifficulty.hard);
    });

    test('delivers the client responses via onResult', () async {
      final fake = _FakeDecompositionClient(responses: ['A', 'B', 'C']);
      final service = GoalDecompositionService(client: fake);

      final results = await _runBackground(service, 'Some goal');

      expect(results, ['A', 'B', 'C']);
    });

    test('clears the in-flight state after the call completes', () async {
      final service = GoalDecompositionService(client: _FakeDecompositionClient());
      final state = DecompositionState();

      await _runBackground(service, 'Do something', state: state);

      expect(state.isDecomposing('g1'), isFalse);
    });

    test('falls back to keyword templates and marks fallback when client throws',
        () async {
      final fake = _FakeDecompositionClient(shouldThrow: true);
      final service = GoalDecompositionService(client: fake);
      final state = DecompositionState();

      final results = await _runBackground(
        service,
        'Learn Python',
        state: state,
      );

      expect(results, isNotEmpty);
      expect(state.hasFallback('g1'), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // decomposeInBackground — keyword-only path (no client)
  // -------------------------------------------------------------------------

  group('GoalDecompositionService.decomposeInBackground — keyword-only', () {
    test('delivers keyword templates without marking in-flight state', () async {
      final service = GoalDecompositionService();
      final state = DecompositionState();
      bool wasInFlight = false;

      await service.decomposeInBackground(
        goalId: 'g1',
        title: 'Learn Python',
        onResult: (_) => wasInFlight = state.isDecomposing('g1'),
        state: state,
      );

      expect(wasInFlight, isFalse);
    });

    test('delivers a non-empty list of steps', () async {
      final service = GoalDecompositionService();
      final results = await _runBackground(service, 'Fix the bug');
      expect(results, isNotEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Intent detection (tested indirectly via keyword-only mode)
  // -------------------------------------------------------------------------

  group('GoalDecompositionService intent detection', () {
    late GoalDecompositionService service;

    setUp(() => service = GoalDecompositionService()); // no client

    test('"Learn X" produces learning-oriented steps', () async {
      final steps = await _runBackground(service, 'Learn Swift');
      expect(steps.any((s) => s.toLowerCase().contains('resource')), isTrue);
    });

    test('"Build X" produces build-oriented steps', () async {
      final steps = await _runBackground(service, 'Build a portfolio site');
      expect(
        steps.any((s) =>
            s.toLowerCase().contains('implement') ||
            s.toLowerCase().contains('require')),
        isTrue,
      );
    });

    test('"Fix X" produces debugging-oriented steps', () async {
      final steps = await _runBackground(service, 'Fix the login bug');
      expect(
        steps.any((s) =>
            s.toLowerCase().contains('root cause') ||
            s.toLowerCase().contains('reproduce')),
        isTrue,
      );
    });

    test('unrecognised title falls back to generic steps', () async {
      final steps = await _runBackground(service, 'xyzzy random nonsense 42');
      expect(steps.first.toLowerCase(), contains('done'));
    });
  });

  // -------------------------------------------------------------------------
  // redecomposeSubtasks
  // -------------------------------------------------------------------------

  group('GoalDecompositionService.redecomposeSubtasks', () {
    test('forwards difficulty to the client', () async {
      final fake = _FakeDecompositionClient();
      final service = GoalDecompositionService(client: fake);

      await service.redecomposeSubtasks(
        'Build an API',
        difficulty: GoalDifficulty.impossible,
      );

      expect(fake.capturedDifficulty, GoalDifficulty.impossible);
    });

    test('returns the client responses on success', () async {
      final fake = _FakeDecompositionClient(responses: ['A', 'B']);
      final service = GoalDecompositionService(client: fake);

      final result = await service.redecomposeSubtasks('Do something');

      expect(result, ['A', 'B']);
    });

    test('returns null when no client is configured', () async {
      final service = GoalDecompositionService();
      expect(await service.redecomposeSubtasks('Some goal'), isNull);
    });

    test('returns null when the client throws', () async {
      final service = GoalDecompositionService(
        client: _FakeDecompositionClient(shouldThrow: true),
      );
      expect(await service.redecomposeSubtasks('Some goal'), isNull);
    });
  });
}
