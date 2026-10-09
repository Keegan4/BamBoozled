import 'dart:async';

import 'package:bamboozled/data/local/app_database.dart';
import 'package:bamboozled/data/remote/auth_service.dart';
import 'package:bamboozled/data/remote/remote_store.dart';
import 'package:bamboozled/data/repositories/task_repository.dart';
import 'package:bamboozled/data/sync/sync_service.dart';
import 'package:bamboozled/domain/models/category.dart';
import 'package:bamboozled/domain/models/task.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// In-memory stand-in for Supabase that behaves like the SQL migration:
/// stale writes are ignored and every accepted write gets a new server stamp.
class FakeServer implements RemoteStore {
  final _tasks = <String, (Task, int)>{};
  final _categories = <String, (Category, int)>{};
  final _changes = StreamController<void>.broadcast();
  var _stamp = 0;
  bool offline = false;
  int taskUpserts = 0;
  Iterable<Task> get tasks => _tasks.values.map((e) => e.$1);

  String _cursor(int stamp) => stamp.toString().padLeft(10, '0');

  void _check() {
    if (offline) throw Exception('offline');
  }

  @override
  Future<void> upsertTasks(List<Task> tasks) async {
    _check();
    for (final t in tasks) {
      taskUpserts++;
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

User fakeUser({String id = 'user-1', String email = 'ms.tan@school.edu.sg'}) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: DateTime(2026, 10, 1).toIso8601String(),
  email: email,
);

/// Stand-in for [AuthService] that records calls and can be told to fail.
class FakeAuthService implements AuthService {
  FakeAuthService({this._user});

  User? _user;
  final _controller = StreamController<User?>.broadcast();
  final sentCodes = <String>[];
  final verified = <(String, String)>[];
  bool failSend = false;
  bool failVerify = false;
  int signOuts = 0;

  @override
  SupabaseClient get client => throw UnimplementedError('FakeAuthService has no client');

  @override
  User? get currentUser => _user;

  @override
  Stream<User?> userChanges() async* {
    yield _user;
    yield* _controller.stream;
  }

  @override
  Future<void> sendCode(String email) async {
    if (failSend) throw Exception('offline');
    sentCodes.add(email.trim());
  }

  @override
  Future<void> verifyCode(String email, String code) async {
    if (failVerify) throw Exception('bad code');
    verified.add((email.trim(), code.trim()));
    _user = fakeUser(email: email.trim());
    _controller.add(_user);
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    _user = null;
    _controller.add(null);
  }
}

/// A phone or laptop: its own database, repository and sync service, sharing one [FakeServer].
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
