/// Build-time configuration. Pass with `--dart-define` (see README):
///
///   flutter run --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///               --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
///
/// Without these the app runs fully offline on one device.
abstract final class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get syncConfigured => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
