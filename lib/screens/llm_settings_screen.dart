import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../models/enums.dart';
import '../models/goal.dart';
import '../services/goal_repository.dart';
import '../services/goal_service.dart';
import '../services/settings/llm_profile.dart';
import '../services/settings/llm_settings_service.dart';
import 'widgets/icon_catalog.dart';

// LLM configuration screen. Add new profile types by:
//   1. Adding a subtype in llm_profile.dart
//   2. Adding its name to _presets
//   3. Adding a case in _buildForm and handling in initState / _onPresetChanged

// ---------------------------------------------------------------------------
// OpenRouter model data + fetch
// ---------------------------------------------------------------------------

class _OrModel {
  final String id;
  final String name;

  /// True when both prompt and completion pricing are "0" — no billing needed.
  final bool isFree;

  const _OrModel({required this.id, required this.name, required this.isFree});
}

Future<List<_OrModel>> _fetchOrModels() async {
  final res = await http
      .get(Uri.parse('https://openrouter.ai/api/v1/models'))
      .timeout(const Duration(seconds: 10));
  if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  final models = (data['data'] as List)
      .whereType<Map<String, dynamic>>()
      .where((m) {
        // Keep models whose output includes text (covers text->text,
        // text+image->text, and router models like openrouter/auto whose
        // modality is text+image+…->text+image).
        // Models with no architecture field (OpenRouter meta-models) are kept.
        final arch = m['architecture'] as Map<String, dynamic>?;
        final modality = arch?['modality'] as String?;
        if (modality == null) return true;
        final outputPart = modality.contains('->')
            ? modality.split('->').last
            : modality;
        return outputPart.split('+').contains('text');
      })
      .map((m) {
        final p = (m['pricing'] as Map<String, dynamic>?) ?? {};
        final isFree = p['prompt'] == '0' && p['completion'] == '0';
        final id = m['id'] as String;
        return _OrModel(
          id: id,
          name: (m['name'] as String?)?.isNotEmpty == true
              ? m['name'] as String
              : id,
          isFree: isFree,
        );
      })
      .toList();
  // Free first, then alphabetical within each group.
  models.sort((a, b) {
    if (a.isFree != b.isFree) return a.isFree ? -1 : 1;
    return a.name.compareTo(b.name);
  });
  return models;
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class LlmSettingsScreen extends StatefulWidget {
  const LlmSettingsScreen({super.key});

  @override
  State<LlmSettingsScreen> createState() => _LlmSettingsScreenState();
}

class _LlmSettingsScreenState extends State<LlmSettingsScreen> {
  static const _presets = ['OpenAI Compatible', 'OpenRouter', 'Goblin Tools'];

  late bool _generateEmojis;
  late bool _debugMode;

  // Each profile type has its own draft so switching presets and back
  // does not discard previously entered values.
  late OpenAiCompatibleProfile _openAiDraft;
  late GoblinToolsProfile _goblinDraft;
  late String _selectedPreset;

  LlmProfile get _draft => switch (_selectedPreset) {
    'Goblin Tools' => _goblinDraft,
    _ => _openAiDraft,
  };

  // When switching to the OpenRouter preset, pre-fill the URL if it's blank.
  void _onPresetChangedWithDefaults(String preset) {
    // Always force the OpenRouter base URL — it never changes and the field is
    // hidden, so whatever the user had saved for OpenAI Compatible must not bleed through.
    if (preset == 'OpenRouter') {
      setState(() {
        _openAiDraft = _openAiDraft.copyWith(
          endpointUrl: 'https://openrouter.ai/api/v1',
        );
      });
    }
    _onPresetChanged(preset);
  }

  @override
  void initState() {
    super.initState();
    final service = context.read<LlmSettingsService>();
    _generateEmojis = service.generateEmojis;
    _debugMode = service.debugMode;

    // Each draft is initialised from its own stored slot, so switching active
    // preset and saving never wipes the other type's configuration.
    _openAiDraft = service.openAiProfile;
    _goblinDraft = service.goblinProfile;

    _selectedPreset = switch (service.activeProfile) {
      GoblinToolsProfile() => 'Goblin Tools',
      OpenAiCompatibleProfile(endpointUrl: final url)
          when url.contains('openrouter.ai') =>
        'OpenRouter',
      _ => 'OpenAI Compatible',
    };
  }

  bool get _isGoblinTools => _selectedPreset == 'Goblin Tools';

  // Effective emoji setting — always false for Goblin Tools since it has no
  // emoji endpoint. The in-memory flag is preserved so switching back to an
  // OpenAI-compatible preset restores whatever the user had before.
  bool get _effectiveGenerateEmojis => _isGoblinTools ? false : _generateEmojis;

  void _onPresetChanged(String preset) {
    setState(() { _selectedPreset = preset; });
  }

  Future<void> _save() async {
    final service = context.read<LlmSettingsService>();
    final wasEmojisEnabled = service.generateEmojis;
    final nowEmojisEnabled = _effectiveGenerateEmojis;

    await service.setGenerateEmojis(nowEmojisEnabled);
    await service.setDebugMode(_debugMode);
    await service.setProfile(_draft);
    if (!mounted) return;

    // When emoji generation is newly switched on, offer to backfill existing goals.
    if (!wasEmojisEnabled && nowEmojisEnabled) {
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
          'without an emoji. Generate one for each now?\n\n'
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

    // Run bulk generation in background — no await, no loading indicator.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LLM Configuration'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ── Preferences ──────────────────────────────────────────────────
          _SectionHeader(label: 'Preferences'),
          SwitchListTile(
            title: const Text('Generate goal emojis'),
            subtitle: Text(
              _isGoblinTools
                  ? 'Not supported by Goblin Tools'
                  : 'Adds a visual emoji to each goal using AI',
            ),
            value: _effectiveGenerateEmojis,
            // Null onChanged disables the switch visually when Goblin Tools active
            onChanged: _isGoblinTools
                ? null
                : (v) => setState(() { _generateEmojis = v; }),
          ),
          const Divider(height: 1),
          // ── Technical ────────────────────────────────────────────────────
          _SectionHeader(label: 'Technical'),
          _PresetTile(
            selected: _selectedPreset,
            options: _presets,
            onChanged: _onPresetChangedWithDefaults,
          ),
          const Divider(height: 1),
          _buildForm(),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Debug mode'),
            subtitle: const Text(
              'Show full error details in failure notifications',
            ),
            value: _debugMode,
            onChanged: (v) => setState(() { _debugMode = v; }),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() => switch (_selectedPreset) {
    'Goblin Tools' => _GoblinToolsForm(
      profile: _goblinDraft,
      onChanged: (p) => setState(() { _goblinDraft = p; }),
    ),
    'OpenRouter' => _OpenAiCompatibleForm(
      profile: _openAiDraft,
      onChanged: (p) => setState(() { _openAiDraft = p; }),
      isOpenRouter: true,
    ),
    _ => _OpenAiCompatibleForm(
      profile: _openAiDraft,
      onChanged: (p) => setState(() { _openAiDraft = p; }),
    ),
  };
}

// ---------------------------------------------------------------------------
// Shared
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

class _PresetTile extends StatelessWidget {
  final String selected;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _PresetTile({
    required this.selected,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: DropdownButtonFormField<String>(
        initialValue: selected,
        decoration: const InputDecoration(
          labelText: 'Preset',
          border: OutlineInputBorder(),
        ),
        items: options
            .map((o) => DropdownMenuItem(value: o, child: Text(o)))
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// OpenAI-compatible form
// ---------------------------------------------------------------------------

class _OpenAiCompatibleForm extends StatefulWidget {
  final OpenAiCompatibleProfile profile;
  final ValueChanged<OpenAiCompatibleProfile> onChanged;
  final bool isOpenRouter;

  const _OpenAiCompatibleForm({
    required this.profile,
    required this.onChanged,
    this.isOpenRouter = false,
  });

  @override
  State<_OpenAiCompatibleForm> createState() => _OpenAiCompatibleFormState();
}

class _OpenAiCompatibleFormState extends State<_OpenAiCompatibleForm> {
  late final TextEditingController _urlController;
  late final TextEditingController _modelController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _promptController;
  late final TextEditingController _breakdownPromptController;
  bool _apiKeyVisible = false;

  // OpenRouter model list state
  List<_OrModel>? _orModels;
  bool _orLoading = false;
  String? _orError;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.profile.endpointUrl);
    _modelController = TextEditingController(text: widget.profile.modelId);
    _apiKeyController = TextEditingController(
      text: widget.profile.apiKey ?? '',
    );
    _promptController = TextEditingController(
      text: widget.profile.systemPrompt,
    );
    _breakdownPromptController = TextEditingController(
      text: widget.profile.breakdownPrompt,
    );
    if (widget.isOpenRouter) _loadOrModels();
  }

  @override
  void didUpdateWidget(_OpenAiCompatibleForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync controllers when the profile is updated externally (e.g. the preset
    // picker auto-fills the URL when switching to OpenRouter).
    if (widget.profile.endpointUrl != oldWidget.profile.endpointUrl) {
      _urlController.text = widget.profile.endpointUrl;
    }
    if (widget.profile.modelId != oldWidget.profile.modelId) {
      _modelController.text = widget.profile.modelId;
    }
    if (widget.isOpenRouter && !oldWidget.isOpenRouter) _loadOrModels();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    _promptController.dispose();
    _breakdownPromptController.dispose();
    super.dispose();
  }

  Future<void> _loadOrModels() async {
    setState(() {
      _orLoading = true;
      _orError = null;
    });
    try {
      final models = await _fetchOrModels();
      if (!mounted) return;
      // Auto-select the first free model when the current value isn't a
      // known OpenRouter model (e.g. switching from an OpenAI-compatible
      // profile that had a local model ID like 'llama3.2').
      bool autoSelected = false;
      setState(() {
        _orModels = models;
        _orLoading = false;
        final currentKnown = models.any((m) => m.id == _modelController.text);
        if (!currentKnown && models.isNotEmpty) {
          final candidate = models.firstWhere(
            (m) => m.id == 'openrouter/auto',
            orElse: () => models.firstWhere(
              (m) => m.isFree,
              orElse: () => models.first,
            ),
          );
          _modelController.text = candidate.id;
          autoSelected = true;
        }
      });
      // Call _notifyFields outside setState to avoid nested setState calls,
      // which can cause the "setState() callback returned a Future" assertion.
      if (autoSelected) _notifyFields();
    } catch (e) {
      if (mounted) {
        setState(() {
          _orError = e.toString();
          _orLoading = false;
        });
      }
    }
  }

  Future<void> _openModelPicker() async {
    if (_orModels == null) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          _ModelSearchSheet(models: _orModels!, current: _modelController.text),
    );
    if (selected != null) {
      _modelController.text = selected;
      _notifyFields();
    }
  }

  Future<List<String>> _runDecomposition(String goalTitle) =>
      widget.profile.buildClient().decompose(goalTitle);

  void _testConnection() {
    showDialog<void>(
      context: context,
      builder: (_) => _TestDialog(onTest: _runDecomposition),
    );
  }

  void _notifyFields() {
    widget.onChanged(
      widget.profile.copyWith(
        endpointUrl: _urlController.text.trim(),
        modelId: _modelController.text.trim(),
        apiKey: _apiKeyController.text.trim().isEmpty
            ? null
            : _apiKeyController.text.trim(),
        systemPrompt: _promptController.text,
        breakdownPrompt: _breakdownPromptController.text,
      ),
    );
  }

  void _restoreDefaultPrompt() {
    _promptController.text = OpenAiCompatibleProfile.defaultSystemPrompt;
    widget.onChanged(
      widget.profile.copyWith(
        systemPrompt: OpenAiCompatibleProfile.defaultSystemPrompt,
      ),
    );
  }

  void _restoreDefaultBreakdownPrompt() {
    _breakdownPromptController.text =
        OpenAiCompatibleProfile.defaultBreakdownPrompt;
    widget.onChanged(
      widget.profile.copyWith(
        breakdownPrompt: OpenAiCompatibleProfile.defaultBreakdownPrompt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.fromLTRB(16, 12, 16, 4);

    return Column(
      children: [
        if (!widget.isOpenRouter)
          Padding(
            padding: padding,
            child: TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Endpoint URL',
                hintText: 'http://10.0.2.2:8080/v1',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              textCapitalization: TextCapitalization.none,
              onChanged: (_) => _notifyFields(),
            ),
          ),
        Padding(
          padding: padding,
          child: widget.isOpenRouter
              ? _buildOpenRouterModelField(context)
              : TextField(
                  controller: _modelController,
                  decoration: const InputDecoration(
                    labelText: 'Model ID',
                    hintText: 'llama3.2',
                    border: OutlineInputBorder(),
                  ),
                  autocorrect: false,
                  textCapitalization: TextCapitalization.none,
                  onChanged: (_) => _notifyFields(),
                ),
        ),
        Padding(
          padding: padding,
          child: TextField(
            controller: _apiKeyController,
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: 'Optional',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _apiKeyVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () =>
                    setState(() { _apiKeyVisible = !_apiKeyVisible; }),
              ),
            ),
            obscureText: !_apiKeyVisible,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            onChanged: (_) => _notifyFields(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Temperature',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    widget.profile.temperature.toStringAsFixed(2),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Slider(
                value: widget.profile.temperature,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                onChanged: (v) =>
                    widget.onChanged(widget.profile.copyWith(temperature: v)),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Focused',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    'Creative',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Request timeout',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    '${widget.profile.timeout.inSeconds}s',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Slider(
                value: widget.profile.timeout.inSeconds.toDouble(),
                min: 10,
                max: 300,
                divisions: 29,
                onChanged: (v) => widget.onChanged(
                  widget.profile.copyWith(
                    timeout: Duration(seconds: v.round()),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '10s',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '5 min',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: FilledButton.tonal(
            onPressed: _testConnection,
            child: const Text('Test connection'),
          ),
        ),
        _PromptSection(
          label: 'Goal decomposition prompt',
          helper: 'Used when a new goal is broken into subtasks.',
          controller: _promptController,
          isDefault:
              widget.profile.systemPrompt ==
              OpenAiCompatibleProfile.defaultSystemPrompt,
          onRestore: _restoreDefaultPrompt,
          onChanged: _notifyFields,
        ),
        _PromptSection(
          label: 'Subtask breakdown prompt',
          helper:
              'Used when an existing subtask is broken down into smaller steps.',
          controller: _breakdownPromptController,
          isDefault:
              widget.profile.breakdownPrompt ==
              OpenAiCompatibleProfile.defaultBreakdownPrompt,
          onRestore: _restoreDefaultBreakdownPrompt,
          onChanged: _notifyFields,
        ),
        _DifficultyRangesSection(
          profile: widget.profile,
          onChanged: widget.onChanged,
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildOpenRouterModelField(BuildContext context) {
    if (_orLoading) {
      return TextField(
        controller: _modelController,
        readOnly: true,
        decoration: InputDecoration(
          labelText: 'Model',
          border: const OutlineInputBorder(),
          helperText: 'Fetching available models…',
          suffixIcon: const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    if (_orError != null) {
      // Fetch failed — fall back to plain text entry with a retry button.
      return TextField(
        controller: _modelController,
        decoration: InputDecoration(
          labelText: 'Model ID',
          hintText: 'e.g. meta-llama/llama-3.2-3b-instruct:free',
          helperText: 'Find models at openrouter.ai/models',
          errorText: 'Could not load models — enter manually',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Retry',
            onPressed: _loadOrModels,
          ),
        ),
        autocorrect: false,
        textCapitalization: TextCapitalization.none,
        onChanged: (_) => _notifyFields(),
      );
    }

    // Models loaded — show a read-only tap-to-pick field.
    return TextField(
      controller: _modelController,
      readOnly: true,
      onTap: _openModelPicker,
      decoration: const InputDecoration(
        labelText: 'Model',
        hintText: 'Tap to choose…',
        border: OutlineInputBorder(),
        suffixIcon: Icon(Icons.arrow_drop_down),
      ),
    );
  }
}

class _PromptSection extends StatelessWidget {
  final String label;
  final String helper;
  final TextEditingController controller;
  final bool isDefault;
  final VoidCallback onRestore;
  final VoidCallback onChanged;

  const _PromptSection({
    required this.label,
    required this.helper,
    required this.controller,
    required this.isDefault,
    required this.onRestore,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              if (!isDefault)
                TextButton(
                  onPressed: onRestore,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Restore default'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            helper,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            maxLines: null,
            minLines: 3,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => onChanged(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Goblin Tools form
// ---------------------------------------------------------------------------

class _GoblinToolsForm extends StatelessWidget {
  final GoblinToolsProfile profile;
  final ValueChanged<GoblinToolsProfile> onChanged;

  const _GoblinToolsForm({required this.profile, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Number of subtasks',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('Few')),
              ButtonSegment(value: 2, label: Text('Some')),
              ButtonSegment(value: 3, label: Text('Many')),
            ],
            selected: {profile.spiciness},
            onSelectionChanged: (s) =>
                onChanged(profile.copyWith(spiciness: s.first)),
          ),
          const SizedBox(height: 12),
          Text(
            'Goblin Tools is a free third-party service — no API key required.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Model search sheet
// ---------------------------------------------------------------------------

class _ModelSearchSheet extends StatefulWidget {
  final List<_OrModel> models;
  final String current;

  const _ModelSearchSheet({required this.models, required this.current});

  @override
  State<_ModelSearchSheet> createState() => _ModelSearchSheetState();
}

class _ModelSearchSheetState extends State<_ModelSearchSheet> {
  late final TextEditingController _search;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search = TextEditingController();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final filtered = q.isEmpty
        ? widget.models
        : widget.models
              .where(
                (m) =>
                    m.id.toLowerCase().contains(q) ||
                    m.name.toLowerCase().contains(q),
              )
              .toList();

    final free = filtered.where((m) => m.isFree).toList();
    final paid = filtered.where((m) => !m.isFree).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          const SizedBox(height: 8),
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search models…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          setState(() { _query = ''; });
                        },
                      ),
              ),
              onChanged: (v) => setState(() { _query = v; }),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              children: [
                if (free.isNotEmpty) ...[
                  _SheetSectionHeader(
                    label: 'Free',
                    subtitle: 'No billing info required',
                    icon: Icons.lock_open_outlined,
                    color: Colors.green.shade700,
                  ),
                  for (final m in free)
                    _ModelTile(model: m, current: widget.current),
                ],
                if (paid.isNotEmpty) ...[
                  _SheetSectionHeader(label: 'Paid'),
                  for (final m in paid)
                    _ModelTile(model: m, current: widget.current),
                ],
                if (filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No models match your search')),
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetSectionHeader extends StatelessWidget {
  final String label;
  final String? subtitle;
  final IconData? icon;
  final Color? color;

  const _SheetSectionHeader({
    required this.label,
    this.subtitle,
    this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: effectiveColor),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: effectiveColor,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 8),
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  final _OrModel model;
  final String current;

  const _ModelTile({required this.model, required this.current});

  @override
  Widget build(BuildContext context) {
    final isSelected = current == model.id;
    return ListTile(
      title: Text(model.name),
      subtitle: Text(
        model.id,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
          : model.isFree
          ? Icon(
              Icons.lock_open_outlined,
              size: 16,
              color: Colors.green.shade700,
            )
          : null,
      selected: isSelected,
      onTap: () => Navigator.pop(context, model.id),
    );
  }
}

// ---------------------------------------------------------------------------
// Test connection dialog
// ---------------------------------------------------------------------------

class _TestDialog extends StatefulWidget {
  final Future<List<String>> Function(String) onTest;

  const _TestDialog({required this.onTest});

  @override
  State<_TestDialog> createState() => _TestDialogState();
}

class _TestDialogState extends State<_TestDialog> {
  static const _defaultGoal = 'Build a house';

  late final TextEditingController _goalController;
  Future<List<String>>? _future;

  @override
  void initState() {
    super.initState();
    _goalController = TextEditingController(text: _defaultGoal);
  }

  @override
  void dispose() {
    _goalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Test decomposition'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _goalController,
              decoration: const InputDecoration(
                labelText: 'Goal',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            if (_future != null) ...[
              const SizedBox(height: 16),
              FutureBuilder<List<String>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  if (snap.hasError) {
                    return Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        borderRadius: BorderRadius.circular(6),
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(10),
                        child: SelectableText(
                          '${snap.error}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ),
                    );
                  }
                  final subtasks = snap.data!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${subtasks.length} subtask${subtasks.length == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 8),
                      for (int i = 0; i < subtasks.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${i + 1}.',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: SelectableText(
                                  subtasks[i],
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: () {
            final future = widget.onTest(_goalController.text.trim());
            setState(() { _future = future; });
          },
          child: const Text('Run'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Difficulty subtask count ranges
// ---------------------------------------------------------------------------

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
