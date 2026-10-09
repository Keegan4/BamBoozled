import 'dart:io';

import 'package:bamboozled/data/canvas/canvas_feed.dart';
import 'package:bamboozled/data/canvas/canvas_service.dart';
import 'package:bamboozled/data/local/app_database.dart';
import 'package:bamboozled/data/repositories/task_repository.dart';
import 'package:bamboozled/domain/models/priority.dart';
import 'package:bamboozled/domain/models/task.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../canvas_samples.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late TaskRepository repo;
  late DateTime now;
  var ids = 0;

  setUp(() async {
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    now = DateTime(2026, 10, 9, 9);
    repo = TaskRepository(db, clock: () => now, newId: () => 'id${ids++}');
    await repo.ensureDefaultCategories();
  });
  tearDown(() async {
    await repo.dispose();
    await db.close();
  });

  Future<List<Task>> all() => repo.watchTasks().first;
  Future<Task> one(String uid) async => (await repo.getTask(TaskRepository.canvasTaskId(uid)))!;
  void later() => now = now.add(const Duration(minutes: 5));
  CanvasItem item(String uid, {String title = 'Essay', DateTime? due, String? course = 'EN1101E', String? link}) =>
      CanvasItem(uid: uid, title: title, dueAt: due ?? DateTime(2026, 10, 15, 23, 59), course: course, link: link);

  group('importing assignments', () {
    test('each assignment becomes a task with its title, due date and link', () async {
      final result = await repo.applyCanvasItems(parseCanvasFeed(sampleFeed));
      expect(result.added, 2);
      expect(result.total, 2);
      final tasks = await all();
      expect(tasks.map((t) => t.title), ['Essay 2', 'Problem set 3, part A']);
      expect(tasks.first.link, 'https://canvas.nus.edu.sg/courses/55/assignments/101');
      expect(tasks.every((t) => t.isFromCanvas), isTrue);
      expect(tasks.first.priority, Priority.medium);
      expect(tasks.first.isDone, isFalse);
    });

    test('task ids come from Canvas ids, so every device makes the same task', () async {
      await repo.applyCanvasItems([item('event-assignment-101')]);
      expect((await all()).single.id, 'canvas-event-assignment-101');
      expect(TaskRepository.canvasTaskId('odd id/with:chars'), 'canvas-odd_id_with_chars');
    });

    test('each course gets its own colour-coded category, made once', () async {
      await repo.applyCanvasItems(parseCanvasFeed(sampleFeed));
      final categories = await repo.watchCategories().first;
      final english = categories.singleWhere((c) => c.name == 'EN1101E Academic Writing');
      final cs = categories.singleWhere((c) => c.name == 'CS1010 Programming');
      expect(english.id, 'canvas-course-en1101e-academic-writing');
      expect(english.color, isNot(cs.color));
      final used = categories.where((c) => !c.id.startsWith('canvas-')).map((c) => c.color).toSet();
      expect(used.contains(english.color), isFalse, reason: 'a colour not already taken');
      await repo.applyCanvasItems(parseCanvasFeed(sampleFeed));
      expect(await repo.watchCategories().first, hasLength(categories.length));
      final tasks = await all();
      expect(tasks.first.categoryId, english.id);
      expect(tasks.last.categoryId, cs.id);
    });

    test('assignments without a course go into a "Canvas" category', () async {
      await repo.applyCanvasItems([item('a', course: null)]);
      final category = (await repo.watchCategories().first).singleWhere((c) => c.id == 'canvas-course');
      expect(category.name, 'Canvas');
      expect((await all()).single.categoryId, 'canvas-course');
    });

    test('long course names are cut to fit a category name', () async {
      await repo.applyCanvasItems([item('a', course: 'A' * 80)]);
      final category = (await repo.watchCategories().first).singleWhere((c) => c.id.startsWith('canvas-course-'));
      expect(category.name.length, 40);
    });

    test('importing the same feed again changes nothing', () async {
      await repo.applyCanvasItems(parseCanvasFeed(sampleFeed));
      final before = await all();
      later();
      final result = await repo.applyCanvasItems(parseCanvasFeed(sampleFeed));
      expect([result.added, result.updated, result.removed], [0, 0, 0]);
      expect(await all(), before);
    });

    test('the same assignment listed twice in a feed is one task', () async {
      await repo.applyCanvasItems([item('a'), item('a', title: 'Copy')]);
      expect((await all()).single.title, 'Essay');
    });
  });

  group('keeping in step with Canvas', () {
    test('a changed title, due date or link in Canvas is copied over', () async {
      await repo.applyCanvasItems([item('a')]);
      later();
      final result = await repo.applyCanvasItems([
        item('a', title: 'Essay (extended)', due: DateTime(2026, 10, 18, 23, 59), link: 'https://c.example/a'),
      ]);
      expect(result.updated, 1);
      final t = await one('a');
      expect([t.title, t.dueAt, t.link], ['Essay (extended)', DateTime(2026, 10, 18, 23, 59), 'https://c.example/a']);
      expect(t.updatedAt, now);
    });

    test('your own priority, category, notes, estimate and tick are kept', () async {
      await repo.applyCanvasItems([item('a')]);
      later();
      await repo.updateTask(
        (await one('a')).copyWith(
          priority: Priority.urgent,
          categoryId: 'admin',
          notes: () => 'Ask Ms Lim',
          estimateMinutes: () => 60,
        ),
      );
      await repo.setDone(TaskRepository.canvasTaskId('a'), true);
      later();
      await repo.applyCanvasItems([item('a', title: 'Essay v2')]);
      final t = await one('a');
      expect(t.title, 'Essay v2');
      expect([t.priority, t.categoryId, t.notes, t.estimateMinutes], [Priority.urgent, 'admin', 'Ask Ms Lim', 60]);
      expect(t.isDone, isTrue, reason: 'a refresh never un-ticks');
    });

    test('an assignment removed from Canvas is removed here', () async {
      await repo.applyCanvasItems([item('a'), item('b', due: DateTime(2026, 10, 20))]);
      later();
      final result = await repo.applyCanvasItems([item('a')]);
      expect(result.removed, 1);
      expect((await all()).map((t) => t.id), ['canvas-a']);
    });

    test('but one you already finished is kept, as a record', () async {
      await repo.applyCanvasItems([item('a'), item('b', due: DateTime(2026, 10, 20))]);
      await repo.setDone(TaskRepository.canvasTaskId('b'), true);
      later();
      await repo.applyCanvasItems([item('a')]);
      expect((await all()).map((t) => t.id), containsAll(['canvas-a', 'canvas-b']));
    });

    test('old assignments that drop out of the feed’s date range are kept', () async {
      await repo.applyCanvasItems([item('old', due: DateTime(2026, 8, 1)), item('a')]);
      later();
      await repo.applyCanvasItems([item('a')]);
      expect((await all()).map((t) => t.id), containsAll(['canvas-old', 'canvas-a']));
    });

    test('an empty feed removes nothing (it may just be a hiccup)', () async {
      await repo.applyCanvasItems([item('a')]);
      final result = await repo.applyCanvasItems([]);
      expect(result.removed, 0);
      expect(await all(), hasLength(1));
    });

    test('your own tasks are never touched', () async {
      final mine = await repo.addTask(TaskDraft(title: 'Mine', dueAt: DateTime(2026, 10, 16), categoryId: 'general'));
      await repo.applyCanvasItems([item('a')]);
      await repo.applyCanvasItems([item('b')]);
      expect((await all()).map((t) => t.id), containsAll([mine.id, 'canvas-b']));
    });

    test('an assignment you deleted stays deleted when the feed is read again', () async {
      await repo.applyCanvasItems([item('a')]);
      later();
      await repo.deleteTask(TaskRepository.canvasTaskId('a'));
      later();
      final result = await repo.applyCanvasItems([item('a', title: 'Changed')]);
      expect(result.added, 0);
      expect(await all(), isEmpty);
    });

    test('but connecting again brings it back', () async {
      await repo.applyCanvasItems([item('a')]);
      await repo.deleteTask(TaskRepository.canvasTaskId('a'));
      later();
      final result = await repo.applyCanvasItems([item('a')], restoreDeleted: true);
      expect(result.added, 1);
      expect((await all()).single.id, 'canvas-a');
    });

    test('imported and changed tasks are marked for upload to the other devices', () async {
      await repo.applyCanvasItems([item('a')]);
      expect((await repo.dirtyTasks()).map((t) => t.id), ['canvas-a']);
    });
  });

  group('disconnecting', () {
    test('removes every Canvas task and course category, and nothing else', () async {
      final mine = await repo.addTask(TaskDraft(title: 'Mine', dueAt: DateTime(2026, 10, 16), categoryId: 'general'));
      await repo.applyCanvasItems(parseCanvasFeed(sampleFeed));
      later();
      expect(await repo.removeCanvasTasks(), 2);
      expect((await all()).single.id, mine.id);
      expect((await repo.watchCategories().first).where((c) => c.id.startsWith('canvas-')), isEmpty);
    });

    test('connecting again restores the tasks and their course categories', () async {
      await repo.applyCanvasItems(parseCanvasFeed(sampleFeed));
      later();
      await repo.removeCanvasTasks();
      later();
      await repo.applyCanvasItems(parseCanvasFeed(sampleFeed), restoreDeleted: true);
      final tasks = await all();
      expect(tasks, hasLength(2));
      final categories = {for (final c in await repo.watchCategories().first) c.id};
      expect(categories, containsAll(tasks.map((t) => t.categoryId)));
    });
  });

  group('CanvasService', () {
    late List<Uri> fetched;
    late String body;
    Object? failure;
    late CanvasService canvas;

    setUp(() {
      fetched = [];
      body = sampleFeed;
      failure = null;
      canvas = CanvasService(
        db: db,
        repo: repo,
        clock: () => now,
        fetch: (uri) async {
          fetched.add(uri);
          if (failure != null) throw failure!;
          return body;
        },
      );
    });

    test('connect imports the feed and remembers the link and when it was read', () async {
      final result = await canvas.connect(' webcal://canvas.nus.edu.sg/feeds/calendars/user_x.ics ');
      expect(fetched.single.toString(), 'https://canvas.nus.edu.sg/feeds/calendars/user_x.ics');
      expect(result.total, 2);
      final status = await canvas.status();
      expect(status.connected, isTrue);
      expect(status.host, 'canvas.nus.edu.sg');
      expect(status.itemCount, 2);
      expect(status.lastSyncedAt, now);
      expect(status.lastError, isNull);
    });

    test('a link that is not a link is refused without going online', () async {
      await expectLater(canvas.connect('my canvas'), throwsA(isA<CanvasFeedException>()));
      expect(fetched, isEmpty);
      expect((await canvas.status()).connected, isFalse);
    });

    test('a page that is not a calendar is refused and nothing is saved', () async {
      body = '<html>Log in</html>';
      await expectLater(canvas.connect('https://canvas.example/x.ics'), throwsA(isA<CanvasFeedException>()));
      expect((await canvas.status()).connected, isFalse);
      expect(await all(), isEmpty);
    });

    test('a download problem is passed on with its message', () async {
      failure = const CanvasFeedException('We couldn’t reach Canvas.');
      await expectLater(
        canvas.connect('https://canvas.example/x.ics'),
        throwsA(isA<CanvasFeedException>().having((e) => e.message, 'message', 'We couldn’t reach Canvas.')),
      );
    });

    test('refresh does nothing when not connected', () async {
      expect(await canvas.refresh(), isNull);
      expect(fetched, isEmpty);
    });

    test('refresh reads the saved link again and records the time', () async {
      await canvas.connect('https://canvas.example/x.ics');
      later();
      body = feed([vevent(uid: 'event-assignment-101', summary: 'Essay 2 [EN1101E Academic Writing]')]);
      final result = await canvas.refresh();
      expect(result!.removed, 1);
      expect(fetched, hasLength(2));
      expect((await canvas.status()).lastSyncedAt, now);
      expect((await canvas.status()).itemCount, 1);
    });

    test('a failed refresh keeps the tasks and shows the problem, until the next one works', () async {
      await canvas.connect('https://canvas.example/x.ics');
      later();
      failure = const CanvasFeedException('We couldn’t reach Canvas.');
      expect(await canvas.refresh(), isNull);
      var status = await canvas.status();
      expect(status.lastError, 'We couldn’t reach Canvas.');
      expect(status.connected, isTrue);
      expect(await all(), hasLength(2));

      failure = Exception('odd');
      await canvas.refresh();
      expect((await canvas.status()).lastError, contains('will try again'));

      failure = null;
      later();
      await canvas.refresh();
      status = await canvas.status();
      expect(status.lastError, isNull);
      expect(status.lastSyncedAt, now);
    });

    test('a refresh within five minutes of the last one is skipped, unless forced', () async {
      await canvas.connect('https://canvas.example/x.ics');
      now = now.add(const Duration(minutes: 4));
      expect(await canvas.refresh(), isNull);
      expect(fetched, hasLength(1));
      expect(await canvas.refresh(force: true), isNotNull);
      expect(fetched, hasLength(2));
    });

    test('two refreshes at once read the feed only once', () async {
      await canvas.connect('https://canvas.example/x.ics');
      await Future.wait([canvas.refresh(force: true), canvas.refresh(force: true)]);
      expect(fetched, hasLength(2), reason: 'one for connect, one shared refresh');
    });

    test('disconnect forgets the link and removes the Canvas tasks', () async {
      await canvas.connect('https://canvas.example/x.ics');
      expect(await canvas.disconnect(), 2);
      expect((await canvas.status()).connected, isFalse);
      expect(await all(), isEmpty);
    });

    test('a refresh that finishes after a disconnect does not reconnect', () async {
      await canvas.connect('https://canvas.example/x.ics');
      final running = canvas.refresh(force: true);
      await canvas.disconnect();
      await running;
      expect((await canvas.status()).connected, isFalse);
    });
  });

  group('CanvasStatus', () {
    test('survives being saved and read back', () {
      final s = CanvasStatus(
        feedUrl: 'https://canvas.example/x.ics',
        lastSyncedAt: DateTime(2026, 10, 9, 9, 30),
        lastError: 'oops',
        itemCount: 3,
      );
      final back = CanvasStatus.fromSetting(s.toSetting());
      expect([back.feedUrl, back.lastSyncedAt, back.lastError, back.itemCount], [s.feedUrl, s.lastSyncedAt, 'oops', 3]);
    });

    test('nothing saved, or something unreadable, means not connected', () {
      expect(CanvasStatus.fromSetting(null).connected, isFalse);
      expect(CanvasStatus.fromSetting('not json').connected, isFalse);
    });
  });

  group('downloading the feed', () {
    late HttpServer server;
    var status = 200;
    var reply = sampleFeed;

    setUpAll(() => HttpOverrides.global = null); // let these tests talk to a local server
    setUp(() async {
      status = 200;
      reply = sampleFeed;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        req.response
          ..statusCode = status
          ..write(reply);
        req.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    Uri at(String path) => Uri.parse('http://${server.address.host}:${server.port}$path');

    test('returns the calendar text, including non-English characters', () async {
      reply = feed([vevent(uid: 'a', summary: 'Résumé ✏️ [中文 101]')]);
      final text = await fetchFeedOverHttp(at('/feeds/calendars/user_x.ics'));
      expect(parseCanvasFeed(text).single.course, '中文 101');
    });

    for (final code in [401, 403, 404]) {
      test('a $code says Canvas didn’t recognise the link', () async {
        status = code;
        await expectLater(
          fetchFeedOverHttp(at('/x.ics')),
          throwsA(isA<CanvasFeedException>().having((e) => e.message, 'message', contains('didn’t recognise'))),
        );
      });
    }

    test('a server error says to try later', () async {
      status = 500;
      await expectLater(
        fetchFeedOverHttp(at('/x.ics')),
        throwsA(isA<CanvasFeedException>().having((e) => e.message, 'message', contains('error 500'))),
      );
    });

    test('no connection says to check the internet', () async {
      final closed = at('/x.ics');
      await server.close(force: true);
      await expectLater(
        fetchFeedOverHttp(closed),
        throwsA(isA<CanvasFeedException>().having((e) => e.message, 'message', contains('internet connection'))),
      );
    });
  });
}
