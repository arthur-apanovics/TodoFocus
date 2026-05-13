import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings/llm_profile.dart';
import '../services/settings/llm_settings_service.dart';

// LLM configuration screen. Currently supports one preset ("OpenAI Compatible").
// New profile types will appear as additional options in the preset dropdown —
// add a new LlmProfile subtype and a corresponding _ProfileForm widget.

class LlmSettingsScreen extends StatefulWidget {
  const LlmSettingsScreen({super.key});

  @override
  State<LlmSettingsScreen> createState() => _LlmSettingsScreenState();
}

class _LlmSettingsScreenState extends State<LlmSettingsScreen> {
  // Working copy of the profile — only written to the service on Save.
  late bool _enabled;
  late OpenAiCompatibleProfile _draft;

  @override
  void initState() {
    super.initState();
    final service = context.read<LlmSettingsService>();
    _enabled = service.isEnabled;
    // Seed draft from whatever profile is stored (even if currently disabled),
    // so fields survive toggle-off → save → toggle-on.
    _draft = service.activeProfile is OpenAiCompatibleProfile
        ? service.activeProfile! as OpenAiCompatibleProfile
        : const OpenAiCompatibleProfile(endpointUrl: '', modelId: '');
  }

  void _save() {
    final service = context.read<LlmSettingsService>();
    service.setEnabled(_enabled);
    service.setProfile(_draft);
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
              selected: _draft.displayName,
              // Only one preset for now; more added here later.
              options: const ['OpenAI Compatible'],
              onChanged: (_) {}, // no-op until second preset exists
            ),
            const Divider(height: 1),
            _OpenAiCompatibleForm(
              profile: _draft,
              onChanged: (updated) => setState(() => _draft = updated),
            ),
          ],
        ],
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
// OpenAI-compatible profile form
// ---------------------------------------------------------------------------

class _OpenAiCompatibleForm extends StatefulWidget {
  final OpenAiCompatibleProfile profile;
  final ValueChanged<OpenAiCompatibleProfile> onChanged;

  const _OpenAiCompatibleForm({
    required this.profile,
    required this.onChanged,
  });

  @override
  State<_OpenAiCompatibleForm> createState() => _OpenAiCompatibleFormState();
}

class _OpenAiCompatibleFormState extends State<_OpenAiCompatibleForm> {
  late final TextEditingController _urlController;
  late final TextEditingController _modelController;
  late final TextEditingController _apiKeyController;
  bool _apiKeyVisible = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.profile.endpointUrl);
    _modelController = TextEditingController(text: widget.profile.modelId);
    _apiKeyController = TextEditingController(text: widget.profile.apiKey ?? '');
  }

  @override
  void dispose() {
    _urlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged(widget.profile.copyWith(
      endpointUrl: _urlController.text.trim(),
      modelId: _modelController.text.trim(),
      apiKey: _apiKeyController.text.trim().isEmpty
          ? null
          : _apiKeyController.text.trim(),
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
              hintText: 'http://localhost:11434/v1',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            onChanged: (_) => _notify(),
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
            onChanged: (_) => _notify(),
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
            onChanged: (_) => _notify(),
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
                onChanged: (v) => widget.onChanged(
                  widget.profile.copyWith(temperature: v),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Focused',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                  Text('Creative',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
