import 'dart:async';

import 'package:flutter/painting.dart' show Color;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/category.dart';
import '../../domain/models/priority.dart';
import '../../domain/models/task.dart';
import 'remote_store.dart';

/// [RemoteStore] backed by the Supabase tables in supabase/migrations.
class SupabaseRemoteStore implements RemoteStore {
  SupabaseRemoteStore(this.client);

  final SupabaseClient client;

  String get _userId {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    return user.id;
  }

  @override
  Future<void> upsertCategories(List<Category> categories) async {
    if (categories.isEmpty) return;
    final uid = _userId;
    await client.from('categories').upsert([
      for (final c in categories) categoryToJson(c, uid),
    ], onConflict: 'user_id,id');
  }

  @override
  Future<void> upsertTasks(List<Task> tasks) async {
    if (tasks.isEmpty) return;
    final uid = _userId;
    await client.from('tasks').upsert([for (final t in tasks) taskToJson(t, uid)], onConflict: 'user_id,id');
  }

  @override
  Future<RemotePage<Category>> fetchCategoriesSince(String? cursor) async {
    final rows = await _fetch('categories', cursor);
    return RemotePage([for (final r in rows) categoryFromJson(r)], _lastCursor(rows, cursor));
  }

  @override
  Future<RemotePage<Task>> fetchTasksSince(String? cursor) async {
    final rows = await _fetch('tasks', cursor);
    return RemotePage([for (final r in rows) taskFromJson(r)], _lastCursor(rows, cursor));
  }

  Future<List<Map<String, dynamic>>> _fetch(String table, String? cursor) {
    var query = client.from(table).select().eq('user_id', _userId);
    if (cursor != null) query = query.gt('server_updated_at', cursor);
    return query.order('server_updated_at', ascending: true).limit(RemoteStore.pageSize);
  }

  static String? _lastCursor(List<Map<String, dynamic>> rows, String? previous) =>
      rows.isEmpty ? previous : rows.last['server_updated_at'] as String;

  @override
  Stream<void> changes() {
    late final RealtimeChannel channel;
    final controller = StreamController<void>.broadcast();
    controller.onListen = () {
      channel = client.channel('bamboozled-sync');
      for (final table in ['tasks', 'categories']) {
        channel.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          callback: (_) => controller.add(null),
        );
      }
      channel.subscribe();
    };
    controller.onCancel = () => client.removeChannel(channel);
    return controller.stream;
  }

  // ---- JSON mapping (timestamps are sent as UTC, shown in local time) ----

  static String _ts(DateTime d) => d.toUtc().toIso8601String();
  static DateTime _parse(Object v) => DateTime.parse(v as String).toLocal();
  static DateTime? _parseOpt(Object? v) => v == null ? null : _parse(v);

  static Map<String, dynamic> taskToJson(Task t, String userId) => {
    'user_id': userId,
    'id': t.id,
    'title': t.title,
    'due_at': _ts(t.dueAt),
    'priority': t.priority.weight,
    'category_id': t.categoryId,
    'estimate_minutes': t.estimateMinutes,
    'notes': t.notes,
    'repeat': t.repeat.index,
    'completed_at': t.completedAt == null ? null : _ts(t.completedAt!),
    'created_at': _ts(t.createdAt),
    'updated_at': _ts(t.updatedAt),
    'deleted_at': t.deletedAt == null ? null : _ts(t.deletedAt!),
  };

  static Task taskFromJson(Map<String, dynamic> j) => Task(
    id: j['id'] as String,
    title: j['title'] as String,
    dueAt: _parse(j['due_at']),
    priority: Priority.fromWeight(j['priority'] as int),
    categoryId: j['category_id'] as String,
    estimateMinutes: j['estimate_minutes'] as int?,
    notes: j['notes'] as String?,
    repeat: Repeat.values[(j['repeat'] as int).clamp(0, Repeat.values.length - 1)],
    completedAt: _parseOpt(j['completed_at']),
    createdAt: _parse(j['created_at']),
    updatedAt: _parse(j['updated_at']),
    deletedAt: _parseOpt(j['deleted_at']),
  );

  static Map<String, dynamic> categoryToJson(Category c, String userId) => {
    'user_id': userId,
    'id': c.id,
    'name': c.name,
    'color_value': c.color.toARGB32(),
    'sort_order': c.sortOrder,
    'updated_at': _ts(c.updatedAt),
    'deleted_at': c.deletedAt == null ? null : _ts(c.deletedAt!),
  };

  static Category categoryFromJson(Map<String, dynamic> j) => Category(
    id: j['id'] as String,
    name: j['name'] as String,
    color: Color(j['color_value'] as int),
    sortOrder: j['sort_order'] as int,
    updatedAt: _parse(j['updated_at']),
    deletedAt: _parseOpt(j['deleted_at']),
  );
}
