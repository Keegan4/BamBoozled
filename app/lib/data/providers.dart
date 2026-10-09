import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models/category.dart';
import '../domain/models/task.dart';
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

final tasksProvider = StreamProvider<List<Task>>((ref) => ref.watch(taskRepositoryProvider).watchTasks());

final categoriesProvider = StreamProvider<List<Category>>((ref) => ref.watch(taskRepositoryProvider).watchCategories());

final categoryMapProvider = Provider<Map<String, Category>>(
  (ref) => {for (final c in ref.watch(categoriesProvider).value ?? const <Category>[]) c.id: c},
);

const displayNameKey = 'display_name';

final displayNameProvider = StreamProvider<String?>((ref) => ref.watch(databaseProvider).watchSetting(displayNameKey));
