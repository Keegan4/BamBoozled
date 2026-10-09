/// Calendar feeds shaped like the ones Canvas produces, for tests.
library;

String vevent({required String uid, required String summary, String start = 'DTSTART:20261015T155900Z', String? url}) =>
    [
      'BEGIN:VEVENT',
      'DTEND:20261015T155900Z',
      'DTSTAMP:20261008T010203Z',
      start,
      'CLASS:PUBLIC',
      'DESCRIPTION:Write 800 words.',
      'SEQUENCE:0',
      'SUMMARY:$summary',
      if (url != null) 'URL;VALUE=URI:$url',
      'UID:$uid',
      'END:VEVENT',
    ].join('\r\n');

String feed(List<String> events) => [
  'BEGIN:VCALENDAR',
  'VERSION:2.0',
  'PRODID:-//Instructure//Canvas//EN',
  'CALSCALE:GREGORIAN',
  'X-WR-CALNAME:Tan Calendar (Canvas)',
  ...events,
  'END:VCALENDAR',
  '',
].join('\r\n');

/// Two assignments in two courses, one course event, due 15 and 20 Oct (UTC times).
final sampleFeed = feed([
  vevent(
    uid: 'event-assignment-101',
    summary: 'Essay 2 [EN1101E Academic Writing]',
    url: 'https://canvas.nus.edu.sg/courses/55/assignments/101',
  ),
  vevent(
    uid: 'event-assignment-202',
    summary: r'Problem set 3\, part A [CS1010 Programming]',
    start: 'DTSTART:20261020T155900Z',
    url: 'https://canvas.nus.edu.sg/courses/66/assignments/202',
  ),
  vevent(uid: 'event-calendar-event-9', summary: 'Office hours [CS1010 Programming]'),
]);
