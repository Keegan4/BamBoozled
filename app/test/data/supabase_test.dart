import 'dart:convert';
import 'dart:io';

import 'package:bamboozled/data/remote/auth_service.dart';
import 'package:bamboozled/data/remote/remote_store.dart';
import 'package:bamboozled/data/remote/supabase_remote_store.dart';
import 'package:bamboozled/domain/models/category.dart';
import 'package:bamboozled/domain/models/priority.dart';
import 'package:bamboozled/domain/models/task.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A signed access token that expires in an hour (the signature isn't checked by the client).
String _jwt() {
  String b64(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
  return '${b64({'alg': 'HS256', 'typ': 'JWT'})}.${b64({'sub': 'user-1', 'exp': exp, 'role': 'authenticated'})}.sig';
}

Map<String, dynamic> _session() => {
  'access_token': _jwt(),
  'token_type': 'bearer',
  'expires_in': 3600,
  'refresh_token': 'refresh-1',
  'user': {
    'id': 'user-1',
    'aud': 'authenticated',
    'email': 'ms.tan@school.edu.sg',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
    'created_at': '2026-10-01T00:00:00Z',
  },
};

/// Where the sign-in code challenge is kept (the app uses SharedPreferences).
class _MemoryStorage extends GotrueAsyncStorage {
  final _items = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> removeItem({required String key}) async => _items.remove(key);

  @override
  Future<void> setItem({required String key, required String value}) async => _items[key] = value;
}

class RecordedRequest {
  RecordedRequest(this.method, this.uri, this.headers, this.body);
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String body;

  String get path => uri.path;
  Map<String, String> get query => uri.queryParameters;
}

/// A tiny fake of the Supabase HTTP API (auth and the two tables), served on localhost.
class FakeSupabaseApi {
  FakeSupabaseApi._(this._server) {
    _server.listen(_handle);
  }

  static Future<FakeSupabaseApi> start() async =>
      FakeSupabaseApi._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final requests = <RecordedRequest>[];
  final tasksResponse = <Map<String, dynamic>>[];
  final categoriesResponse = <Map<String, dynamic>>[];
  bool rejectLogin = false;
  bool serverDown = false;

  String get url => 'http://${_server.address.host}:${_server.port}';

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final body = await utf8.decodeStream(req);
    final headers = <String, String>{};
    req.headers.forEach((name, values) => headers[name] = values.join(','));
    requests.add(RecordedRequest(req.method, req.uri, headers, body));

    var status = 200;
    Object? payload = <String, dynamic>{};
    final path = req.uri.path;
    if (serverDown) {
      (status, payload) = (503, {'message': 'down'});
    } else if (path.endsWith('/auth/v1/token')) {
      (status, payload) = rejectLogin
          ? (400, {'error_code': 'invalid_credentials', 'msg': 'Invalid login credentials'})
          : (200, _session());
    } else if (path.endsWith('/auth/v1/logout')) {
      status = 204;
      payload = null;
    } else if (path.endsWith('/rest/v1/tasks')) {
      payload = req.method == 'GET' ? tasksResponse : <dynamic>[];
    } else if (path.endsWith('/rest/v1/categories')) {
      payload = req.method == 'GET' ? categoriesResponse : <dynamic>[];
    } else {
      (status, payload) = (404, {'message': 'not found: $path'});
    }
    req.response.statusCode = status;
    if (payload != null) {
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(payload));
    }
    await req.response.close();
  }

  Iterable<RecordedRequest> to(String suffix, [String? method]) =>
      requests.where((r) => r.path.endsWith(suffix) && (method == null || r.method == method));
}

Map<String, dynamic> _taskRow({String id = 't1', String stamp = '2026-10-08T01:00:00.123456+00:00'}) => {
  'user_id': 'user-1',
  'id': id,
  'title': 'Mark 3A essays',
  'due_at': '2026-10-09T09:00:00+00:00',
  'priority': 3,
  'category_id': 'teaching',
  'estimate_minutes': null,
  'notes': null,
  'repeat': 0,
  'completed_at': null,
  'created_at': '2026-10-08T01:00:00+00:00',
  'updated_at': '2026-10-08T01:00:00+00:00',
  'deleted_at': null,
  'server_updated_at': stamp,
};

void main() {
  late FakeSupabaseApi api;
  late SupabaseClient client;

  // The Flutter test binding blocks real sockets; these tests talk to a server on localhost.
  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    api = await FakeSupabaseApi.start();
    client = SupabaseClient(
      api.url,
      'sb_publishable_test',
      authOptions: AuthClientOptions(autoRefreshToken: false, pkceAsyncStorage: _MemoryStorage()),
    );
  });

  tearDown(() async {
    await client.dispose();
    await api.close();
  });

  Future<void> signIn() async {
    await client.auth.setSession('refresh-1');
    expect(client.auth.currentUser?.id, 'user-1');
  }

  Task task(String id) => Task(
    id: id,
    title: 'Plan CCA trip',
    dueAt: DateTime.utc(2026, 10, 15, 1),
    priority: Priority.urgent,
    categoryId: 'cca',
    createdAt: DateTime.utc(2026, 10, 8),
    updatedAt: DateTime.utc(2026, 10, 8, 2),
  );

  group('AuthService', () {
    test('signIn sends the trimmed email and the password, and signs the user in', () async {
      final auth = AuthService(client);
      expect(auth.currentUser, isNull);
      await auth.signIn(' ms.tan@school.edu.sg ', 'bamboo-123');
      final req = api.to('/auth/v1/token', 'POST').single;
      expect(req.query['grant_type'], 'password');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['email'], 'ms.tan@school.edu.sg');
      expect(body['password'], 'bamboo-123');
      expect(auth.currentUser?.email, 'ms.tan@school.edu.sg');
    });

    test('signIn never asks the server to create an account or send an email', () async {
      await AuthService(client).signIn('ms.tan@school.edu.sg', 'bamboo-123');
      expect(api.to('/auth/v1/otp'), isEmpty);
      expect(api.to('/auth/v1/signup'), isEmpty);
    });

    test('a wrong email or password throws and leaves the user signed out', () async {
      api.rejectLogin = true;
      final auth = AuthService(client);
      await expectLater(auth.signIn('ms.tan@school.edu.sg', 'wrong'), throwsA(isA<AuthException>()));
      expect(auth.currentUser, isNull);
    });

    test('userChanges emits the current user first, then sign-in and sign-out', () async {
      final auth = AuthService(client);
      final seen = <String?>[];
      final sub = auth.userChanges().listen((u) => seen.add(u?.email));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await auth.signIn('ms.tan@school.edu.sg', 'bamboo-123');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await auth.signOut();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();
      expect(seen.first, isNull);
      expect(seen, contains('ms.tan@school.edu.sg'));
      expect(seen.last, isNull);
    });

    test('network failures surface as errors the UI can catch', () async {
      api.serverDown = true;
      await expectLater(AuthService(client).signIn('ms.tan@school.edu.sg', 'bamboo-123'), throwsA(anything));
    });
  });

  group('SupabaseRemoteStore', () {
    test('refuses to talk to the server when signed out', () async {
      final store = SupabaseRemoteStore(client);
      await expectLater(store.upsertTasks([task('a')]), throwsA(isA<StateError>()));
      await expectLater(store.fetchTasksSince(null), throwsA(isA<StateError>()));
      expect(api.to('/rest/v1/tasks'), isEmpty);
    });

    test('upsertTasks posts every row with the signed-in user id and merges on (user_id, id)', () async {
      await signIn();
      await SupabaseRemoteStore(client).upsertTasks([task('a'), task('b')]);
      final req = api.to('/rest/v1/tasks', 'POST').single;
      expect(req.query['on_conflict'], 'user_id,id');
      final rows = jsonDecode(req.body) as List;
      expect(rows.map((r) => r['id']), ['a', 'b']);
      expect(rows.every((r) => r['user_id'] == 'user-1'), isTrue);
      expect(rows.first['due_at'], '2026-10-15T01:00:00.000Z');
      expect(req.headers['prefer'], contains('resolution=merge-duplicates'));
    });

    test('upsertCategories posts to the categories table', () async {
      await signIn();
      final c = Category(id: 'c', name: 'Exams', color: const Color(0xFFF2C879), updatedAt: DateTime.utc(2026, 10, 8));
      await SupabaseRemoteStore(client).upsertCategories([c]);
      final rows = jsonDecode(api.to('/rest/v1/categories', 'POST').single.body) as List;
      expect(rows.single['name'], 'Exams');
      expect(rows.single['color_value'], 0xFFF2C879);
    });

    test('pushing nothing makes no request', () async {
      await signIn();
      final store = SupabaseRemoteStore(client);
      await store.upsertTasks([]);
      await store.upsertCategories([]);
      expect(api.to('/rest/v1/tasks'), isEmpty);
      expect(api.to('/rest/v1/categories'), isEmpty);
    });

    test('fetchTasksSince reads only my rows, oldest change first, and returns the next cursor', () async {
      await signIn();
      api.tasksResponse.addAll([_taskRow(id: 'a', stamp: '2026-10-08T01:00:00.5+00:00'), _taskRow(id: 'b')]);
      final page = await SupabaseRemoteStore(client).fetchTasksSince('2026-10-07T00:00:00+00:00');
      final q = api.to('/rest/v1/tasks', 'GET').single.query;
      expect(q['user_id'], 'eq.user-1');
      expect(q['server_updated_at'], 'gt.2026-10-07T00:00:00+00:00');
      expect(q['order'], startsWith('server_updated_at.asc'));
      expect(q['limit'], '${RemoteStore.pageSize}');
      expect(page.rows.map((t) => t.id), ['a', 'b']);
      expect(page.cursor, '2026-10-08T01:00:00.123456+00:00', reason: 'cursor is the last row\'s server stamp');
    });

    test('the first fetch has no cursor filter, and an empty page keeps the old cursor', () async {
      await signIn();
      final store = SupabaseRemoteStore(client);
      final empty = await store.fetchTasksSince(null);
      expect(api.to('/rest/v1/tasks', 'GET').single.query.containsKey('server_updated_at'), isFalse);
      expect(empty.rows, isEmpty);
      expect(empty.cursor, isNull);
      expect((await store.fetchCategoriesSince('cursor-1')).cursor, 'cursor-1');
    });

    test('fetchCategoriesSince parses categories', () async {
      await signIn();
      api.categoriesResponse.add({
        'user_id': 'user-1',
        'id': 'exams',
        'name': 'Exams',
        'color_value': 0xFFF2C879,
        'sort_order': 6,
        'updated_at': '2026-10-08T01:00:00+00:00',
        'deleted_at': null,
        'server_updated_at': '2026-10-08T01:00:00+00:00',
      });
      final page = await SupabaseRemoteStore(client).fetchCategoriesSince(null);
      expect(page.rows.single.name, 'Exams');
      expect(page.rows.single.color, const Color(0xFFF2C879));
      expect(page.rows.single.sortOrder, 6);
    });

    test('server errors are thrown so the sync service can retry', () async {
      await signIn();
      api.serverDown = true;
      await expectLater(SupabaseRemoteStore(client).fetchTasksSince(null), throwsA(anything));
      await expectLater(SupabaseRemoteStore(client).upsertTasks([task('a')]), throwsA(anything));
    });
  });

  group('JSON mapping', () {
    test('a task with every field set survives a round trip, including deletion', () {
      final t = Task(
        id: 'x',
        title: 'Everything',
        dueAt: DateTime(2026, 10, 9, 17),
        priority: Priority.low,
        categoryId: 'personal',
        estimateMinutes: 120,
        notes: 'Notes with “quotes”, emoji 🐼 and\nnewlines',
        repeat: Repeat.monthly,
        completedAt: DateTime(2026, 10, 9, 12, 30, 15, 250),
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 9, 12, 30, 15, 250),
        deletedAt: DateTime(2026, 10, 10),
        link: 'https://canvas.nus.edu.sg/courses/55/assignments/101',
      );
      final json = SupabaseRemoteStore.taskToJson(t, 'u');
      expect(SupabaseRemoteStore.taskFromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>), t);
    });

    test('a task without a link sends no link column, so servers without 0002 still accept it', () {
      final json = SupabaseRemoteStore.taskToJson(
        Task(
          id: 'x',
          title: 'x',
          dueAt: DateTime(2026),
          categoryId: 'g',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
        'u',
      );
      expect(json.containsKey('link'), isFalse);
      expect(SupabaseRemoteStore.taskFromJson({...json, 'server_updated_at': 'x'}).link, isNull);
    });

    test('timestamps are sent in UTC and read back in local time', () {
      final json = SupabaseRemoteStore.taskToJson(
        Task(
          id: 'x',
          title: 'x',
          dueAt: DateTime.utc(2026, 10, 9, 9),
          categoryId: 'g',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
        'u',
      );
      expect(json['due_at'], '2026-10-09T09:00:00.000Z');
      expect(SupabaseRemoteStore.taskFromJson({...json, 'server_updated_at': 'x'}).dueAt.isUtc, isFalse);
    });

    test('unknown priority and repeat values from a newer app version do not crash', () {
      final t = SupabaseRemoteStore.taskFromJson({..._taskRow(), 'priority': 9, 'repeat': 9});
      expect(t.priority, Priority.medium);
      expect(t.repeat, Repeat.monthly, reason: 'clamped to the last known value');
    });
  });

  group('SQL schema matches the app', () {
    final sql = File('../supabase/migrations/0001_tasks.sql').readAsStringSync();

    Set<String> columnsOf(String table) {
      final body = RegExp('create table public\\.$table \\((.*?)\\n\\);', dotAll: true).firstMatch(sql)!.group(1)!;
      return {
        for (final line in body.split('\n'))
          if (RegExp(r'^\s{2}([a-z_]+)\s').firstMatch(line) case final m? when m.group(1) != 'primary') m.group(1)!,
      };
    }

    test('every field the app sends for a task is a column in public.tasks', () {
      final sent = SupabaseRemoteStore.taskToJson(task('a'), 'u').keys.toSet();
      expect(columnsOf('tasks'), containsAll(sent));
    });

    test('every column the app reads for a task is sent back by the table', () {
      final read = _taskRow().keys.toSet();
      expect(columnsOf('tasks'), equals(read));
    });

    test('every field the app sends for a category is a column in public.categories', () {
      final c = Category(id: 'c', name: 'n', color: const Color(0xFF000000), updatedAt: DateTime.utc(2026));
      final sent = SupabaseRemoteStore.categoryToJson(c, 'u').keys.toSet();
      expect(columnsOf('categories'), containsAll(sent));
    });

    test('the schema keeps row level security and realtime switched on', () {
      expect(sql, contains('alter table public.tasks enable row level security'));
      expect(sql, contains('alter table public.categories enable row level security'));
      expect(sql, contains('alter publication supabase_realtime add table public.categories, public.tasks'));
    });
  });
}
