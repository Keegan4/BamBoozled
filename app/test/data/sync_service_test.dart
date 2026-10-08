import 'dart:async';

import 'package:bamboozled/data/local/app_database.dart';
import 'package:bamboozled/data/remote/remote_store.dart';
import 'package:bamboozled/data/remote/supabase_remote_store.dart';
import 'package:bamboozled/data/repositories/task_repository.dart';
import 'package:bamboozled/data/sync/sync_service.dart';
import 'package:bamboozled/domain/models/category.dart';
import 'package:bamboozled/domain/models/priority.dart';
import 'package:bamboozled/domain/models/task.dart';
import 'package:drift/drift.dart' show DatabaseConnection, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in for Supabase that behaves like the SQL migration:
/// stale writes are ignored and every accepted write gets a new server stamp.
class FakeServer implements RemoteStore {
  final _tasks = <String, (Task, int)>{};
  final _categories = <String, (Category, int)>{};
  final _changes = StreamController<void>.broadcast();
  var _stamp = 0;
  bool offline = false;

  String _cursor(int stamp) => stamp.toString().padLeft(10, '0');

  void _check() {
    if (offline) throw Exception('offline');
  }

  @override
  Future<void> upsertTasks(List<Task> tasks) async {
    _check();
    for (final t in tasks) {
      final existing = _tasks[t.id];
      if (existing != null && t.updatedAt.isBefore(existing.$1.updatedAt)) continue;
      _tasks[t.id] = (t, ++_stamp);
    }
    if (tasks.isNotEmpty) _changes.add(null);
  }

  @override
  Future<void> upsertCategories(List<Category> categories) async {
    _check();
    for (final c in categories) {
      final existing = _categories[c.id];
      if (existing != null && c.updatedAt.isBefore(existing.$1.updatedAt)) continue;
      _categories[c.id] = (c, ++_stamp);
    }
  }

  RemotePage<T> _page<T>(Map<String, (T, int)> table, String? cursor) {
    final after = cursor == null ? 0 : int.parse(cursor);
    final rows = table.values.where((r) => r.$2 > after).toList()..sort((a, b) => a.$2.compareTo(b.$2));
    final page = rows.take(RemoteStore.pageSize).toList();
    return RemotePage([for (final r in page) r.$1], page.isEmpty ? cursor : _cursor(page.last.$2));
  }

  @override
  Future<RemotePage<Task>> fetchTasksSince(String? cursor) async {
    _check();
    return _page(_tasks, cursor);
  }

  @override
  Future<RemotePage<Category>> fetchCategoriesSince(String? cursor) async {
    _check();
    return _page(_categories, cursor);
  }

  @override
  Stream<void> changes() => _changes.stream;
}

class Device {
  Device(this.server, DateTime Function() clock, String name) {
    var n = 0;
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    repo = TaskRepository(db, clock: clock, newId: () => '$name-${n++}');
    sync = SyncService(repo: repo, remote: server, db: db, clock: clock);
  }
  final FakeServer server;
  late final AppDatabase db;
  late final TaskRepository repo;
  late final SyncService sync;

  Future<List<Task>> tasks() => repo.watchTasks().first;

  Future<void> close() async {
    await sync.stop();
    await repo.dispose();
    await db.close();
  }
}

void main() {
  // Each simulated device has its own in-memory database on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late FakeServer server;
  late DateTime now;
  late Device phone;
  late Device laptop;

  setUp(() async {
    server = FakeServer();
    now = DateTime(2026, 10, 8, 14);
    phone = Device(server, () => now, 'phone');
    laptop = Device(server, () => now, 'laptop');
    await phone.repo.ensureDefaultCategories();
    await laptop.repo.ensureDefaultCategories();
  });
  tearDown(() async {
    await phone.close();
    await laptop.close();
  });

  TaskDraft draft(String title) =>
      TaskDraft(title: title, dueAt: DateTime(2026, 10, 9, 17), priority: Priority.high, categoryId: 'teaching');

  test('a task added on the phone appears on the laptop', () async {
    await phone.repo.addTask(draft('Mark 3A essays'));
    await phone.sync.syncNow();
    await laptop.sync.syncNow();
    expect((await laptop.tasks()).single.title, 'Mark 3A essays');
    expect(phone.sync.status.value.phase, SyncPhase.idle);
    expect(phone.sync.status.value.lastSyncedAt, now);
  });

  test('edits, completion and deletion sync both ways', () async {
    final t = await phone.repo.addTask(draft('Plan CCA trip'));
    await phone.sync.syncNow();
    await laptop.sync.syncNow();

    now = now.add(const Duration(minutes: 1));
    await laptop.repo.setDone(t.id, true);
    await laptop.sync.syncNow();
    await phone.sync.syncNow();
    expect((await phone.tasks()).single.isDone, isTrue);

    now = now.add(const Duration(minutes: 1));
    await phone.repo.deleteTask(t.id);
    await phone.sync.syncNow();
    await laptop.sync.syncNow();
    expect(await laptop.tasks(), isEmpty);
  });

  test('offline edits on both devices: the newest edit wins everywhere', () async {
    final t = await phone.repo.addTask(draft('Original'));
    await phone.sync.syncNow();
    await laptop.sync.syncNow();

    now = now.add(const Duration(minutes: 1));
    await laptop.repo.updateTask(t.copyWith(title: 'Laptop edit'));
    now = now.add(const Duration(minutes: 1));
    await phone.repo.updateTask(t.copyWith(title: 'Phone edit (newer)'));

    // The phone syncs first, then the laptop pushes its older edit.
    await phone.sync.syncNow();
    await laptop.sync.syncNow();
    await phone.sync.syncNow();
    expect((await laptop.tasks()).single.title, 'Phone edit (newer)');
    expect((await phone.tasks()).single.title, 'Phone edit (newer)');
  });

  test('custom categories sync', () async {
    await phone.repo.addCategory('Exams', const Color(0xFFF2C879));
    await phone.sync.syncNow();
    await laptop.sync.syncNow();
    expect((await laptop.repo.watchCategories().first).map((c) => c.name), contains('Exams'));
  });

  test('pulls every page when there are many changes', () async {
    for (var i = 0; i < RemoteStore.pageSize + 20; i++) {
      await phone.repo.addTask(draft('Task $i'));
    }
    await phone.sync.syncNow();
    await laptop.sync.syncNow();
    expect(await laptop.tasks(), hasLength(RemoteStore.pageSize + 20));
  });

  test('failures are reported and local edits are kept for the next try', () async {
    server.offline = true;
    await phone.repo.addTask(draft('Written offline'));
    await phone.sync.syncNow();
    expect(phone.sync.status.value.phase, SyncPhase.error);
    expect(await phone.repo.dirtyTasks(), hasLength(1));

    server.offline = false;
    await phone.sync.syncNow();
    expect(phone.sync.status.value.phase, SyncPhase.idle);
    expect(await phone.repo.dirtyTasks(), isEmpty);
  });

  test('local edits trigger a sync after the debounce', () async {
    final fast = SyncService(
      repo: phone.repo,
      remote: server,
      db: phone.db,
      debounce: const Duration(milliseconds: 10),
    );
    fast.start();
    await fast.syncNow();
    await phone.repo.addTask(draft('Auto-synced'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await fast.syncNow();
    await fast.stop();
    expect(await phone.repo.dirtyTasks(), isEmpty);
    await laptop.sync.syncNow();
    expect((await laptop.tasks()).single.title, 'Auto-synced');
  });

  test('Supabase JSON mapping round-trips', () {
    final t = Task(
      id: 'x',
      title: 'Mark essays',
      dueAt: DateTime(2026, 10, 9, 17),
      priority: Priority.urgent,
      categoryId: 'teaching',
      estimateMinutes: 60,
      notes: 'Rubric in drive',
      repeat: Repeat.weekly,
      completedAt: DateTime(2026, 10, 9, 12, 30, 0, 250),
      createdAt: now,
      updatedAt: now,
    );
    final json = SupabaseRemoteStore.taskToJson(t, 'user-1');
    expect(json['user_id'], 'user-1');
    expect(json['due_at'], endsWith('Z'));
    // The server returns the extra server_updated_at column too.
    expect(SupabaseRemoteStore.taskFromJson({...json, 'server_updated_at': '2026-10-08T06:00:00Z'}), t);

    final c = Category(id: 'c', name: 'Exams', color: const Color(0xFFF2C879), sortOrder: 6, updatedAt: now);
    expect(SupabaseRemoteStore.categoryFromJson(SupabaseRemoteStore.categoryToJson(c, 'user-1')), c);
  });
}
