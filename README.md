# BamBoozled 🐼

A friendly, panda-themed notetaking and task app for Android and desktop. Tasks sync between your phone and your computer.

BamBoozled is built for people who aren't technical. Everything works by tapping or clicking:
- big buttons (at least 48px)
- chips and pickers instead of typed syntax
- no command line

## Milestone 1 — Welcome page

The welcome page has:
- **Calendar:** see this week's and this month's tasks, switching between a Week and a Month view.
- **Add task:** a guided form. See [docs/task-format.md](docs/task-format.md).
- **Do next 🎋:** a recommended order to do tasks in, scored from each task's deadline and its priority. See [docs/priority-algorithm.md](docs/priority-algorithm.md).
- **Filter, search and colour coding:** each category has its own colour, and priority is shown with leaf badges.

The UI mockup is described in [design/README.md](design/README.md).

## Recommended framework

| Layer | Choice | Why |
|---|---|---|
| UI / app | **Flutter 3 (Dart)** | One codebase builds for Android, Windows, macOS and Linux (and web later). It handles a fully custom panda theme well, and works with both mouse and touch. |
| State | **Riverpod** | Simple and testable. Works well with streams from the local database. |
| Local storage | **Drift (SQLite)** | Offline-first: the app always reads and writes locally, so it works without internet. |
| Sync / auth | **Supabase** (Postgres + Auth + Realtime) | Sign-in by email magic link or Google. Row-level security keeps each user's data private. |
| Calendar | `table_calendar` | Week and month views, restyled with the panda theme. |
| Routing | `go_router` | Bottom navigation bar on phone, side rail on desktop. |

### How sync works
1. The UI only ever talks to the local Drift database, so it stays fast and works offline.
2. `SyncService` pushes rows that changed locally to Supabase. It compares `updated_at` timestamps, and the most recent change wins.
3. `SyncService` pulls remote changes through Supabase Realtime, plus a full catch-up when the app starts.
4. Deleted tasks are not removed straight away. They are marked with `deleted_at` (a soft delete), so the deletion syncs to the other device.

## Project structure

```
BamBoozled/
├── README.md
├── docs/
│   ├── task-format.md              # recommended task format
│   └── priority-algorithm.md       # "Do next" scoring
├── design/                         # Figma link + exported frames
├── supabase/
│   ├── migrations/0001_tasks.sql   # tasks, categories + RLS policies
│   └── config.toml
└── app/                            # Flutter project
    ├── pubspec.yaml
    ├── android/ windows/ macos/ linux/
    ├── assets/  (fonts/, illustrations/ panda SVGs, icons/)
    ├── lib/
    │   ├── main.dart
    │   ├── app.dart                         # MaterialApp.router, theme
    │   ├── core/
    │   │   ├── theme/  (colors.dart, typography.dart, panda_theme.dart)
    │   │   ├── layout/adaptive_scaffold.dart  # phone vs desktop breakpoints
    │   │   └── utils/dates.dart
    │   ├── data/
    │   │   ├── local/  (app_database.dart, tables.dart)   # Drift
    │   │   ├── remote/supabase_client.dart
    │   │   ├── sync/sync_service.dart
    │   │   └── repositories/task_repository.dart
    │   ├── domain/
    │   │   ├── models/  (task.dart, category.dart, priority.dart)
    │   │   └── services/priority_scorer.dart   # pure Dart, unit-tested
    │   └── features/
    │       ├── welcome/
    │       │   ├── welcome_page.dart
    │       │   ├── welcome_controller.dart
    │       │   └── widgets/  (greeting_header, calendar_panel, week_strip,
    │       │                  do_next_list, task_card, filter_bar, search_field)
    │       ├── tasks/   (add_edit_task_sheet.dart, widgets/ category_picker,
    │       │             priority_picker, date_chips)
    │       ├── auth/
    │       └── notes/                       # later milestones
    └── test/  (priority_scorer_test.dart, task_repository_test.dart, widget tests)
```

## Visual language

| Token | Hex | Use |
|---|---|---|
| Ink | `#1E1E1E` | Text, panda accents |
| Rice | `#FAF8F3` | Background |
| Bamboo | `#7BAE7F` | Primary buttons, "Do next" |
| Blush | `#F4A6A6` | Category colour |
| Sky | `#9CC9E8` | Category colour |
| Honey | `#F2C879` | Category colour |
| Lavender | `#B9A7E0` | Category colour |
| Mint | `#9ED9C3` | Category colour |
| Overdue | `#E06666` | Overdue tasks |

- **Fonts:** Nunito, or Quicksand as an alternative. Body text is at least 16px.
- **Colour is never the only signal:** every coloured element also has a text label or an icon, for colour-blind users.
