# Flutter Todo App

A goal-tracking app built with Flutter, focused on breaking goals into small, ADHD-friendly subtasks. Runs on Android (primary target); other platforms are untested.

## Running the app

```bash
flutter run
```

Requires a connected Android device or emulator. The app uses Hive for local storage — no backend required.

### Running tests

```bash
flutter test
```

---

## LLM configuration

The app uses an LLM to decompose goals into subtasks. Without a configured LLM it falls back to a keyword-based template system — goals are still decomposed, just without LLM intelligence.

### Runtime configuration (recommended)

Open **Settings → LLM configuration** in the app. Enable AI features and fill in:

| Field | Description |
|---|---|
| Endpoint URL | Base URL of any OpenAI-compatible API |
| Model ID | Model name as the server expects it, e.g. `llama3.2` |
| API Key | Optional. Required for hosted providers (OpenAI, Together AI, etc.) |
| Temperature | 0.0 = focused/deterministic, 1.0 = creative. Default: 0.3 |

Settings are persisted across app restarts via Hive.

> **Note:** Android emulators cannot reach `localhost` on the host machine. Use `10.0.2.2` instead of `127.0.0.1` or `localhost`.

### Build-time configuration (dev / CI)

Pass values via `--dart-define` at build or run time. These **overwrite** any settings stored in the app — useful for scripted testing or development builds where you want a known config without tapping through the UI.

```bash
# Local llama-server
flutter run \
  --dart-define=LLM_BASE_URL=http://10.0.2.2:8080/v1 \
  --dart-define=LLM_MODEL=gemma-3-270m-it

# Hosted provider
flutter run \
  --dart-define=LLM_BASE_URL=https://api.openai.com/v1 \
  --dart-define=LLM_MODEL=gpt-4o-mini \
  --dart-define=LLM_API_KEY=sk-...
```

| Variable | Required | Default | Description |
|---|---|---|---|
| `LLM_BASE_URL` | Yes (to activate) | — | Base URL, no trailing slash |
| `LLM_MODEL` | No | `llama3.2` | Model identifier |
| `LLM_API_KEY` | No | — | Bearer token |

Temperature cannot be set via `--dart-define`; it defaults to `0.3`. Adjust it in the UI after first launch if needed.

### Recommended local backend

[llama.cpp](https://github.com/ggerganov/llama.cpp) `llama-server` works well. It supports the OpenAI-compatible `/v1/chat/completions` endpoint and the `response_format: json_schema` field the app uses to constrain sampler output via GBNF grammar.

```bash
llama-server -m your-model.gguf --port 8080
```

Any quantisation level works. Tested with `gemma-3-270m-it-UD-Q4_K_XL.gguf` from Unsloth. Larger models produce better decompositions.

---

## Architecture notes

### State management

Uses `provider` throughout. The dependency chain:

```
HiveGoalRepository (ChangeNotifier)
  ├─ GoalService               (ProxyProvider — writes)
  └─ GoalQueries               (ProxyProvider — reads / derived state)

LlmSettingsService (ChangeNotifier)
  └─ GoalDecompositionService  (ProxyProvider — rebuilt when settings change)
```

### Storage

Hive is used for all persistence. Two boxes:

| Box | Type | Contents |
|---|---|---|
| `goals` | `Box<GoalDto>` | All goals and subtasks (code-generated adapter) |
| `app_settings` | `Box<String>` | LLM settings stored as JSON key-value pairs |

`app_settings` uses plain strings so no Hive code generation is needed for settings.

If the Hive adapter changes (fields added/removed in `GoalDto` or `SubTaskDto`), run:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### Notifications

A persistent Android notification shows the current focus task with a "Mark done" action button. Requirements:

- `POST_NOTIFICATIONS` permission declared in `AndroidManifest.xml` (auto-granted below Android 13, runtime prompt on 13+)
- The notification channel is named `focus_task_v2` — if you change the channel ID, existing devices will not migrate their channel settings automatically
- The notification is re-posted on app resume to recover from system dismissal (Android can clear ongoing notifications under memory pressure)

### LLM output handling

The app sends `response_format: json_schema` with every LLM request. Backends that support it (llama-server, OpenAI) compile this to a grammar that physically prevents malformed output. `GoalDecompositionService` also strips markdown code fences (` ```json [...] ``` `) and extracts the first `[...]` block as fallbacks for backends that ignore the constraint. If parsing still fails, the keyword-template fallback is used silently — the `onLlmFallback` callback on `GoalDecompositionService.decompose` can be used to surface this to the user.
