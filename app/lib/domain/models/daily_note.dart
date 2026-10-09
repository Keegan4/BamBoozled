/// One card for the Notes tab: a photo on the front and a short message on the back.
/// Cards are listed in assets/daily_notes/notes.yaml (see docs/daily-notes.md).
class DailyNote {
  const DailyNote({required this.id, required this.photo, this.title, required this.text});

  /// Unique and permanent: it is how the app remembers which cards have been seen.
  final String id;

  /// Asset path of the photo, e.g. `assets/daily_notes/bamboo-forest.jpg`.
  final String photo;
  final String? title;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is DailyNote && other.id == id && other.photo == photo && other.title == title && other.text == text;

  @override
  int get hashCode => Object.hash(id, photo, title, text);

  @override
  String toString() => 'DailyNote($id)';
}

/// How far today's card has been opened.
enum CardStage {
  /// Blurred photo, "Tap to reveal".
  hidden,

  /// The photo, clear.
  revealed,

  /// Flipped over to the message.
  back,
}
