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
- **Filter, search and colour coding:** each category has its own colour, and priority is shown with leaf badges. When filters hide tasks, a "Showing only: …" banner says so, with a Clear filters button.
- **This week:** the *due*, *done* and *overdue* boxes are buttons. Click one to see those tasks.
- **Finished tasks stay visible:** a "Recently done" section sits under "Do next", and the Status filter has a Done view.
- **Repeating tasks:** ticking a Daily, Weekly or Monthly task marks it done, and the next one appears the day after. A repeating task can only be ticked from one repeat before its due date, so it can't be pushed weeks ahead by accident.

The UI mockup is described in [design/README.md](design/README.md). Screenshots of the working app are in [design/app-screenshots/](design/app-screenshots/).

## Running the app

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.47 or newer, which includes Dart 3.13).

```bash
cd app
flutter pub get
flutter run -d windows      # or macos, linux, or an Android phone/emulator
```

Without any extra settings, the app keeps tasks on the device it runs on. To sync between phone and computer, set up Supabase (below) and pass its details when you run or build:

```bash
flutter run --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
            --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
flutter build apk --release --dart-define=...   # Android
flutter build windows --release --dart-define=... # Windows
```

### Setting up sync (one time)

Sync uses [Supabase](https://supabase.com). **You** create each person's account in the Supabase dashboard. The app has no sign-up screen and sends no emails, so you don't need to set up email or a mail server.

1. Create a free project at [supabase.com](https://supabase.com).
2. In the project's **SQL Editor**, paste and run [supabase/migrations/0001_tasks.sql](supabase/migrations/0001_tasks.sql). Or, with the Supabase CLI: `supabase link` then `supabase db push`.
3. In the dashboard (menu names may differ slightly), go to **Authentication → Sign In / Providers**:
   - Make sure **Email** is on.
   - Turn **off** "Allow new users to sign up", so only the accounts you add can sign in.
   - Turn **off** "Confirm email". Accounts you add yourself don't need a confirmation email.
4. Copy the **Project URL** and **publishable key** from **Project Settings → API Keys**, and use them in the `--dart-define` flags above.

#### Adding a user

1. In the dashboard, open **Authentication → Users → Add user → Create new user**.
2. Type their **email** and a **password**.
3. Tick **Auto Confirm User**, so they can sign in straight away without an email.
4. Give them the email and password. They can use them on the phone and the computer.

To remove someone, or to change their password, open the same **Users** list and use the menu next to their name. Each person only ever sees their own tasks: row-level security in the migration enforces this.

#### Signing in

In the app, go to **Settings → Sign in to sync**, type the email and password, and press **Sign in**. Tasks added before signing in are uploaded automatically. Use the same account on every device and the tasks stay in step. You can sign out from the same Settings page.

If sign-in fails, the app says whether the email or password was wrong, or whether it couldn't reach the server.

### Developing

```bash
cd app
flutter analyze
flutter test                                        # all Dart tests (unit, sync, widget)
flutter test --coverage && dart run tool/check_coverage.dart 95
dart run build_runner build                         # after changing the database tables
SCREENSHOTS=1 flutter test --update-goldens test/screenshots   # refresh design/app-screenshots
```

The database migration has its own tests, which run it on a real PostgreSQL server (you need `psql` and a
server you can create databases on):

```bash
PGHOST=localhost PGUSER=postgres PGPASSWORD=postgres supabase/tests/run.sh
```

## Automated checks and releases (GitHub Actions)

| Workflow | When | What it does |
|---|---|---|
| [CI](.github/workflows/ci.yml) | every push and pull request | checks formatting, runs the analyzer, all tests with a 95% coverage minimum, the SQL tests on PostgreSQL 16, then builds the Linux, Windows, macOS and Android apps |
| [Release](.github/workflows/release.yml) | pushing a tag like `v1.0.0` | re-runs the checks, builds the four apps, and attaches them to a GitHub Release with generated notes |

To publish a release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

Add the repository secrets `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` (Settings → Secrets and variables → Actions) if the released apps should sync. Without them the apps work, but keep tasks on one device. The Android file is signed with Flutter's debug key: it installs by tapping the file on a phone, but it can't go on the Play Store until a release keystore is set up.

## Recommended framework

| Layer | Choice | Why |
|---|---|---|
| UI / app | **Flutter (Dart)** | One codebase builds for Android, Windows, macOS and Linux (and web later). It handles a fully custom panda theme well, and works with both mouse and touch. |
| State | **Riverpod** | Simple and testable. Works well with streams from the local database. |
| Local storage | **Drift (SQLite)** | Offline-first: the app always reads and writes locally, so it works without internet. |
| Sync / auth | **Supabase** (Postgres + Auth) | Email and password sign-in, with accounts added by you in the dashboard. Row-level security keeps each user's data private. |
| Calendar | `table_calendar` | Week and month views, restyled with the panda theme. |
| Routing | `go_router` | Bottom navigation bar on phone, side rail on desktop. |

### How sync works
1. The UI only ever talks to the local Drift database, so it stays fast and works offline.
2. `SyncService` pushes rows that changed locally to Supabase. It compares `updated_at` timestamps, and the most recent change wins.
3. `SyncService` pulls remote changes regularly in the background, and catches up fully when the app starts and after signing in.
4. Deleted tasks are not removed straight away. They are marked with `deleted_at` (a soft delete), so the deletion syncs to the other device.
5. The server ignores a write that is older than the copy it already has, and stamps every row with its own `server_updated_at`, so devices with wrong clocks still pull every change.

## Project structure

```
BamBoozled/
├── README.md
├── docs/
│   ├── task-format.md              # recommended task format
│   └── priority-algorithm.md       # "Do next" scoring
├── design/                         # Figma link, exported frames, app screenshots
├── supabase/
│   ├── migrations/0001_tasks.sql   # tasks, categories + RLS policies
│   └── tests/                      # SQL tests, run on a real PostgreSQL
├── .github/workflows/              # ci.yml, release.yml
└── app/                            # Flutter project
    ├── pubspec.yaml
    ├── android/ windows/ macos/ linux/
    ├── tool/check_coverage.dart    # the coverage gate used by CI
    ├── lib/
    │   ├── main.dart               # start-up
    │   ├── app.dart                # routes, theme, keeps sync and repeats running
    │   ├── core/                   # theme, layout breakpoints, shared widgets, date helpers
    │   ├── data/
    │   │   ├── local/              # Drift tables and database (SQLite)
    │   │   ├── remote/             # Supabase: sign-in (auth_service) and task upload/download
    │   │   ├── sync/sync_service.dart
    │   │   ├── repositories/task_repository.dart   # the only code that changes tasks
    │   │   └── providers.dart      # Riverpod wiring
    │   ├── domain/                 # Task, Category, Priority, Repeat, PriorityScorer (pure Dart)
    │   └── features/
    │       ├── welcome/            # Welcome page, filters, calendar panel, Do next, This week
    │       ├── calendar/  tasks/  settings/  auth/  notes/
    └── test/                       # unit, sync, widget and screenshot tests
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
