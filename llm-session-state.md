# Todo App — LLM Session State
**Last updated:** 2026-05-13  
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
- **Inbox promotion** — adding the first subtask to an inbox goal automatically promotes it to `active`
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

### Post-MVP / Planned
- **Daily reset** — Focus list resets each day; carry-over rules TBD; this is the trigger for extracting `todayOrder`/`isFocusedToday` into a separate `TodaySession` object
- **LLM decomposition** — `GoalDecompositionService._scaffoldSubTasks()` is the exact seam; replace body with Ollama / llama.cpp call; signature stays the same
- **Micro-rewards** — visual/audio feedback on subtask completion
- **Neglect priority** — tasks untouched >24h boosted (`lastSeenDate` already tracked on `SubTask`)
- **Deadline priority** — goals with nearest `dueDate` weighted higher
- **Inbox processing wizard** — guided flow to convert inbox items into structured goals
- **Multi-platform sync** — backend for cross-device state
- **Mobile widget** — single-tap idea capture from home screen
- **Voice capture** — hands-free input
- **Focus mode** — integrated Pomodoro timer per subtask

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
- `ProxyProvider<GoalRepository, GoalService>` — service depends on repo
- `ProxyProvider<GoalRepository, GoalQueries>` — queries depend on repo
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
- `showsUserInterface: false` on the action button (was `true` during debugging; reverted to user preference)
- Cold-start: `getNotificationAppLaunchDetails()` replays the last action on first init

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
│   ├── goals_screen.dart               — Goals tab: active+completed goals, star toggle, delete
│   ├── inbox_screen.dart               — Inbox tab: undecomposed goals, tap to open detail
│   ├── goal_detail_screen.dart         — subtask CRUD, reorder, complete, undo
│   └── widgets/
│       ├── app_bottom_sheet.dart       — shared sheet chrome (handle, padding, keyboard avoid)
│       └── new_goal_sheet.dart         — new goal form; Create pops with goalId, Inbox pops with null
├── services/
│   ├── goal_decomposition_service.dart — _scaffoldSubTasks() seam for future LLM
│   ├── goal_queries.dart               — read projections: todayQueue (sorted), goals, inbox
│   ├── goal_repository.dart            — abstract GoalRepository + InMemoryGoalRepository
│   ├── goal_service.dart               — all mutations incl. toggleFocusToday, reorderTodayQueue
│   ├── notification_service.dart       — persistent Android notification; update(), init(), _onResponse()
│   ├── sample_data.dart                — seed data — DELETE BEFORE SHIPPING
│   └── hive/
│       ├── goal_dto.dart               — Hive DTO (typeId: 0), field index registry in comments
│       ├── goal_dto.g.dart             — generated — DO NOT EDIT (hand-edit for field 7 todayOrder was needed)
│       ├── hive_goal_repository.dart   — concrete Hive impl; seeds from SampleData if box empty
│       ├── sub_task_dto.dart           — Hive DTO (typeId: 1), field index registry in comments
│       └── sub_task_dto.g.dart         — generated — DO NOT EDIT
└── theme/
    ├── app_colors.dart                 — centralised colour palette (see Theme section)
    └── app_icons.dart                  — centralised icon constants (semantic names)

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
| — | Next available | **8** |

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
`goal_dto.g.dart` was hand-edited to add fields 6 (`isFocusedToday`) and 7 (`todayOrder`). `writeByte(n)` in the adapter's `write()` method is the **total field count** (currently `8`), not an index.

---

## Theme System

### `AppColors` — `lib/theme/app_colors.dart`
All colours centralised here. Changing `accent` propagates to the Material seed colour, all explicit icon colours, and progress indicators.

| Name | Value | Used for |
|---|---|---|
| `faded` | `Colors.grey.shade400` | Completed subtask drag handle |
| `muted` | `Colors.grey.shade600` | Secondary icons, hints, subtitles |
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
  flutter_local_notifications: ^17.0  # persistent Android notification

dev_dependencies:
  flutter_test: sdk: flutter          # test framework
  hive_generator: ^2.0.1             # TypeAdapter code generation
  build_runner: ^2.4.0               # runs code generation
```

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

---

## Developer Notes & Gotchas

- **App name:** "Todo App" in code and comments. "PicoClaw" is a container/infra name — don't use it in Flutter code.
- **Sample data:** `SampleData` class in `sample_data.dart` — delete before shipping. `HiveGoalRepository` seeds from it when the Hive box is empty.
- **Nullable getter capture:** When using a nullable computed getter (e.g. `currentSubTask`) multiple times in a method, capture it in a local variable first. Dart flow analysis won't smart-cast through a getter.
- **`context.mounted` after async gaps:** Always check before using `BuildContext` after any `await` or `addPostFrameCallback`.
- **`GoalRepository.save()` uses `goalId` as the Hive key** — `_box.put(goal.goalId, dto)`. Never use `_box.add()` / `_box.addAll()` — those use auto-incrementing integer keys and will create duplicate entries that `delete(goalId)` can never reach.
- **Hive adapter `writeByte(n)` is the field count, not the index** — the first argument to `writeByte` in the `write()` method is the total number of fields written. Currently `8` for `GoalDto`.
- **`_recalculateStatus()` is not called from the constructor** — status is stored exactly as set. This matters for tests and for Hive rehydration.
- **`Slidable` key must be `ValueKey(subtaskId)`** — ensures Flutter reuses widget elements across rebuilds.
- **`cascade (..)` in DTO mapping** — sets multiple fields on one object without repeating the variable name; used extensively in `_toDto()` and `_subTaskToDto()`.
- **`late final` for controllers** — initialised in `initState()`, disposed in `dispose()`.
- **Notification suppress cache** — `NotificationService` stores `_shownGoalId` / `_shownSubtaskId`; `update()` is a no-op if both match. This prevents sound/vibration on every app resume when state hasn't changed.
- **`ReorderableListView` index convention** — `newIndex` from `onReorder` is one past the drop target when moving an item downward. `GoalService.reorderTodayQueue` normalises this with `if (newIndex > oldIndex) newIndex -= 1`.
- **`Card.clipBehavior: Clip.hardEdge`** — required on `_FocusGoalCard` so the `InkWell` ripple is clipped to the card's rounded corners.
