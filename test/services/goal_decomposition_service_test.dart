import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/models/enums.dart';
import 'package:todo_app/services/decomposition_state.dart';
import 'package:todo_app/services/goal_decomposition_service.dart';
import 'package:todo_app/services/llm/decomposed_step.dart';
import 'package:todo_app/services/llm/decomposition_client.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _FakeDecompositionClient implements DecompositionClient {
  GoalDifficulty? capturedDifficulty;
  List<String>? capturedEstimateInputs;
  final List<DecomposedStep> _responses;
  final List<int?>? _estimateResponses;
  final bool shouldThrow;

  _FakeDecompositionClient({
    List<DecomposedStep>? responses,
    List<int?>? estimateResponses,
    this.shouldThrow = false,
  })  : _responses = responses ??
            const [
              DecomposedStep('step 1', estimatedMinutes: 10),
              DecomposedStep('step 2', estimatedMinutes: 15),
              DecomposedStep('step 3', estimatedMinutes: 20),
            ],
        _estimateResponses = estimateResponses;

  @override
  Future<List<DecomposedStep>> decompose(
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
  Future<List<DecomposedStep>> addSteps(
    String title, {
    String? description,
    String? userPrompt,
    GoalDifficulty? difficulty,
    List<String>? existingPendingSteps,
    List<String>? existingCompletedSteps,
  }) async => const [DecomposedStep('new step 1', estimatedMinutes: 5)];

  @override
  Future<List<DecomposedStep>> modify(
    String title, {
    String? description,
    String? additionalInstructions,
    GoalDifficulty? difficulty,
    required List<String> pendingSteps,
    List<String>? completedSteps,
  }) async =>
      pendingSteps.map((d) => DecomposedStep(d)).toList();

  @override
  Future<List<DecomposedStep>> breakdown(
    String subtaskDescription, {
    String? additionalInstructions,
    GoalDifficulty? difficulty,
    String? goalTitle,
    String? goalDescription,
    List<String>? completedSteps,
    List<String>? otherPendingSteps,
  }) async => const [DecomposedStep('sub-step 1', estimatedMinutes: 5)];

  @override
  Future<List<int?>> estimate(
    List<String> descriptions, {
    String? goalTitle,
    String? goalDescription,
  }) async {
    if (shouldThrow) throw Exception('LLM error');
    capturedEstimateInputs = List.of(descriptions);
    return _estimateResponses ?? List<int?>.generate(descriptions.length, (i) => (i + 1) * 5);
  }

  @override
  Future<String?> rewordSubtask(
    String description, {
    required String goalTitle,
    String? goalNotes,
    required int urgencyLevel,
    required String promptTemplate,
  }) async =>
      shouldThrow ? throw Exception('LLM error') : 'Do it now!';

  @override
  Future<String?> suggestIcon(String goalTitle, List<String> iconNames) async =>
      null;

  @override
  Future<List<String?>> suggestIconBulk(
          List<String> goalTitles, List<String> iconNames) async =>
      List.filled(goalTitles.length, null);
}

Future<List<DecomposedStep>> _runBackground(
  GoalDecompositionService service,
  String title, {
  String? description,
  GoalDifficulty difficulty = GoalDifficulty.easy,
  DecompositionState? state,
}) async {
  state ??= DecompositionState();
  List<DecomposedStep>? result;
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
      final fake = _FakeDecompositionClient(
        responses: const [
          DecomposedStep('A', estimatedMinutes: 7),
          DecomposedStep('B', estimatedMinutes: 14),
        ],
      );
      final service = GoalDecompositionService(client: fake);

      final results = await _runBackground(service, 'Some goal');

      expect(results.map((s) => s.description).toList(), ['A', 'B']);
      expect(results.map((s) => s.estimatedMinutes).toList(), [7, 14]);
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

    test('keyword scaffolds have null estimates', () async {
      final service = GoalDecompositionService();
      final results = await _runBackground(service, 'Fix the bug');
      expect(results.every((s) => s.estimatedMinutes == null), isTrue);
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
      expect(
        steps.any((s) => s.description.toLowerCase().contains('resource')),
        isTrue,
      );
    });

    test('"Build X" produces build-oriented steps', () async {
      final steps = await _runBackground(service, 'Build a portfolio site');
      expect(
        steps.any((s) =>
            s.description.toLowerCase().contains('implement') ||
            s.description.toLowerCase().contains('require')),
        isTrue,
      );
    });

    test('"Fix X" produces debugging-oriented steps', () async {
      final steps = await _runBackground(service, 'Fix the login bug');
      expect(
        steps.any((s) =>
            s.description.toLowerCase().contains('root cause') ||
            s.description.toLowerCase().contains('reproduce')),
        isTrue,
      );
    });

    test('unrecognised title falls back to generic steps', () async {
      final steps = await _runBackground(service, 'xyzzy random nonsense 42');
      expect(steps.first.description.toLowerCase(), contains('done'));
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
      final fake = _FakeDecompositionClient(
        responses: const [
          DecomposedStep('A', estimatedMinutes: 10),
          DecomposedStep('B', estimatedMinutes: 20),
        ],
      );
      final service = GoalDecompositionService(client: fake);

      final result = await service.redecomposeSubtasks('Do something');

      expect(result?.map((s) => s.description).toList(), ['A', 'B']);
      expect(result?.map((s) => s.estimatedMinutes).toList(), [10, 20]);
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

  // -------------------------------------------------------------------------
  // estimateMinutes (re-estimate flow)
  // -------------------------------------------------------------------------

  group('GoalDecompositionService.estimateMinutes', () {
    test('forwards descriptions to the client', () async {
      final fake = _FakeDecompositionClient();
      final service = GoalDecompositionService(client: fake);

      await service.estimateMinutes(['First step', 'Second step']);

      expect(fake.capturedEstimateInputs, ['First step', 'Second step']);
    });

    test('returns the client estimates on success', () async {
      final fake = _FakeDecompositionClient(
        estimateResponses: const [42, 17],
      );
      final service = GoalDecompositionService(client: fake);

      final result = await service.estimateMinutes(['A', 'B']);

      expect(result, [42, 17]);
    });

    test('returns null when no client is configured', () async {
      final service = GoalDecompositionService();
      expect(await service.estimateMinutes(['A']), isNull);
    });

    test('returns null when the client throws', () async {
      final service = GoalDecompositionService(
        client: _FakeDecompositionClient(shouldThrow: true),
      );
      expect(await service.estimateMinutes(['A']), isNull);
    });

    test('returns empty list immediately for empty input', () async {
      final fake = _FakeDecompositionClient();
      final service = GoalDecompositionService(client: fake);

      final result = await service.estimateMinutes([]);

      expect(result, isEmpty);
      // Client must not be invoked for an empty input.
      expect(fake.capturedEstimateInputs, isNull);
    });
  });
}
