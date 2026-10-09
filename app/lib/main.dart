import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config.dart';
import 'data/local/app_database.dart';
import 'data/providers.dart';
import 'data/repositories/task_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The app is in English; dates are formatted the same whatever language the device or browser reports.
  Intl.defaultLocale = 'en_US';

  SupabaseClient? client;
  if (AppConfig.syncConfigured) {
    await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseKey);
    client = Supabase.instance.client;
  }

  final db = AppDatabase();
  final repo = TaskRepository(db);
  await repo.ensureDefaultCategories();

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        taskRepositoryProvider.overrideWithValue(repo),
        supabaseClientProvider.overrideWithValue(client),
      ],
      child: const BamBoozledApp(),
    ),
  );
}
