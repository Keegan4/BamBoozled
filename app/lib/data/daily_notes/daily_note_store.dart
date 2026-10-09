import 'dart:convert';

import '../../domain/models/daily_note.dart';
import '../local/app_database.dart';

/// What has been opened, kept on this device in the settings table:
/// * [opened]: the card shown on each day it was revealed (date → card id). This is the Collected
///   gallery, and it also pins today's card once it's been revealed;
/// * the stage today's card was left at, so returning to the tab shows it the same way.
class DailyNoteState {
  const DailyNoteState({this.opened = const {}, this.stageDate, this.stage = CardStage.hidden});

  final Map<String, String> opened;
  final String? stageDate;
  final CardStage stage;

  static const key = 'daily_notes';

  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Today's stage; a stage saved on an earlier day doesn't count.
  CardStage stageOn(DateTime day) => stageDate == dateKey(day) ? stage : CardStage.hidden;

  /// Opened cards, newest first, as (date, card id).
  List<(DateTime, String)> get history {
    final list = [
      for (final e in opened.entries)
        if (DateTime.tryParse(e.key) case final date?) (date, e.value),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    return list;
  }

  DailyNoteState copyWith({Map<String, String>? opened, String? stageDate, CardStage? stage}) =>
      DailyNoteState(opened: opened ?? this.opened, stageDate: stageDate ?? this.stageDate, stage: stage ?? this.stage);

  static DailyNoteState fromSetting(String? value) {
    if (value == null) return const DailyNoteState();
    try {
      final j = jsonDecode(value) as Map<String, dynamic>;
      return DailyNoteState(
        opened: {for (final e in (j['opened'] as Map<String, dynamic>? ?? {}).entries) e.key: e.value as String},
        stageDate: j['stageDate'] as String?,
        stage: CardStage.values.asNameMap()[j['stage']] ?? CardStage.hidden,
      );
    } catch (_) {
      return const DailyNoteState();
    }
  }

  String toSetting() => jsonEncode({'opened': opened, 'stageDate': stageDate, 'stage': stage.name});
}

class DailyNoteStore {
  DailyNoteStore(this.db);
  final AppDatabase db;

  Stream<DailyNoteState> watch() => db.watchSetting(DailyNoteState.key).map(DailyNoteState.fromSetting);

  Future<DailyNoteState> read() async => DailyNoteState.fromSetting(await db.getSetting(DailyNoteState.key));

  /// Moves today's card to [stage]. Revealing it adds it to the collection (and fixes it as today's card).
  Future<void> setStage(DateTime day, String noteId, CardStage stage) async {
    final current = await read();
    final date = DailyNoteState.dateKey(day);
    final opened = stage == CardStage.hidden || current.opened.containsKey(date)
        ? current.opened
        : {...current.opened, date: noteId};
    await db.setSetting(
      DailyNoteState.key,
      current.copyWith(opened: opened, stageDate: date, stage: stage).toSetting(),
    );
  }

  /// An id for this install, used to shuffle the cards when not signed in. Made once, then kept.
  Future<String> installId(String Function() create) async {
    const key = 'install_id';
    final existing = await db.getSetting(key);
    if (existing != null) return existing;
    final id = create();
    await db.setSetting(key, id);
    return id;
  }
}
