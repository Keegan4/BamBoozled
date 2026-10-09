import 'package:flutter/material.dart';

/// How the app chooses between light and dark mode (Settings → Appearance).
enum AppearanceMode {
  light('Light'),
  dark('Dark'),

  /// Follows the phone or computer's own light/dark setting.
  device('Match device'),

  /// Dark between [Appearance.darkFrom] and [Appearance.lightFrom] each day.
  scheduled('On a schedule');

  const AppearanceMode(this.label);
  final String label;
}

/// The Appearance setting. Stored in the settings table as one string, e.g. `scheduled;19:00;07:00`.
@immutable
class Appearance {
  const Appearance({
    this.mode = AppearanceMode.light,
    this.darkFrom = const TimeOfDay(hour: 19, minute: 0),
    this.lightFrom = const TimeOfDay(hour: 7, minute: 0),
  });

  static const key = 'appearance';

  final AppearanceMode mode;

  /// When a scheduled day turns dark…
  final TimeOfDay darkFrom;

  /// …and when it turns light again (usually the next morning).
  final TimeOfDay lightFrom;

  Appearance copyWith({AppearanceMode? mode, TimeOfDay? darkFrom, TimeOfDay? lightFrom}) =>
      Appearance(mode: mode ?? this.mode, darkFrom: darkFrom ?? this.darkFrom, lightFrom: lightFrom ?? this.lightFrom);

  /// Whether the schedule says dark at [now]. The dark stretch may run past midnight (7 pm → 7 am)
  /// or sit inside one day (1 pm → 5 pm). Equal times mean never dark.
  bool scheduledDarkAt(DateTime now) {
    final t = now.hour * 60 + now.minute;
    final from = _minutes(darkFrom), until = _minutes(lightFrom);
    if (from == until) return false;
    return from < until ? t >= from && t < until : t >= from || t < until;
  }

  /// The [ThemeMode] for MaterialApp at [now].
  ThemeMode themeModeAt(DateTime now) => switch (mode) {
    AppearanceMode.light => ThemeMode.light,
    AppearanceMode.dark => ThemeMode.dark,
    AppearanceMode.device => ThemeMode.system,
    AppearanceMode.scheduled => scheduledDarkAt(now) ? ThemeMode.dark : ThemeMode.light,
  };

  String toSetting() => '${mode.name};${_format(darkFrom)};${_format(lightFrom)}';

  /// Reads a stored setting; anything missing or unreadable falls back to the defaults.
  static Appearance fromSetting(String? value) {
    if (value == null) return const Appearance();
    final parts = value.split(';');
    const defaults = Appearance();
    return Appearance(
      mode: AppearanceMode.values.asNameMap()[parts.first] ?? defaults.mode,
      darkFrom: (parts.length > 1 ? _parse(parts[1]) : null) ?? defaults.darkFrom,
      lightFrom: (parts.length > 2 ? _parse(parts[2]) : null) ?? defaults.lightFrom,
    );
  }

  static int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  static String _format(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static TimeOfDay? _parse(String s) {
    final hm = s.split(':');
    if (hm.length != 2) return null;
    final h = int.tryParse(hm[0]), m = int.tryParse(hm[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  @override
  bool operator ==(Object other) =>
      other is Appearance && other.mode == mode && other.darkFrom == darkFrom && other.lightFrom == lightFrom;

  @override
  int get hashCode => Object.hash(mode, darkFrom, lightFrom);
}
