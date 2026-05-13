import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings/llm_profile.dart';
import '../services/settings/llm_settings_service.dart';

// LLM configuration screen. Add new profile types by:
//   1. Adding a subtype in llm_profile.dart
//   2. Adding its name to _presets
//   3. Adding a case in _buildForm and handling in initState / _onPresetChanged

class LlmSettingsScreen extends StatefulWidget {
  const LlmSettingsScreen({super.key});

  @override
  State<LlmSettingsScreen> createState() => _LlmSettingsScreenState();
}

class _LlmSettingsScreenState extends State<LlmSettingsScreen> {
  static const _presets = ['OpenAI Compatible', 'Goblin Tools'];

  late bool _enabled;

  // Each profile type has its own draft so switching presets and back
  // does not discard previously entered values.
  late OpenAiCompatibleProfile _openAiDraft;
  late GoblinToolsProfile _goblinDraft;
  late String _selectedPreset;

  LlmProfile get _draft => switch (_selectedPreset) {
    'Goblin Tools' => _goblinDraft,
    _ => _openAiDraft,
  };

  @override
  void initState() {
    super.initState();
    final service = context.read<LlmSettingsService>();
    _enabled = service.isEnabled;

    // Each draft is initialised from its own stored slot, so switching active
    // preset and saving never wipes the other type's configuration.
    _openAiDraft = service.openAiProfile;
    _goblinDraft = service.goblinProfile;

    _selectedPreset = switch (service.activeProfile) {
      GoblinToolsProfile() => 'Goblin Tools',
      _ => 'OpenAI Compatible',
    };
  }

  void _onPresetChanged(String preset) {
    setState(() => _selectedPreset = preset);
  }

  Future<void> _save() async {
    final service = context.read<LlmSettingsService>();
    await service.setEnabled(_enabled);
    await service.setProfile(_draft);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LLM Configuration'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          SwitchListTile(
            title: const Text('Enable AI features'),
            subtitle: const Text('Goal decomposition and suggestions'),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          const Divider(height: 1),
          if (_enabled) ...[
            _PresetTile(
              selected: _selectedPreset,
              options: _presets,
              onChanged: _onPresetChanged,
            ),
            const Divider(height: 1),
            _buildForm(),
          ],
        ],
      ),
    );
  }

  Widget _buildForm() => switch (_selectedPreset) {
    'Goblin Tools' => _GoblinToolsForm(
        profile: _goblinDraft,
        onChanged: (p) => setState(() => _goblinDraft = p),
      ),
    _ => _OpenAiCompatibleForm(
        profile: _openAiDraft,
        onChanged: (p) => setState(() => _openAiDraft = p),
      ),
  };
}

// ---------------------------------------------------------------------------
// Shared
// ---------------------------------------------------------------------------

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

  const _OpenAiCompatibleForm({required this.profile, required this.onChanged});

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

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.profile.endpointUrl);
    _modelController = TextEditingController(text: widget.profile.modelId);
    _apiKeyController = TextEditingController(text: widget.profile.apiKey ?? '');
    _promptController = TextEditingController(text: widget.profile.systemPrompt);
    _breakdownPromptController =
        TextEditingController(text: widget.profile.breakdownPrompt);
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

  void _notifyFields() {
    widget.onChanged(widget.profile.copyWith(
      endpointUrl: _urlController.text.trim(),
      modelId: _modelController.text.trim(),
      apiKey: _apiKeyController.text.trim().isEmpty
          ? null
          : _apiKeyController.text.trim(),
      systemPrompt: _promptController.text,
      breakdownPrompt: _breakdownPromptController.text,
    ));
  }

  void _restoreDefaultPrompt() {
    _promptController.text = OpenAiCompatibleProfile.defaultSystemPrompt;
    widget.onChanged(widget.profile.copyWith(
      systemPrompt: OpenAiCompatibleProfile.defaultSystemPrompt,
    ));
  }

  void _restoreDefaultBreakdownPrompt() {
    _breakdownPromptController.text =
        OpenAiCompatibleProfile.defaultBreakdownPrompt;
    widget.onChanged(widget.profile.copyWith(
      breakdownPrompt: OpenAiCompatibleProfile.defaultBreakdownPrompt,
    ));
  }

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.fromLTRB(16, 12, 16, 4);

    return Column(
      children: [
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
          child: TextField(
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
                icon: Icon(_apiKeyVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () =>
                    setState(() => _apiKeyVisible = !_apiKeyVisible),
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
                  Text('Temperature',
                      style: Theme.of(context).textTheme.bodyMedium),
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
                  Text('Focused',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                  Text('Creative',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
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
                  Text('Request timeout',
                      style: Theme.of(context).textTheme.bodyMedium),
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
                onChanged: (v) => widget.onChanged(widget.profile.copyWith(
                  timeout: Duration(seconds: v.round()),
                )),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('10s',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                  Text('5 min',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                ],
              ),
            ],
          ),
        ),
        _PromptSection(
          label: 'Goal decomposition prompt',
          helper: 'Used when a new goal is broken into subtasks.',
          controller: _promptController,
          isDefault: widget.profile.systemPrompt ==
              OpenAiCompatibleProfile.defaultSystemPrompt,
          onRestore: _restoreDefaultPrompt,
          onChanged: _notifyFields,
        ),
        _PromptSection(
          label: 'Subtask breakdown prompt',
          helper:
              'Used when an existing subtask is broken down into smaller steps.',
          controller: _breakdownPromptController,
          isDefault: widget.profile.breakdownPrompt ==
              OpenAiCompatibleProfile.defaultBreakdownPrompt,
          onRestore: _restoreDefaultBreakdownPrompt,
          onChanged: _notifyFields,
        ),
        const SizedBox(height: 8),
      ],
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
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
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
          Text('Number of subtasks',
              style: Theme.of(context).textTheme.bodyMedium),
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
