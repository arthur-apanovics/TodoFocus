# Todo App — LLM Session State
**Last updated:** 2026-05-17  
**Framework:** Flutter (Dart)  
**Purpose:** Preserve project context, decisions, and progress across LLM sessions. Read this before touching any code.

---

## App Overview

A mobile-first todo app designed to reduce cognitive load for users with ADHD. Core philosophy: **minimal friction at every step** — from capturing an idea to completing it. The lifecycle is:

**Capture → Inbox → Decompose → Goals → Focus → Complete**

The app is Flutter-only (Android primary target). No backend; all state is local via Hive.

---

## MVP Feature Status

### Complete
- **Goal management** — create, edit, delete goals; title + notes fields; optional due date
- **Inbox capture** — add a goal without decomposing it; lives on its own tab until processed
- **Inbox promotion** — adding the first subtask to an inbox goal automatically promotes it to `active`; inbox items do NOT auto-decompose — user triggers decomposition manually from the detail screen
- **Goal decomposition** — manual subtask creation, edit, delete, reorder (drag handles)
- **Sequential subtask queue** — subtasks must be completed in order; `currentSubTask` is always the first `pending` one — derived, never stored; invalid multi-active state is unrepresentable by design
- **Undo completion** — `uncompleteSubTask()` marks a completed subtask pending and re-inserts it just before the current one
- **Focus tab** — star icon on goal tile toggles `isFocusedToday`; Focus screen shows current + next subtask peek per focused goal with a progress bar and drag-to-reorder
- **Today queue ordering** — `todayOrder: int` on `Goal` stores position; `GoalService.reorderTodayQueue()` handles ReorderableListView's index convention; `GoalQueries.todayQueue` sorts by `todayOrder` ascending
- **Navigation from Focus view** — tapping a goal card navigates to `GoalDetailScreen`
- **Navigate to new goal** — "Create Goal" in the new-goal sheet navigates directly to the new goal's detail screen; "Save to Inbox" does not navigate
- **Bottom navigation** — Focus, Goals, Inbox tabs
- **Swipe to delete** — `Slidable` (not `Dismissible`) on all list tiles for goal delete and subtask delete
- **Persistence** — Hive NoSQL local storage; `GoalRepository` abstraction isolates domain from storage
- **Theme** — centralised `AppColors` and `AppIcons` classes; Material seed colour from `AppColors.accent`
- **CI / release** — GitHub Actions builds arm64 APK on `workflow_dispatch` or `v*` tag push; tagged runs create a GitHub Release with generated notes
- **Persistent Android notification** — ongoing notification showing `❯ <currentSubTask>` as title, `↳ <nextSubTask>` as body, `<goalTitle>` as subText; action button "Next step" / "Finish goal" completes the subtask; tapping the body opens the Focus tab; suppressed if goal/subtask unchanged; re-posted on app resume via `WidgetsBindingObserver`; replays cold-start action via `getNotificationAppLaunchDetails()`
- **Tests** — 79 passing tests across 4 layers (see Testing section)
- **App icons** — generated from `logos/app-icon-1024.png` via `flutter_launcher_icons` for all Android mipmap densities and iOS AppIcon slots
- **LLM decomposition** — pluggable provider system; goals decomposed into subtasks by LLM or keyword fallback; see LLM section below
- **LLM settings UI** — `LlmSettingsScreen` with OpenAI-compatible config (URL, model, API key, temperature, timeout, custom system/breakdown prompts); supports OpenRouter and local llama-server via the same OpenAI endpoint
- **Icon generation** — 665 Material icons across 16 categories (Work, Health, Learning, Food, Home, Travel, Creative, Finance, People, Tech, Transport, Animals, Communication, Events, Mindfulness); stored in `Goal.emoji` as short names (e.g., `'gym'`, `'running'`); falls back to rendering legacy Unicode emoji strings
- **Async goal creation with loading indicator** — goals created immediately, icons/subtasks populated in the background via `decomposeInBackground` and `suggestIcon`; `DecompositionState` tracks in-flight goal IDs; detail screen shows spinner in place of subtask list; list tiles show spinner in place of status icon while decomposing
- **Re-decompose subtasks** — three-dot menu on `GoalDetailScreen`; replaces all subtasks; optional additional instructions field in confirm dialog; uses `DecompositionState` for loading UI
- **Subtask breakdown** — split button on every non-completed subtask tile; tap = auto-breakdown via LLM; long press = opens `_InstructionsSheet` for custom steering instructions first; falls back to manual split sheet when no LLM configured
- **Custom steering instructions** — both re-decompose and subtask breakdown accept optional free-text instructions; appended to LLM user message for OpenAI-compatible
- **Bulk icon generation** — LLM Settings screen allows generating icons for goals without them; uses `suggestIconBulk` to batch requests

### Post-MVP / Planned
- **Daily reset** — Focus list resets each day; carry-over rules TBD; this is the trigger for extracting `todayOrder`/`isFocusedToday` into a separate `TodaySession` object
- **Micro-rewards** — visual/audio feedback on subtask completion
- **Neglect priority** — tasks untouched >24h boosted (`lastSeenDate` already tracked on `SubTask`)
- **Deadline priority** — goals with nearest `dueDate` weighted higher
- **Inbox processing wizard** — guided flow to convert inbox items into structured goals
- **Multi-platform sync** — backend for cross-device state
- **Mobile widget** — single-tap idea capture from home screen
- **Voice capture** — hands-free input
- **Focus mode** — integrated Pomodoro timer per subtask

---

## LLM Integration

### Provider Architecture
`DecompositionClient` is an abstract interface with four methods:
- `decompose(title, {description, additionalInstructions, difficulty, completedSteps})` → `List<String>` subtask descriptions
- `breakdown(subtaskDescription, {additionalInstructions, difficulty})` → `List<String>` smaller steps
- `suggestIcon(goalTitle, iconNames)` → `String?` single icon name from the provided list
- `suggestIconBulk(goalTitles, iconNames)` → `List<String?>` icon names (one per goal, same order)

Implementations:
- `OpenAiDecompositionClient` — wraps `LlmClient` (HTTP); appends `additionalInstructions` to the user message; difficulty controls subtask count bounds; includes prompt caching for icon names list

`GoalDecompositionService` is provider-agnostic: it receives an optional `DecompositionClient?` and falls back to keyword templates when `null`. Icon generation is concurrent with decomposition and controlled by `_generateEmojis` flag.

### Keyword Fallback
`_detectIntent(title, description)` scans for ~20 action-verb categories (learn, build, travel, etc.) and picks a matching template list from `_templatesByIntent`. Returns `'fallback'` if nothing matches.

### Settings Persistence
`LlmSettingsService` (Hive `Box<String>`, key `app_settings`):
- Single storage slot: `openai_profile` (Goblin Tools support dropped for complexity reduction)
- `active_profile_type` stores which preset is currently active (currently only `OpenAiCompatibleProfile.typeKey`)
- `generateEmojis` boolean — enables/disables concurrent icon suggestion during decomposition
- `debugMode` boolean — shows full error details in failure notifications
- One-time migration from legacy single `active_profile` key and removal of `goblin_profile` key
- `--dart-define` env vars (`LLM_BASE_URL`, `LLM_MODEL`, `LLM_API_KEY`, `LLM_TEMPERATURE`) override stored OpenAI settings at startup

### `DecompositionState`
A top-level `ChangeNotifier` (not tied to `ProxyProvider` recreation) that tracks which goal IDs have an in-flight decomposition. Also tracks fallback events so the detail screen can show a snackbar.

Key methods: `begin(goalId)`, `end(goalId)`, `isDecomposing(goalId)`, `fail(goalId, {errorMessage})`, `hasFallback(goalId)`, `fallbackError(goalId)`, `clearFallback(goalId)`.

### `decomposeInBackground`
Fire-and-forget async method on `GoalDecompositionService`. Marks state, calls LLM, falls back to keywords on error, delivers results via `onResult` callback, clears state in `finally`. No loading flash when no client is configured (synchronous keyword path).

Concurrent icon suggestion: if `_generateEmojis && onEmoji != null && _iconNames.isNotEmpty`, fires `_client.suggestIcon(title, _iconNames)` in parallel with decomposition. Icon arrives via `onEmoji` callback once resolved.

Icon names list is passed from `main.dart` during service construction: `iconByName.keys.toList()` from `icon_catalog.dart` (665 names across 16 categories).

---

## Architecture

### Principles
- **DDD-influenced** — `Goal` is the aggregate root; subtasks never exist or mutate independently
- **Repository abstraction** — `GoalRepository` (abstract `ChangeNotifier`) isolates domain from storage. Swap `HiveGoalRepository` for any other impl by changing one line in `main.dart`
- **CQRS-lite** — `GoalService` (commands/writes), `GoalQueries` (read projections), `GoalRepository` (storage)
- **Domain model purity** — `Goal` and `SubTask` have zero Flutter/Hive dependencies; Hive DTOs (`GoalDto`, `SubTaskDto`) are separate classes in `services/hive/`
- **Invalid state unrepresentable** — `SubTaskState` has only `pending` and `completed`; `inProgress` is derived (`currentSubTask` = first pending), never stored

### State Management — Provider
- `ChangeNotifierProvider<GoalRepository>` — source of truth; calls `notifyListeners()` on every mutation
- `ChangeNotifierProvider<LlmSettingsService>` — LLM config and enable/disable state
- `ChangeNotifierProvider<DecompositionState>` — tracks in-flight decompositions app-wide; intentionally NOT a `ProxyProvider` so it survives LLM settings changes without resetting in-flight state
- `ProxyProvider<GoalRepository, GoalService>` — service depends on repo
- `ProxyProvider<GoalRepository, GoalQueries>` — queries depend on repo
- `ProxyProvider<LlmSettingsService, GoalDecompositionService>` — rebuilds client when settings change
- `Provider<NotificationService>` — notification service exposed so `AppShell` can re-post on resume
- `context.watch<T>()` — reactive reads inside `build()` (subscribes to rebuilds)
- `context.read<T>()` — one-off reads inside event handlers (no subscription)

### Navigation
- `AppShell` — `StatefulWidget` with `NavigationBar` (bottom tabs); FAB lives here, visible on all tabs
- `GoalsScreen` / `InboxScreen` / `FocusScreen` → `GoalDetailScreen` via `Navigator.push` / `MaterialPageRoute`
- "Create Goal" in `NewGoalSheet` — pops with `goal.goalId`; `AppShell._buildFab` awaits and pushes `GoalDetailScreen`
- "Save to Inbox" — pops with no result, no navigation
- `ValueNotifier<int> tabNotifier` — passed from `main()` into `AppShell` and `NotificationService`; tapping the notification body sets index 0 (Focus tab) via the notifier
- Edit/create forms via `showModalBottomSheet` using `AppBottomSheet` wrapper widget

### Notification Architecture
- `NotificationService` in `lib/services/notification_service.dart`
- Initialised in `main()` before `runApp`; passed via `Provider`
- `GoalRepository.addListener` triggers `notificationService.update(todayQueue)` on every repo change
- `AppShell` implements `WidgetsBindingObserver`; `didChangeAppLifecycleState(resumed)` re-posts notification
- `_shownGoalId` / `_shownSubtaskId` cache suppresses spurious re-posts when nothing has changed
- Channel ID: `focus_task_v2` (importance locked at channel creation; versioned ID forces recreation)
- `showsUserInterface: false` on the action button
- Cold-start: `getNotificationAppLaunchDetails()` replays the last action on first init
- `GoalDetailScreen` accepts `triggerBreakdown: bool` — when `true`, auto-triggers subtask breakdown on first frame (wired to "Break it down" notification action)

---

## Project Structure

```
lib/
├── main.dart                           — Hive init, Provider tree, AppShell, tabNotifier, notification wiring
├── models/
│   ├── enums.dart                      — GoalStatus {inbox, active, completed}
│   │                                     SubTaskState {pending, completed}
│   ├── goal.dart                       — aggregate root, queue logic, todayOrder, _recalculateStatus
│   └── sub_task.dart                   — subtask domain model
├── screens/
│   ├── focus_screen.dart               — Today tab: focused goals, current+next subtask, drag-to-reorder, tap→detail
│   ├── goals_screen.dart               — Goals tab: active+completed goals, star toggle, delete; spinner on decomposing tiles
│   ├── inbox_screen.dart               — Inbox tab: undecomposed goals, tap to open detail; spinner on decomposing tiles
│   ├── goal_detail_screen.dart         — StatefulWidget; subtask CRUD, reorder, complete, undo; loading/inbox/empty states;
│   │                                     re-decompose menu; split button (tap=auto, long-press=instructions sheet);
│   │                                     triggerBreakdown param for notification action; fallback snackbar via DecompositionState
│   ├── llm_settings_screen.dart        — LLM config UI: OpenAI-compatible form (url/model/key/temp/timeout/custom prompts),
│   │                                     bulk icon generation button for goals without icons; save is async
│   └── widgets/
│       ├── icon_catalog.dart           — 665 Material icons across 16 categories; returns `IconData?` by name
│       ├── goal_symbol.dart            — renders icon for Goal.emoji; inherits IconTheme size when null
│       ├── emoji_picker_sheet.dart     — Material Icons picker with search; used in goal creation/detail
│       ├── app_bottom_sheet.dart       — shared sheet chrome (handle, padding, keyboard avoid)
│       └── new_goal_sheet.dart         — new goal form; Create pops with goalId + fires decomposeInBackground;
│                                         Inbox saves immediately with no decomposition
├── services/
│   ├── decomposition_state.dart        — ChangeNotifier; tracks in-flight goal IDs + fallback events
│   ├── goal_decomposition_service.dart — orchestrates LLM/keyword decomposition; createGoal, captureToInbox,
│   │                                     decomposeInBackground, redecomposeSubtasks, breakdownSubtask
│   ├── goal_queries.dart               — read projections: todayQueue (sorted), goals, inbox
│   ├── goal_repository.dart            — abstract GoalRepository + InMemoryGoalRepository
│   ├── goal_service.dart               — all mutations incl. toggleFocusToday, reorderTodayQueue, replaceAllSubTasks
│   ├── notification_service.dart       — persistent Android notification; update(), init(), _onResponse()
│   ├── sample_data.dart                — seed data — DELETE BEFORE SHIPPING
│   ├── hive/
│   │   ├── goal_dto.dart               — Hive DTO (typeId: 0), field index registry in comments
│   │   ├── goal_dto.g.dart             — generated — DO NOT EDIT (hand-edit for field 7 todayOrder was needed)
│   │   ├── hive_goal_repository.dart   — concrete Hive impl; seeds from SampleData if box empty
│   │   ├── sub_task_dto.dart           — Hive DTO (typeId: 1), field index registry in comments
│   │   └── sub_task_dto.g.dart         — generated — DO NOT EDIT
│   ├── llm/
│   │   ├── decomposition_client.dart   — abstract interface: decompose(), breakdown(), suggestIcon(), suggestIconBulk()
│   │   ├── openai_decomposition_client.dart — OpenAI-compatible impl; additionalInstructions appended to user message; supports prompt caching
│   │   ├── llm_client.dart             — HTTP client wrapping the OpenAI chat completions endpoint
│   │   └── llm_config.dart             — reads --dart-define env vars (LLM_BASE_URL, LLM_MODEL, LLM_API_KEY, LLM_TEMPERATURE)
│   └── settings/
│       ├── llm_profile.dart            — sealed class: OpenAiCompatibleProfile only; JSON encode/decode
│       └── llm_settings_service.dart   — Hive-backed; single openai_profile key; activeType; generateEmojis; debugMode
└── theme/
    ├── app_colors.dart                 — centralised colour palette (see Theme section)
    └── app_icons.dart                  — centralised icon constants (semantic names)

logos/                                  — source assets; app-icon-1024.png is the flutter_launcher_icons source

test/
├── models/
│   └── goal_test.dart                  — 26 tests: Goal domain logic
├── services/
│   ├── goal_service_test.dart          — 21 tests: GoalService + InMemoryGoalRepository
│   ├── goal_queries_test.dart          — 13 tests: GoalQueries projections
│   └── hive/
│       └── hive_goal_repository_test.dart — 19 tests: Hive round-trips, migrations

.github/
└── workflows/
    └── build-apk.yml                   — manual + tag-triggered arm64 APK build + GitHub Release
```

---

## Data Models

### `GoalStatus` (enum)
| Value | Meaning |
|---|---|
| `inbox` | Captured, not yet decomposed (no subtasks yet) |
| `active` | Has subtasks; in progress |
| `completed` | All subtasks done — set by `_recalculateStatus()` |

> `paused` was removed. Any Hive records with `status == 'paused'` are migrated to `active` in `_toDomain()` in `HiveGoalRepository`.

### `SubTaskState` (enum)
| Value | Meaning |
|---|---|
| `pending` | Not yet done; first pending = implicit current |
| `completed` | Done |

### `Goal` — key members
| Member | Type | Notes |
|---|---|---|
| `goalId` | `String` | UUID v4 |
| `title` | `String` | Mutable |
| `notes` | `String` | Mutable |
| `status` | `GoalStatus` | Managed by `_recalculateStatus()` |
| `dueDate` | `DateTime?` | Optional |
| `isFocusedToday` | `bool` | Toggled via star icon on Goals screen |
| `todayOrder` | `int` | Position in the today queue; 0-based; assigned by `toggleFocusToday`, rewritten by `reorderTodayQueue` |
| `emoji` | `String?` | Optional icon name (e.g., `'gym'`, `'running'`) from `iconCatalog`, or legacy Unicode emoji string |
| `subtasks` | `List<SubTask>` | Ordered queue; mutable list |
| `currentSubTask` | `SubTask?` | Computed — first `pending` subtask |
| `nextSubTask` | `SubTask?` | Computed — second `pending` (used for Focus peek and notification) |
| `isDailyAssignable` | `bool` | `status != completed && status != inbox` |
| `progressPercent` | `double` | 0.0 when no subtasks |
| `completedSubtaskCount` | `int` | Count of `completed` subtasks |

Key `Goal` mutation methods:
- `addSubTask(SubTask)` — appends, then calls `_recalculateStatus()` (inbox → active, completed → active)
- `removeSubTask(String subtaskId)` — removes, recalculates
- `completeCurrentSubTask()` — marks first pending done, recalculates
- `uncompleteSubTask(String subtaskId)` — marks pending, removes from list, re-inserts before current (or appends if all others done), recalculates
- `reorderSubTask(int old, int new)` — can't move completed; clamps to first pending index
- `replaceAllSubTasks(List<SubTask>)` — clears and replaces atomically, recalculates (used by LLM result delivery)
- `_recalculateStatus()` — sets `completed` if all subtasks done; else `active`

> **Important:** The `Goal` constructor does NOT call `_recalculateStatus()`. Status is set exactly as passed. `_recalculateStatus()` only fires on explicit mutations.

### `SubTask` — key members
| Member | Type | Notes |
|---|---|---|
| `subtaskId` | `String` | UUID v4 |
| `description` | `String` | Mutable |
| `state` | `SubTaskState` | `pending` or `completed` |
| `assignedDate` | `DateTime` | Set on creation |
| `completionDate` | `DateTime?` | Set by `markComplete()`, cleared by `markIncomplete()` |
| `lastSeenDate` | `DateTime` | Updated on interaction — reserved for neglect priority |
| `effortEstimate` | `int?` | Optional, minutes |

---

## Hive Schema

Schema evolution rule: **never reuse a retired field index**. Add new fields at the next available index. Null-check in `_toDomain()` provides backward compat for older records missing new fields.

### `GoalDto` — typeId: 0
| Index | Field | Status |
|---|---|---|
| 0 | `goalId` | active |
| 1 | `title` | active |
| 2 | `notes` | active |
| 3 | `status` | active — stored as string, e.g. `"active"` |
| 4 | `dueDate` | active |
| 5 | `subtasks` | active — `List<SubTaskDto>` |
| 6 | `isFocusedToday` | active — defaults `false` if null (backward compat) |
| 7 | `todayOrder` | active — defaults `0` if null (backward compat) |
| 8 | `emoji` | active — optional icon name or legacy emoji string; defaults `null` if missing |
| — | Next available | **9** |

### `SubTaskDto` — typeId: 1
| Index | Field | Status |
|---|---|---|
| 0 | `subtaskId` | active |
| 1 | `description` | active |
| 2 | `state` | active — stored as string: `"pending"` or `"completed"` |
| 3 | `assignedDate` | active |
| 4 | `completionDate` | active |
| 5 | `lastSeenDate` | active |
| 6 | `effortEstimate` | active |
| — | Next available | **7** |

After editing any `@HiveType`/`@HiveField` annotated class, regenerate adapters:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```
`goal_dto.g.dart` was hand-edited to add fields 6 (`isFocusedToday`), 7 (`todayOrder`), and 8 (`emoji`). `writeByte(n)` in the adapter's `write()` method is the **total field count** (currently `9`), not an index.

---

## Theme System

### `AppColors` — `lib/theme/app_colors.dart`
All colours centralised here. Changing `accent` propagates to the Material seed colour, all explicit icon colours, and progress indicators.

| Name | Value | Used for |
|---|---|---|
| `faded` | `Colors.grey.shade400` | Completed subtask drag handle (now transparent — kept in palette for future use) |
| `muted` | `Colors.grey.shade600` | Secondary icons, hints, subtitles, completed subtask text |
| `strong` | `Colors.grey.shade800` | Primary action icon (current subtask complete button) |
| `sheetHandle` | `Colors.grey.shade300` | Bottom sheet drag handle |
| `accent` | `Colors.indigo` | Focus today star, current subtask label, progress, badges |
| `accentSurface` | `Colors.indigo.shade50` | Progress badge background |
| `success` | `Colors.green` | All-done state |
| `successSurface` | `Colors.green.shade50` | All-done badge background |
| `destructive` | `Colors.red` | Delete actions |
| `onDestructive` | `Colors.white` | Text/icon on red |

### `AppIcons` — `lib/theme/app_icons.dart`
| Name | Icon | Semantic meaning |
|---|---|---|
| `complete` | `Icons.radio_button_unchecked` | "Tap to mark this subtask done" |
| `uncomplete` | `Icons.restore` | "Undo completion" |
| `delete` | `Icons.delete_outline` | Destructive delete on all swipe actions |
| `nextInQueue` | (dimmed peek icon) | Next subtask visual in Focus card |

### Subtask tile visual rules
- **Opacity:** `1.0` always; `0.6` while `_isBreakingDown`
- **Leading drag handle:** `Colors.transparent` for completed and breaking-down rows (preserves layout width, hides icon); `ReorderableDragStartListener` for all others
- **Current subtask title:** bold + `AppColors.strong`
- **Completed subtask title:** strikethrough + `AppColors.muted`
- **Subtitle:** shown only for "Breaking down…" and "Completed"; null for current and queued
- **Split button tooltip removed** — `Tooltip`'s long-press recognizer wins the gesture arena over an outer `GestureDetector`; tooltip was removed so long-press correctly opens the instructions sheet

---

## Testing

79 tests, all passing. Run with `flutter test`.

### Layers

**`test/models/goal_test.dart`** — 26 tests, pure Dart, no dependencies  
Covers: `addSubTask` (inbox promotion, completed→active restore), `completeCurrentSubTask` (queue advance, completion transition), `uncompleteSubTask` (re-insert before current, append when all done), `reorderSubTask` (completed no-op, clamp to pending block), `progressPercent`, `isDailyAssignable`, `currentSubTask`/`nextSubTask`

**`test/services/goal_service_test.dart`** — 21 tests  
Uses `InMemoryGoalRepository.empty()`. Covers the full write path: service → repo → re-read.  
Covers: `addSubTask`, `removeGoal`, `updateGoal`, `toggleFocusToday` (order assignment on focus), `reorderTodayQueue` (bottom→top, top→bottom, no-op), `completeCurrentSubTask`, `deleteSubTask`, `uncompleteSubTask`, `reorderSubTask`

**`test/services/goal_queries_test.dart`** — 13 tests  
Covers projections that had real bugs. Each `todayQueue` test maps to a bug found in production:
- Excludes `isFocusedToday = false` goals
- Excludes goals with 0 subtasks (caused "All 0 steps complete" card)
- Excludes completed goals and inbox goals (`isDailyAssignable` not checked)
- Sorts by `todayOrder` ascending  
Also covers `goals` (excludes inbox) and `inbox` projections.

**`test/services/hive/hive_goal_repository_test.dart`** — 19 tests  
Uses `Hive.init(tempDir)` + `HiveGoalRepository(box, seed: false)`. No extra deps needed.  
Covers: save/findById/all, delete, `todayOrder` round-trip, `isFocusedToday` round-trip (the persistence bug), status round-trips, legacy `paused` migration, subtask order/state preservation, idempotent save (the duplicate-entry bug).

### Test infrastructure
- `InMemoryGoalRepository.empty()` — named constructor, starts with no goals (app default still seeds from `SampleData`)
- `HiveGoalRepository(box, {bool seed = true})` — `seed: false` used in tests to skip `SampleData` injection

---

## Dependencies

```yaml
dependencies:
  flutter_slidable: ^3.1.0            # swipe actions on list tiles
  collection: ^1.18.0                 # firstWhereOrNull, etc.
  uuid: ^4.0.0                        # UUID generation
  provider: ^6.1.0                    # DI / state management
  hive_flutter: ^1.1.0                # local persistence
  http: ^1.2.0                        # LLM HTTP calls
  awesome_notifications: ^0.11.0      # persistent Android notification
  file_picker: ^8.0.0                 # (reserved)

dev_dependencies:
  hive_generator: ^2.0.1             # TypeAdapter code generation
  build_runner: ^2.4.0               # runs code generation
  flutter_launcher_icons: ^0.14.0    # generates all platform icon sizes from logos/app-icon-1024.png
```

To regenerate icons after changing the source image:
```bash
flutter pub run flutter_launcher_icons
```
Note: source image has an alpha channel — set `remove_alpha_ios: true` in pubspec `flutter_launcher_icons` block before App Store submission.

### Android requirements for notifications
- `android/app/build.gradle.kts`: `isCoreLibraryDesugaringEnabled = true` + `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")`
- `AndroidManifest.xml`: `<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>`

---

## CI / CD

**`.github/workflows/build-apk.yml`**  
Triggers:
- `workflow_dispatch` — manual run from GitHub Actions UI
- `push: tags: 'v*'` — tag-triggered

Build: `flutter build apk --release --target-platform android-arm64`  
Artefact: APK uploaded as workflow artefact AND attached to a GitHub Release (with auto-generated notes) on tag push.  
Requires `permissions: contents: write` on the job.

---

## Key Architectural Decisions

| Decision | Rationale |
|---|---|
| Flutter over MAUI | MAUI too fragile; Flutter owns rendering stack = consistent cross-platform |
| Provider over Riverpod/Bloc | Right size for MVP; familiar DI mental model; easy to migrate later |
| Hive over SQLite | Hierarchical data (subtasks embedded in goals); no joins needed |
| Hive DTOs separate from domain models | Domain stays pure; Hive concern contained to `services/hive/` |
| `GoalRepository` as abstract class | Enables swap to SQLite/Firestore by changing one line in `main.dart` |
| `ChangeNotifier` on repository | Pragmatic compromise; acknowledged smell; justified at MVP scale |
| Two-state `SubTaskState` | Unrepresentable invalid state; current = derived from position |
| `Goal` as aggregate root | Subtasks never mutate independently; all operations go through `GoalService → Goal` |
| `Slidable` over `Dismissible` | `Dismissible` swallows `IconButton` taps on trailing edges; also throws "Dismissed Dismissible still in tree" when Provider rebuild races dismiss animation. |
| Star `IconButton` for focus toggle | Previous swipe-right caused goal duplication because `Dismissible` confirmed dismissal before Provider rebuild could update the list. |
| `todayOrder` on `Goal`, not a separate entity | "Today queue" state is just two fields (`isFocusedToday`, `todayOrder`); extraction to `TodaySession` deferred until daily-reset logic is built, which is the natural trigger. |
| Notification channel `focus_task_v2` | Android locks channel importance at creation; versioned ID forces recreation with new importance settings. |
| `DecompositionState` as standalone `ChangeNotifierProvider` | Not a `ProxyProvider` — must survive LLM settings changes without losing in-flight tracking. A `ProxyProvider` would recreate it whenever `LlmSettingsService` notifies. |
| Material Icons instead of emoji picker | Simplifies theming, removes dependency fragility, and gives consistent design language. `icon_catalog.dart` provides 665 curated names; legacy Unicode emoji strings still render via `GoalSymbol` fallback. |
| Dropped Goblin Tools support | Complexity reduction — maintains single OpenAI-compatible provider path. Goblin's limitation (no system prompt, no icon suggestions, no steering) didn't justify separate code path. |
| Icon names in catalog, not hardcoded | `icon_catalog.dart` with 16 categories is discoverable and extensible. Passed to LLM for `suggestIcon` via `iconByName.keys.toList()` in `main.dart`. |
| `GoalSymbol` inherits icon size from `IconTheme` | When no explicit size is set, the widget respects the ambient theme — meaning icons stay in sync with status badges without extra measurements. |
| `TextEditingController` in dialog as `StatefulWidget` | Disposing a controller owned by a `showDialog` caller while the dialog's exit animation is still running triggers `_dependents.isEmpty` assertion. Owning it in a `StatefulWidget` dialog ensures disposal happens after the widget is fully unmounted. |
| No tooltip on split button | `Tooltip` registers a `LongPressGestureRecognizer` that wins over an outer `GestureDetector`. Removing the tooltip lets the `GestureDetector.onLongPress` fire correctly to open the instructions sheet. |
| Inbox items don't auto-decompose | User intent: inbox is a true backlog. Auto-decomposing on capture would promote items to active without the user consciously deciding to act on them. |

---

## Quick Reference — Useful Commands

```bash
# Run tests (79 tests across 4 layers)
flutter test

# Analyze code (strict checks)
flutter analyze

# Generate Hive adapters after editing @HiveType/@HiveField
flutter pub run build_runner build --delete-conflicting-outputs

# Regenerate app icons from logos/app-icon-1024.png
flutter pub run flutter_launcher_icons

# Build release APK (arm64)
flutter build apk --release --target-platform android-arm64

# Run the app in debug mode
flutter run

# Format code
dart format lib/ test/

# View the interactive project structure
# (Open this file's Project Structure section)
```

---

## Developer Notes & Gotchas

- **App name:** "Todo App" in code and comments. "PicoClaw" is a container/infra name — don't use it in Flutter code.
- **Sample data:** `SampleData` class in `sample_data.dart` — delete before shipping. `HiveGoalRepository` seeds from it when the Hive box is empty.
- **Nullable getter capture:** When using a nullable computed getter (e.g. `currentSubTask`) multiple times in a method, capture it in a local variable first. Dart flow analysis won't smart-cast through a getter.
- **`context.mounted` after async gaps:** Always check before using `BuildContext` after any `await` or `addPostFrameCallback`.
- **`GoalRepository.save()` uses `goalId` as the Hive key** — `_box.put(goal.goalId, dto)`. Never use `_box.add()` / `_box.addAll()` — those use auto-incrementing integer keys and will create duplicate entries that `delete(goalId)` can never reach.
- **Hive adapter `writeByte(n)` is the field count, not the index** — the first argument to `writeByte` in the `write()` method is the total number of fields written. Currently `9` for `GoalDto` (including `emoji` at index 8).
- **`_recalculateStatus()` is not called from the constructor** — status is stored exactly as set. This matters for tests and for Hive rehydration.
- **`Slidable` key must be `ValueKey(subtaskId)`** — ensures Flutter reuses widget elements across rebuilds.
- **`cascade (..)` in DTO mapping** — sets multiple fields on one object without repeating the variable name; used extensively in `_toDto()` and `_subTaskToDto()`.
- **`late final` for controllers** — initialised in `initState()`, disposed in `dispose()`.
- **Notification suppress cache** — `NotificationService` stores `_shownGoalId` / `_shownSubtaskId`; `update()` is a no-op if both match. This prevents sound/vibration on every app resume when state hasn't changed.
- **`ReorderableListView` index convention** — `newIndex` from `onReorder` is one past the drop target when moving an item downward. `GoalService.reorderTodayQueue` normalises this with `if (newIndex > oldIndex) newIndex -= 1`.
- **`Card.clipBehavior: Clip.hardEdge`** — required on `_FocusGoalCard` so the `InkWell` ripple is clipped to the card's rounded corners.
- **LLM `additionalInstructions` null vs empty string** — callers pass `null` when no instructions are provided (not an empty string). `OpenAiDecompositionClient` checks `isNotEmpty` before applying. Passing `null` produces identical output to having no instructions field at all.
- **`GoalDetailScreen` is a `StatefulWidget`** — converted from `StatelessWidget` to support `DecompositionState` listener for fallback snackbars and the `triggerBreakdown` post-frame callback. `context.watch<DecompositionState>()` still lives in `build()` for the loading UI.
- **`GoalSymbol` size is nullable** — when `null`, inherits the ambient `IconTheme.size` (or defaults to 24.0). This keeps icons visually aligned with `_StatusBadge` icons without manual size tuning.
- **Icon catalog names must be unique** — `iconByName` is a flat map keyed by name across all categories. Adding a duplicate name will silently overwrite the earlier entry.
