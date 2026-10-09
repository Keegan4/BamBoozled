/// Reads a Canvas calendar feed (the "Calendar Feed" link on Canvas's Calendar page), which is a
/// standard iCalendar (.ics) file. Pure Dart, no network: see CanvasService for fetching.
library;

/// One assignment (or other dated item) from the feed.
class CanvasItem {
  const CanvasItem({required this.uid, required this.title, required this.dueAt, this.course, this.link});

  /// Canvas's own id for the item, e.g. `event-assignment-12345`. Stays the same when it is edited.
  final String uid;
  final String title;
  final DateTime dueAt;

  /// The course name Canvas puts in square brackets at the end of the title, if any.
  final String? course;

  /// The assignment's page in Canvas.
  final String? link;

  @override
  String toString() => 'CanvasItem($uid, $title, $dueAt, $course)';
}

class CanvasFeedException implements Exception {
  const CanvasFeedException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Turns what the user pasted into the feed's address, or null if it can't be one.
/// Accepts `webcal://` links too, which some calendar apps hand out.
Uri? canvasFeedUri(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;
  if (text.toLowerCase().startsWith('webcal://')) text = 'https://${text.substring(9)}';
  final uri = Uri.tryParse(text);
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http') || uri.host.isEmpty) return null;
  return uri;
}

/// Parses the feed. Personal and course calendar events (office hours, lectures) are left out:
/// they aren't things to do. Throws [CanvasFeedException] if [ics] isn't a calendar at all.
List<CanvasItem> parseCanvasFeed(String ics) {
  if (!ics.contains('BEGIN:VCALENDAR')) {
    throw const CanvasFeedException('That link didn’t give a calendar. Check you copied the Calendar Feed link.');
  }
  // Long lines are "folded": continued on the next line, which starts with a space or a tab.
  final unfolded = ics.replaceAll('\r\n', '\n').replaceAll(RegExp(r'\n[ \t]'), '');
  final items = <CanvasItem>[];
  Map<String, _Property>? event;
  for (final line in unfolded.split('\n')) {
    if (line == 'BEGIN:VEVENT') {
      event = {};
    } else if (line == 'END:VEVENT') {
      final item = event == null ? null : _toItem(event);
      if (item != null) items.add(item);
      event = null;
    } else if (event != null) {
      final p = _Property.parse(line);
      if (p != null) event.putIfAbsent(p.name, () => p);
    }
  }
  return items;
}

CanvasItem? _toItem(Map<String, _Property> e) {
  final uid = e['UID']?.value.trim();
  final summary = e['SUMMARY'] == null ? null : _unescape(e['SUMMARY']!.value).trim();
  final start = e['DTSTART'] ?? e['DUE'] ?? e['DTEND'];
  if (uid == null || uid.isEmpty || summary == null || summary.isEmpty || start == null) return null;
  if (uid.startsWith('event-calendar-event-')) return null;
  final due = _parseDate(start);
  if (due == null) return null;

  // "Essay 2 [EN1101E Academic Writing]" → title "Essay 2", course "EN1101E Academic Writing".
  var title = summary;
  String? course;
  final bracket = RegExp(r'^(.*\S)\s*\[([^\[\]]+)\]$').firstMatch(summary);
  if (bracket != null) {
    title = bracket.group(1)!.trim();
    course = bracket.group(2)!.trim();
  }
  final url = e['URL']?.value.trim();
  final link = url != null && RegExp(r'^https?://', caseSensitive: false).hasMatch(url) && url.length <= 2000
      ? url
      : null;
  return CanvasItem(
    uid: uid,
    title: title.length > 200 ? title.substring(0, 200) : title,
    dueAt: due,
    course: course,
    link: link,
  );
}

/// `20261015T155900Z` (UTC), `20261015T235900` (local time, with or without a TZID), or
/// `20261015` / VALUE=DATE (a whole day, so due by the end of it).
DateTime? _parseDate(_Property p) {
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$').firstMatch(p.value.trim());
  if (m == null) return null;
  int part(int i) => int.parse(m.group(i) ?? '0');
  final (y, mo, d) = (part(1), part(2), part(3));
  if (m.group(4) == null) return DateTime(y, mo, d, 23, 59);
  if (m.group(7) != null) return DateTime.utc(y, mo, d, part(4), part(5), part(6)).toLocal();
  return DateTime(y, mo, d, part(4), part(5), part(6));
}

String _unescape(String s) => s.replaceAllMapped(
  RegExp(r'\\([\\;,nN])'),
  (m) => switch (m.group(1)!) {
    'n' || 'N' => '\n',
    final c => c,
  },
);

class _Property {
  const _Property(this.name, this.value);
  final String name;
  final String value;

  /// `NAME;PARAM=x;PARAM="a:b":value` → (NAME, value). The first colon outside quotes ends the name.
  static _Property? parse(String line) {
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') quoted = !quoted;
      if (c == ':' && !quoted) {
        final name = line.substring(0, i).split(';').first.toUpperCase();
        return _Property(name, line.substring(i + 1));
      }
    }
    return null;
  }
}
