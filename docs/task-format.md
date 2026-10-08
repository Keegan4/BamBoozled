# Recommended task format

Tasks are added through a form: a bottom sheet on phone and a dialog on desktop. Users fill it in with chips and pickers, so they never need to learn a typing syntax.

| Field | Required | How it's entered | Default |
|---|---|---|---|
| **Title** | yes | Short text that starts with a verb, e.g. "Mark 3A essays" | — |
| **Due date** | yes | Quick chips: *Today · Tomorrow · This Fri · Next week*, or a calendar picker | Today |
| Due time | no | Time picker | End of day (23:59) |
| **Priority** | yes | Four large buttons: *Low · Medium · High · Urgent* (1–4 bamboo leaves) | Medium |
| **Category** | yes | Colour chips, e.g. *Teaching, Admin, Meetings, Personal*. Users can add their own. | General |
| Estimated time | no | Chips: *15m · 30m · 1h · 2h+* | — |
| Notes | no | Free text | — |
| Repeat | no | *None · Daily · Weekly · Monthly* | None |

## Tips shown under the Title box
- Start with an action word: *Mark, Email, Prepare, Submit, Call*.
- Keep it under about 8 words, and put the details in **Notes**.
- One task is one thing you can tick off. Split big jobs into smaller tasks.

## Data model (`Task`)
```dart
class Task {
  String id;            // uuid
  String userId;
  String title;
  DateTime dueAt;
  Priority priority;    // low=1, medium=2, high=3, urgent=4
  String categoryId;    // → Category(name, colorHex)
  Duration? estimate;
  String? notes;
  Repeat repeat;        // none, daily, weekly, monthly
  DateTime? completedAt;
  DateTime createdAt, updatedAt;
  DateTime? deletedAt;  // soft delete, so deletions sync
}
```
