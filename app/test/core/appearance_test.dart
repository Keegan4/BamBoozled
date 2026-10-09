import 'package:bamboozled/core/theme/appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime at(int h, [int m = 0]) => DateTime(2026, 10, 8, h, m);

void main() {
  group('Appearance schedule', () {
    const evening = Appearance(mode: AppearanceMode.scheduled); // dark 7 pm → 7 am

    test('dark overnight, light during the day', () {
      expect(evening.scheduledDarkAt(at(18, 59)), isFalse);
      expect(evening.scheduledDarkAt(at(19)), isTrue);
      expect(evening.scheduledDarkAt(at(23, 59)), isTrue);
      expect(evening.scheduledDarkAt(at(0)), isTrue);
      expect(evening.scheduledDarkAt(at(6, 59)), isTrue);
      expect(evening.scheduledDarkAt(at(7)), isFalse);
      expect(evening.scheduledDarkAt(at(12)), isFalse);
    });

    test('a dark stretch inside one day', () {
      const afternoon = Appearance(
        mode: AppearanceMode.scheduled,
        darkFrom: TimeOfDay(hour: 13, minute: 30),
        lightFrom: TimeOfDay(hour: 17, minute: 0),
      );
      expect(afternoon.scheduledDarkAt(at(13, 29)), isFalse);
      expect(afternoon.scheduledDarkAt(at(13, 30)), isTrue);
      expect(afternoon.scheduledDarkAt(at(16, 59)), isTrue);
      expect(afternoon.scheduledDarkAt(at(17)), isFalse);
      expect(afternoon.scheduledDarkAt(at(2)), isFalse);
    });

    test('the same time twice means never dark', () {
      const same = Appearance(
        mode: AppearanceMode.scheduled,
        darkFrom: TimeOfDay(hour: 8, minute: 0),
        lightFrom: TimeOfDay(hour: 8, minute: 0),
      );
      for (final h in [0, 8, 12, 20]) {
        expect(same.scheduledDarkAt(at(h)), isFalse);
      }
    });

    test('theme mode for each choice', () {
      expect(const Appearance().themeModeAt(at(22)), ThemeMode.light);
      expect(const Appearance(mode: AppearanceMode.dark).themeModeAt(at(9)), ThemeMode.dark);
      expect(const Appearance(mode: AppearanceMode.device).themeModeAt(at(9)), ThemeMode.system);
      expect(evening.themeModeAt(at(9)), ThemeMode.light);
      expect(evening.themeModeAt(at(21)), ThemeMode.dark);
    });
  });

  group('Appearance setting', () {
    test('defaults to light, dark from 7 pm to 7 am', () {
      const a = Appearance();
      expect(a.mode, AppearanceMode.light);
      expect(a.darkFrom, const TimeOfDay(hour: 19, minute: 0));
      expect(a.lightFrom, const TimeOfDay(hour: 7, minute: 0));
      expect(Appearance.fromSetting(null), a);
    });

    test('round-trips through the stored string', () {
      const a = Appearance(
        mode: AppearanceMode.scheduled,
        darkFrom: TimeOfDay(hour: 20, minute: 15),
        lightFrom: TimeOfDay(hour: 6, minute: 5),
      );
      expect(a.toSetting(), 'scheduled;20:15;06:05');
      expect(Appearance.fromSetting(a.toSetting()), a);
      expect(Appearance.fromSetting(a.toSetting()).hashCode, a.hashCode);
    });

    test('unreadable parts fall back to the defaults', () {
      expect(Appearance.fromSetting('dark'), const Appearance(mode: AppearanceMode.dark));
      expect(Appearance.fromSetting('sepia;25:00;7'), const Appearance());
      expect(Appearance.fromSetting('device;ab:cd;07:60'), const Appearance(mode: AppearanceMode.device));
    });

    test('copyWith changes only what is given', () {
      const a = Appearance();
      expect(a.copyWith(mode: AppearanceMode.dark), const Appearance(mode: AppearanceMode.dark));
      expect(a.copyWith(darkFrom: const TimeOfDay(hour: 21, minute: 0)).lightFrom, a.lightFrom);
      expect(a.copyWith(), a);
    });

    test('every choice has a friendly label', () {
      expect(AppearanceMode.values.map((m) => m.label), ['Light', 'Dark', 'Match device', 'On a schedule']);
    });
  });
}
