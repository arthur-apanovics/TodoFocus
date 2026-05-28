import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/enums.dart';
import '../models/goal.dart';
import '../services/goal_repository.dart';
import '../services/goal_service.dart';
import '../services/settings/llm_profile.dart';
import '../services/settings/llm_settings_service.dart';
import 'widgets/icon_catalog.dart';

/// "Generation" half of the LLM settings split.
///
/// Owns the **content** the model produces — system prompt, difficulty
/// subtask-count ranges, and the goal-icon toggle. The **connection** half
/// (URL/model/API key/temperature/timeout/debug) lives in
/// [LlmConnectionScreen]. Both edit the same underlying
/// [OpenAiCompatibleProfile]; each screen only writes back its own subset by
/// merging the draft via [OpenAiCompatibleProfile.copyWith], so changes made
/// on the other screen aren't clobbered.
class LlmGenerationScreen extends StatefulWidget {
  const LlmGenerationScreen({super.key});

  @override
  State<LlmGenerationScreen> createState() => _LlmGenerationScreenState();
}

class _LlmGenerationScreenState extends State<LlmGenerationScreen> {
  late bool _generateEmojis;
  late OpenAiCompatibleProfile _draft;

  @override
  void initState() {
    super.initState();
    final service = context.read<LlmSettingsService>();
    _generateEmojis = service.generateEmojis;
    _draft = service.openAiProfile;
  }

  Future<void> _save() async {
    final service = context.read<LlmSettingsService>();
    final wasEmojisEnabled = service.generateEmojis;

    await service.setGenerateEmojis(_generateEmojis);
    // Only write back generation settings when an OpenAI-compatible profile is
    // active — Anthropic profiles don't carry these fields and saving here would
    // unexpectedly switch the active profile type back to OpenAI.
    if (service.activeProfile is OpenAiCompatibleProfile) {
      // Re-read the latest connection fields before saving so that a tweak made
      // on the Connection screen since this screen opened isn't overwritten.
      final latest = service.openAiProfile;
      await service.setProfile(latest.copyWith(
        systemPrompt: _draft.systemPrompt,
        easyMin: _draft.easyMin,
        easyMax: _draft.easyMax,
        hardMin: _draft.hardMin,
        hardMax: _draft.hardMax,
        impossibleMin: _draft.impossibleMin,
        impossibleMax: _draft.impossibleMax,
      ));
    }
    if (!mounted) return;

    // When emoji generation is newly switched on, offer to backfill existing
    // goals that don't have an icon yet.
    if (!wasEmojisEnabled && _generateEmojis) {
      await _offerBulkEmojiGeneration(service);
      if (!mounted) return;
    }
    Navigator.pop(context);
  }

  Future<void> _offerBulkEmojiGeneration(LlmSettingsService service) async {
    final repo = context.read<GoalRepository>();
    final goalsWithoutEmoji = repo.all
        .where((g) =>
            g.emoji == null &&
            g.status != GoalStatus.inbox &&
            g.status != GoalStatus.archived)
        .cast<Goal>()
        .toList();

    if (goalsWithoutEmoji.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Generate emojis for existing goals?'),
        content: Text(
          'You have ${goalsWithoutEmoji.length} goal${goalsWithoutEmoji.length == 1 ? '' : 's'} '
          'without an icon. Generate one for each now?\n\n'
          'This sends a single request and runs in the background.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Generate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _runBulkGeneration(service, goalsWithoutEmoji);
  }

  void _runBulkGeneration(LlmSettingsService service, List<Goal> goals) {
    final client = service.buildClient();
    if (client == null) return;
    final goalService = context.read<GoalService>();
    final titles = goals.map((g) => g.title).toList();
    final ids = goals.map((g) => g.goalId).toList();

    final names = iconByName.keys.toList();
    client.suggestIconBulk(titles, names).then((emojis) {
      final batch = <String, String>{};
      for (var i = 0; i < ids.length && i < emojis.length; i++) {
        final emoji = emojis[i];
        if (emoji != null) batch[ids[i]] = emoji;
      }
      if (batch.isNotEmpty) goalService.bulkSetEmojis(batch);
    }).catchError((_) {});
  }

  void _restoreDefaultPrompt() {
    setState(() {
      _draft = _draft.copyWith(
        systemPrompt: OpenAiCompatibleProfile.defaultSystemPrompt,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Generation'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader(label: 'Preferences'),
          SwitchListTile(
            title: const Text('Generate goal icons'),
            subtitle: const Text(
              'Adds a visual icon to each goal using AI',
            ),
            value: _generateEmojis,
            onChanged: (v) => setState(() => _generateEmojis = v),
          ),
          const Divider(height: 1),
          _SectionHeader(label: 'Goal generation prompt'),
          _PromptSection(
            helper: 'Used when a new goal is broken into subtasks.',
            text: _draft.systemPrompt,
            isDefault: _draft.systemPrompt ==
                OpenAiCompatibleProfile.defaultSystemPrompt,
            onRestore: _restoreDefaultPrompt,
            onChanged: (v) =>
                setState(() => _draft = _draft.copyWith(systemPrompt: v)),
          ),
          const Divider(height: 1),
          _DifficultyRangesSection(
            profile: _draft,
            onChanged: (p) => setState(() => _draft = p),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets (private to this screen)
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}

class _PromptSection extends StatefulWidget {
  final String helper;
  final String text;
  final bool isDefault;
  final VoidCallback onRestore;
  final ValueChanged<String> onChanged;

  const _PromptSection({
    required this.helper,
    required this.text,
    required this.isDefault,
    required this.onRestore,
    required this.onChanged,
  });

  @override
  State<_PromptSection> createState() => _PromptSectionState();
}

class _PromptSectionState extends State<_PromptSection> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
  }

  @override
  void didUpdateWidget(_PromptSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Externally-driven text changes (e.g. "Restore default") must overwrite
    // the controller, but only when the value actually differs — comparing
    // against the controller's own value avoids cursor-jump on every keystroke.
    if (widget.text != _controller.text) {
      _controller.text = widget.text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  widget.helper,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              if (!widget.isDefault)
                TextButton(
                  onPressed: widget.onRestore,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Restore default'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            maxLines: null,
            minLines: 3,
            textCapitalization: TextCapitalization.sentences,
            onChanged: widget.onChanged,
          ),
        ],
      ),
    );
  }
}

class _DifficultyRangesSection extends StatefulWidget {
  final OpenAiCompatibleProfile profile;
  final ValueChanged<OpenAiCompatibleProfile> onChanged;

  const _DifficultyRangesSection({
    required this.profile,
    required this.onChanged,
  });

  @override
  State<_DifficultyRangesSection> createState() =>
      _DifficultyRangesSectionState();
}

class _DifficultyRangesSectionState extends State<_DifficultyRangesSection> {
  late final TextEditingController _easyMinCtrl;
  late final TextEditingController _easyMaxCtrl;
  late final TextEditingController _hardMinCtrl;
  late final TextEditingController _hardMaxCtrl;
  late final TextEditingController _impossibleMinCtrl;
  late final TextEditingController _impossibleMaxCtrl;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _easyMinCtrl = TextEditingController(text: '${p.easyMin}');
    _easyMaxCtrl = TextEditingController(text: '${p.easyMax}');
    _hardMinCtrl = TextEditingController(text: '${p.hardMin}');
    _hardMaxCtrl = TextEditingController(text: '${p.hardMax}');
    _impossibleMinCtrl = TextEditingController(text: '${p.impossibleMin}');
    _impossibleMaxCtrl = TextEditingController(text: '${p.impossibleMax}');
  }

  @override
  void dispose() {
    _easyMinCtrl.dispose();
    _easyMaxCtrl.dispose();
    _hardMinCtrl.dispose();
    _hardMaxCtrl.dispose();
    _impossibleMinCtrl.dispose();
    _impossibleMaxCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    final p = widget.profile;
    widget.onChanged(p.copyWith(
      easyMin: int.tryParse(_easyMinCtrl.text) ?? p.easyMin,
      easyMax: int.tryParse(_easyMaxCtrl.text) ?? p.easyMax,
      hardMin: int.tryParse(_hardMinCtrl.text) ?? p.hardMin,
      hardMax: int.tryParse(_hardMaxCtrl.text) ?? p.hardMax,
      impossibleMin: int.tryParse(_impossibleMinCtrl.text) ?? p.impossibleMin,
      impossibleMax: int.tryParse(_impossibleMaxCtrl.text) ?? p.impossibleMax,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Subtask count by difficulty',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Min and max subtasks the LLM generates for each difficulty level.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          _DifficultyRangeRow(
            label: 'Easy',
            minCtrl: _easyMinCtrl,
            maxCtrl: _easyMaxCtrl,
            onChanged: _notify,
          ),
          const SizedBox(height: 8),
          _DifficultyRangeRow(
            label: 'Hard',
            minCtrl: _hardMinCtrl,
            maxCtrl: _hardMaxCtrl,
            onChanged: _notify,
          ),
          const SizedBox(height: 8),
          _DifficultyRangeRow(
            label: 'Impossible',
            minCtrl: _impossibleMinCtrl,
            maxCtrl: _impossibleMaxCtrl,
            onChanged: _notify,
          ),
        ],
      ),
    );
  }
}

class _DifficultyRangeRow extends StatelessWidget {
  final String label;
  final TextEditingController minCtrl;
  final TextEditingController maxCtrl;
  final VoidCallback onChanged;

  const _DifficultyRangeRow({
    required this.label,
    required this.minCtrl,
    required this.maxCtrl,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const fieldWidth = 64.0;
    const inputDecoration = InputDecoration(
      border: OutlineInputBorder(),
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        SizedBox(
          width: fieldWidth,
          child: TextField(
            controller: minCtrl,
            keyboardType: TextInputType.number,
            decoration: inputDecoration,
            onChanged: (_) => onChanged(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '–',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        SizedBox(
          width: fieldWidth,
          child: TextField(
            controller: maxCtrl,
            keyboardType: TextInputType.number,
            decoration: inputDecoration,
            onChanged: (_) => onChanged(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text(
            'subtasks',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }
}
