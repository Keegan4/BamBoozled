import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/theme/appearance.dart';
import '../domain/models/category.dart';
import '../domain/models/daily_note.dart';
import '../domain/services/daily_note_picker.dart';
import '../domain/models/task.dart';
import 'canvas/canvas_service.dart';
import 'daily_notes/daily_note_library.dart';
import 'daily_notes/daily_note_store.dart';
import 'local/app_database.dart';
import 'remote/auth_service.dart';
import 'remote/supabase_remote_store.dart';
import 'repositories/task_repository.dart';
import 'sync/sync_service.dart';

/// Overridden in main() (and in tests) with an opened database.
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('databaseProvider not overridden'));

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  final repo = TaskRepository(ref.watch(databaseProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

/// Null when the build has no Supabase settings (offline-only mode).
final supabaseClientProvider = Provider<SupabaseClient?>((ref) => null);

final authServiceProvider = Provider<AuthService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : AuthService(client);
});

final currentUserProvider = StreamProvider<User?>((ref) {
  final auth = ref.watch(authServiceProvider);
  return auth == null ? Stream.value(null) : auth.userChanges();
});

/// Running sync for the signed-in user, or null when signed out / not configured.
final syncServiceProvider = Provider<SyncService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final userId = ref.watch(currentUserProvider.select((u) => u.value?.id));
  if (client == null || userId == null) return null;
  final sync = SyncService(
    repo: ref.watch(taskRepositoryProvider),
    remote: SupabaseRemoteStore(client),
    db: ref.watch(databaseProvider),
  );
  unawaited(sync.startFor(userId));
  ref.onDispose(sync.stop);
  return sync;
});

final syncStatusProvider = StreamProvider<SyncStatus?>((ref) {
  final sync = ref.watch(syncServiceProvider);
  if (sync == null) return Stream.value(null);
  final controller = StreamController<SyncStatus?>();
  void push() => controller.add(sync.status.value);
  push();
  sync.status.addListener(push);
  ref.onDispose(() {
    sync.status.removeListener(push);
    controller.close();
  });
  return controller.stream;
});

/// "Now", refreshed every minute so due labels and overdue states stay current.
/// Tests override this with a fixed time.
final clockProvider = NotifierProvider<ClockNotifier, DateTime>(ClockNotifier.new);

class ClockNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final timer = Timer.periodic(const Duration(minutes: 1), (_) => state = DateTime.now());
    ref.onDispose(timer.cancel);
    return DateTime.now();
  }
}

/// Brings back each repeating task the day after it was finished. Watch it once, near the top of
/// the app: it re-checks whenever the tasks or the day change.
final repeatSpawnerProvider = Provider<void>((ref) {
  ref.watch(tasksProvider);
  ref.watch(clockProvider.select((d) => DateTime(d.year, d.month, d.day)));
  final repo = ref.watch(taskRepositoryProvider);
  Future.microtask(repo.spawnNextRepeats);
});

/// True in the web version, which has to fetch Canvas feeds through Supabase (see
/// [fetchFeedViaSupabase]).
final canvasNeedsProxyProvider = Provider<bool>((ref) => kIsWeb);

/// True in the web version, which draws everything a little smaller on phones (see CompactScale).
final compactPhoneLayoutProvider = Provider<bool>((ref) => kIsWeb);

/// How Canvas feeds are downloaded. Tests swap in sample feeds.
final canvasFetcherProvider = Provider<FeedFetcher>(
  (ref) => ref.watch(canvasNeedsProxyProvider)
      ? (uri) => fetchFeedViaSupabase(ref.read(supabaseClientProvider), uri)
      : fetchFeedOverHttp,
);

final canvasServiceProvider = Provider<CanvasService>(
  (ref) => CanvasService(
    db: ref.watch(databaseProvider),
    repo: ref.watch(taskRepositoryProvider),
    fetch: ref.watch(canvasFetcherProvider),
  ),
);

final canvasStatusProvider = StreamProvider<CanvasStatus>(
  (ref) => ref.watch(databaseProvider).watchSetting(CanvasStatus.key).map(CanvasStatus.fromSetting),
);

/// While connected to Canvas, reads the feed when the app opens and then every hour. Watch it once,
/// near the top of the app.
final canvasAutoRefreshProvider = Provider<void>((ref) {
  final url = ref.watch(canvasStatusProvider.select((s) => s.value?.feedUrl));
  if (url == null) return;
  final canvas = ref.watch(canvasServiceProvider);
  Future.microtask(canvas.refresh);
  final timer = Timer.periodic(const Duration(hours: 1), (_) => canvas.refresh());
  ref.onDispose(timer.cancel);
});

final tasksProvider = StreamProvider<List<Task>>((ref) => ref.watch(taskRepositoryProvider).watchTasks());

final categoriesProvider = StreamProvider<List<Category>>((ref) => ref.watch(taskRepositoryProvider).watchCategories());

final categoryMapProvider = Provider<Map<String, Category>>(
  (ref) => {for (final c in ref.watch(categoriesProvider).value ?? const <Category>[]) c.id: c},
);

const displayNameKey = 'display_name';

final displayNameProvider = StreamProvider<String?>((ref) => ref.watch(databaseProvider).watchSetting(displayNameKey));

/// Light, dark, match the device, or dark on a schedule (Settings → Appearance).
final appearanceProvider = StreamProvider<Appearance>(
  (ref) => ref.watch(databaseProvider).watchSetting(Appearance.key).map(Appearance.fromSetting),
);

/// The theme mode to show now. On a schedule it changes within a minute of the set time, because
/// [clockProvider] ticks every minute.
final themeModeProvider = Provider<ThemeMode>((ref) {
  final appearance = ref.watch(appearanceProvider).value ?? const Appearance();
  if (appearance.mode != AppearanceMode.scheduled) return appearance.themeModeAt(DateTime(0));
  return ref.watch(clockProvider.select(appearance.themeModeAt));
});

// ---- Daily cards (Notes tab) ----

/// Where bundled files come from. Tests can swap in their own.
final assetBundleProvider = Provider<AssetBundle>((ref) => rootBundle);

final dailyNotesProvider = FutureProvider<DailyNoteLibrary>((ref) => loadDailyNotes(ref.watch(assetBundleProvider)));

final dailyNoteStoreProvider = Provider<DailyNoteStore>((ref) => DailyNoteStore(ref.watch(databaseProvider)));

final dailyNoteStateProvider = StreamProvider<DailyNoteState>((ref) => ref.watch(dailyNoteStoreProvider).watch());

/// Shuffles the cards per person: the account id when signed in (so phone and computer agree),
/// otherwise an id made once for this install.
final dailyNoteSeedProvider = FutureProvider<String>((ref) async {
  final userId = ref.watch(currentUserProvider.select((u) => u.value?.id));
  return userId ?? ref.watch(dailyNoteStoreProvider).installId(const Uuid().v4);
});

/// Today's card, or null when there are no cards. A card already revealed today stays today's card,
/// even if the shuffle would now pick another (e.g. after signing in).
final todaysNoteProvider = Provider<AsyncValue<DailyNote?>>((ref) {
  final today = ref.watch(clockProvider.select((d) => DateTime(d.year, d.month, d.day)));
  final library = ref.watch(dailyNotesProvider);
  final state = ref.watch(dailyNoteStateProvider);
  final seed = ref.watch(dailyNoteSeedProvider);
  if (library.hasError) return AsyncValue.error(library.error!, library.stackTrace!);
  if (!library.hasValue || !state.hasValue || !seed.hasValue) return const AsyncValue.loading();
  final notes = {for (final n in library.value!.notes) n.id: n};
  final pinned = notes[state.value!.opened[DailyNoteState.dateKey(today)]];
  if (pinned != null) return AsyncValue.data(pinned);
  final id = DailyNotePicker.pick(notes.keys, seed.value!, today);
  return AsyncValue.data(id == null ? null : notes[id]);
});
