import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Categories, Tasks, Settings])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openDefault());

  /// Stored in the app's private support folder, not Documents (which may be
  /// missing, or synced by OneDrive/iCloud while the database is open).
  static QueryExecutor _openDefault() => driftDatabase(
    name: 'bamboozled',
    native: const DriftNativeOptions(databaseDirectory: getApplicationSupportDirectory),
  );

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await m.createIndex(Index('tasks_due_at', 'CREATE INDEX tasks_due_at ON tasks (due_at)'));
      await m.createIndex(Index('tasks_dirty', 'CREATE INDEX tasks_dirty ON tasks (dirty)'));
    },
  );

  Future<String?> getSetting(String key) async =>
      (await (select(settings)..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Stream<String?> watchSetting(String key) =>
      (select(settings)..where((s) => s.key.equals(key))).watchSingleOrNull().map((r) => r?.value);

  Future<void> setSetting(String key, String? value) async {
    if (value == null) {
      await (delete(settings)..where((s) => s.key.equals(key))).go();
    } else {
      await into(settings).insertOnConflictUpdate(SettingRow(key: key, value: value));
    }
  }
}
