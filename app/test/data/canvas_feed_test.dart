import 'package:bamboozled/data/canvas/canvas_feed.dart';
import 'package:flutter_test/flutter_test.dart';

import '../canvas_samples.dart';

void main() {
  group('reading a Canvas feed', () {
    test('turns each assignment into an item with title, course, due time and link', () {
      final items = parseCanvasFeed(sampleFeed);
      expect(items.map((i) => i.uid), ['event-assignment-101', 'event-assignment-202']);
      final essay = items.first;
      expect(essay.title, 'Essay 2');
      expect(essay.course, 'EN1101E Academic Writing');
      expect(essay.dueAt, DateTime.utc(2026, 10, 15, 15, 59).toLocal());
      expect(essay.link, 'https://canvas.nus.edu.sg/courses/55/assignments/101');
    });

    test('UTC due times become the same moment in local time', () {
      final item = parseCanvasFeed(sampleFeed).first;
      expect(item.dueAt.isUtc, isFalse);
      expect(item.dueAt.toUtc(), DateTime.utc(2026, 10, 15, 15, 59));
    });

    test('leaves out calendar events such as office hours', () {
      expect(parseCanvasFeed(sampleFeed).map((i) => i.title), isNot(contains('Office hours')));
    });

    test('undoes iCalendar escaping in titles', () {
      expect(parseCanvasFeed(sampleFeed)[1].title, 'Problem set 3, part A');
      final items = parseCanvasFeed(feed([vevent(uid: 'a', summary: r'Read\; then write \\ reflect\nnow')]));
      expect(items.single.title, 'Read; then write \\ reflect\nnow');
    });

    test('joins long lines that Canvas folds onto the next line', () {
      final folded = feed([
        'BEGIN:VEVENT\r\nDTSTART:20261015T155900Z\r\nSUMMARY:A very long assignment na\r\n me that wraps [CS1\r\n\t010 Prog]\r\nUID:event-assignment-7\r\nEND:VEVENT',
      ]);
      final item = parseCanvasFeed(folded).single;
      expect(item.title, 'A very long assignment name that wraps');
      expect(item.course, 'CS1010 Prog');
    });

    test('also reads files with plain \\n line endings', () {
      expect(parseCanvasFeed(sampleFeed.replaceAll('\r\n', '\n')), hasLength(2));
    });

    test('a whole-day item is due at the end of that day', () {
      final item = parseCanvasFeed(feed([vevent(uid: 'a', summary: 'Quiz', start: 'DTSTART;VALUE=DATE:20261016')]));
      expect(item.single.dueAt, DateTime(2026, 10, 16, 23, 59));
    });

    test('a time with a time zone name is read as local time', () {
      final item = parseCanvasFeed(
        feed([vevent(uid: 'a', summary: 'Quiz', start: 'DTSTART;TZID=Asia/Singapore:20261016T090000')]),
      );
      expect(item.single.dueAt, DateTime(2026, 10, 16, 9));
    });

    test('a title without a course in brackets has no course', () {
      final item = parseCanvasFeed(feed([vevent(uid: 'a', summary: 'Sign the form')])).single;
      expect(item.title, 'Sign the form');
      expect(item.course, isNull);
    });

    test('only the last [bracket] is the course', () {
      final item = parseCanvasFeed(feed([vevent(uid: 'a', summary: 'Lab [part 1] report [BIO 101]')])).single;
      expect(item.title, 'Lab [part 1] report');
      expect(item.course, 'BIO 101');
    });

    test('very long titles are cut to 200 characters', () {
      final item = parseCanvasFeed(feed([vevent(uid: 'a', summary: 'x' * 300)])).single;
      expect(item.title.length, 200);
    });

    test('links that are not web addresses are dropped', () {
      final item = parseCanvasFeed(feed([vevent(uid: 'a', summary: 'Quiz', url: 'javascript:alert(1)')])).single;
      expect(item.link, isNull);
    });

    test('items missing a UID, a title or a readable date are skipped, not fatal', () {
      final items = parseCanvasFeed(
        feed([
          'BEGIN:VEVENT\r\nDTSTART:20261015T155900Z\r\nSUMMARY:No uid\r\nEND:VEVENT',
          'BEGIN:VEVENT\r\nDTSTART:20261015T155900Z\r\nUID:no-title\r\nEND:VEVENT',
          vevent(uid: 'bad-date', summary: 'Bad date', start: 'DTSTART:next tuesday'),
          'BEGIN:VEVENT\r\nSUMMARY:No date\r\nUID:no-date\r\nEND:VEVENT',
          vevent(uid: 'ok', summary: 'Fine'),
        ]),
      );
      expect(items.map((i) => i.uid), ['ok']);
    });

    test('colons inside quoted parameters do not confuse it', () {
      final items = parseCanvasFeed(
        feed([
          'BEGIN:VEVENT\r\nDTSTART:20261015T155900Z\r\nSUMMARY;ALTREP="http://x.example/a:b":Quoted\r\nUID:q\r\nEND:VEVENT',
        ]),
      );
      expect(items.single.title, 'Quoted');
    });

    test('an empty calendar gives no items', () {
      expect(parseCanvasFeed(feed([])), isEmpty);
    });

    test('something that is not a calendar is refused with a helpful message', () {
      expect(
        () => parseCanvasFeed('<html>Please log in</html>'),
        throwsA(isA<CanvasFeedException>().having((e) => e.message, 'message', contains('Calendar Feed link'))),
      );
    });
  });

  group('the pasted link', () {
    test('https and http links are accepted, trimmed', () {
      expect(
        canvasFeedUri('  https://canvas.nus.edu.sg/feeds/calendars/user_abc.ics \n').toString(),
        'https://canvas.nus.edu.sg/feeds/calendars/user_abc.ics',
      );
      expect(canvasFeedUri('http://canvas.example/feed.ics'), isNotNull);
    });

    test('webcal links are turned into https', () {
      expect(canvasFeedUri('webcal://canvas.example/feeds/x.ics').toString(), 'https://canvas.example/feeds/x.ics');
      expect(canvasFeedUri('WEBCAL://canvas.example/x.ics')!.scheme, 'https');
    });

    test('anything else is not a link', () {
      for (final bad in ['', '   ', 'canvas', 'ftp://canvas.example/x.ics', 'https://', 'just some words']) {
        expect(canvasFeedUri(bad), isNull, reason: bad);
      }
    });
  });
}
