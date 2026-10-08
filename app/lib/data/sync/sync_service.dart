import 'dart:async';

import 'package:flutter/foundation.dart';

import '../local/app_database.dart';
import '../remote/remote_store.dart';
import '../repositories/task_repository.dart';

enum SyncPhase { idle, syncing, error }

@immutable
class SyncStatus {
  const SyncStatus({this.phase = SyncPhase.idle, this.lastSyncedAt, this.message});
  final SyncPhase phase;
  final DateTime? lastSyncedAt;
  final String? message;

  SyncStatus copyWith({SyncPhase? phase, DateTime? lastSyncedAt, String? message}) =>
      SyncStatus(phase: phase ?? this.phase, lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt, message: message);
}

/// Copies local changes to the server and server changes to the local database.
///
/// Sync runs when started, a couple of seconds after any local edit, whenever
/// another device changes something (realtime), and every few minutes as a
/// fallback. Failures are retried on the next trigger; the app keeps working
/// offline in the meantime.
class SyncService {
  SyncService({
    required this.repo,
    required this.remote,
    required this.db,
    this.debounce = const Duration(seconds: 2),
    this.interval = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const _taskCursorKey = 'sync_cursor_tasks';
  static const _categoryCursorKey = 'sync_cursor_categories';

  final TaskRepository repo;
  final RemoteStore remote;
  final AppDatabase db;
  final Duration debounce;
  final Duration interval;
  final DateTime Function() _clock;

  final status = ValueNotifier(const SyncStatus());
  final _subs = <StreamSubscription<void>>[];
  Timer? _debounceTimer;
  Timer? _periodic;
  Future<void>? _running;
  bool _again = false;

  void start() {
    _subs
      ..add(repo.localChanges.listen((_) => _schedule()))
      ..add(remote.changes().listen((_) => _schedule()));
    _periodic = Timer.periodic(interval, (_) => syncNow());
    syncNow();
  }

  void _schedule() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, syncNow);
  }

  /// Runs one sync. If one is already running, another runs straight after it.
  Future<void> syncNow() {
    if (_running != null) {
      _again = true;
      return _running!;
    }
    return _running = _loop().whenComplete(() => _running = null);
  }

  Future<void> _loop() async {
    do {
      _again = false;
      await _syncOnce();
    } while (_again);
  }

  Future<void> _syncOnce() async {
    status.value = status.value.copyWith(phase: SyncPhase.syncing);
    try {
      // Push first so our edits aren't overwritten by older server copies.
      final categories = await repo.dirtyCategories();
      await remote.upsertCategories(categories);
      await repo.markCategoriesClean(categories);
      final tasks = await repo.dirtyTasks();
      await remote.upsertTasks(tasks);
      await repo.markTasksClean(tasks);

      await _pull(_categoryCursorKey, remote.fetchCategoriesSince, repo.applyRemoteCategories);
      await _pull(_taskCursorKey, remote.fetchTasksSince, repo.applyRemoteTasks);

      status.value = SyncStatus(phase: SyncPhase.idle, lastSyncedAt: _clock());
    } catch (e) {
      debugPrint('Sync failed: $e');
      status.value = status.value.copyWith(phase: SyncPhase.error, message: 'Couldn’t sync — will retry');
    }
  }

  Future<void> _pull<T>(
    String key,
    Future<RemotePage<T>> Function(String? cursor) fetch,
    Future<int> Function(List<T>) apply,
  ) async {
    var cursor = await db.getSetting(key);
    while (true) {
      final page = await fetch(cursor);
      await apply(page.rows);
      cursor = page.cursor;
      await db.setSetting(key, cursor);
      if (page.rows.length < RemoteStore.pageSize) break;
    }
  }

  /// Forget pull progress, e.g. after switching account.
  Future<void> resetCursors() async {
    await db.setSetting(_taskCursorKey, null);
    await db.setSetting(_categoryCursorKey, null);
  }

  Future<void> stop() async {
    _debounceTimer?.cancel();
    _periodic?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _running;
  }
}
