import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

/// Panda palette. Mirrors the `Panda` colour variables in the Figma file.
///
/// The first block is the light-mode palette. Screens read those colours through [PandaPalette]
/// (`context.panda`), so they follow light or dark mode; use them from here directly only for art that
/// looks the same in both modes, such as the panda mascot. Category colours are the same in both modes.
abstract final class PandaColors {
  static const ink = Color(0xFF1E1E1E);
  static const rice = Color(0xFFFAF8F3);
  static const surface = Color(0xFFFFFFFF);
  static const muted = Color(0xFF5F5F5F);
  static const line = Color(0xFFE8E4DA);
  static const bamboo = Color(0xFF7BAE7F);
  static const bambooDark = Color(0xFF3F6B45);
  static const bambooTint = Color(0xFFE6F0E4);
  static const overdue = Color(0xFFE06666);
  static const overdueTint = Color(0xFFFBE4E4);

  // Category colours.
  static const blush = Color(0xFFF4A6A6);
  static const sky = Color(0xFF9CC9E8);
  static const honey = Color(0xFFF2C879);
  static const lavender = Color(0xFFB9A7E0);
  static const mint = Color(0xFF9ED9C3);
  static const stone = Color(0xFFCFC8B8);

  // Extra colours, so a user's own categories don't all have to share a colour with the built-in ones.
  static const peach = Color(0xFFF6BF9A);
  static const lime = Color(0xFFCBE08E);
  static const rose = Color(0xFFEDB2D6);
  static const slate = Color(0xFFAFC0D4);
  static const aqua = Color(0xFF8ED8E4);
  static const sand = Color(0xFFE6D9A8);

  /// Colours offered when a user creates a category, with friendly names.
  static const categoryChoices = <String, Color>{
    'Sky': sky,
    'Honey': honey,
    'Blush': blush,
    'Lavender': lavender,
    'Mint': mint,
    'Stone': stone,
    'Peach': peach,
    'Lime': lime,
    'Rose': rose,
    'Slate': slate,
    'Aqua': aqua,
    'Sand': sand,
  };
}

/// The colours that change between light and dark mode. Read them with `context.panda`.
///
/// The dark values come from the dark mode mockup: warm near-black instead of rice-white, and a lighter
/// bamboo green so buttons and accents still stand out. Category colours don't change.
@immutable
class PandaPalette extends ThemeExtension<PandaPalette> {
  const PandaPalette({
    required this.ink,
    required this.rice,
    required this.surface,
    required this.muted,
    required this.line,
    required this.bamboo,
    required this.bambooDark,
    required this.bambooTint,
    required this.overdue,
    required this.overdueTint,
    required this.onBamboo,
  });

  /// Text and panda accents.
  final Color ink;

  /// Page background.
  final Color rice;

  /// Cards, navigation and sheets.
  final Color surface;

  /// Secondary text.
  final Color muted;

  /// Borders and dividers.
  final Color line;

  /// Primary buttons and "Do next".
  final Color bamboo;

  /// Links and the active item.
  final Color bambooDark;

  /// Fills behind green text.
  final Color bambooTint;
  final Color overdue;
  final Color overdueTint;

  /// Text and icons drawn on [bamboo] (dark in both modes, so it stays readable on the green).
  final Color onBamboo;

  static const light = PandaPalette(
    ink: PandaColors.ink,
    rice: PandaColors.rice,
    surface: PandaColors.surface,
    muted: PandaColors.muted,
    line: PandaColors.line,
    bamboo: PandaColors.bamboo,
    bambooDark: PandaColors.bambooDark,
    bambooTint: PandaColors.bambooTint,
    overdue: PandaColors.overdue,
    overdueTint: PandaColors.overdueTint,
    onBamboo: PandaColors.ink,
  );

  static const dark = PandaPalette(
    ink: Color(0xFFEDEBE4),
    rice: Color(0xFF121412),
    surface: Color(0xFF1B1E1B),
    muted: Color(0xFFA2A69E),
    line: Color(0xFF2D312C),
    bamboo: Color(0xFF8CC490),
    bambooDark: Color(0xFFA9D8AC),
    bambooTint: Color(0xFF223426),
    overdue: Color(0xFFF28B8B),
    overdueTint: Color(0xFF3B2323),
    onBamboo: Color(0xFF121412),
  );

  @override
  PandaPalette copyWith({
    Color? ink,
    Color? rice,
    Color? surface,
    Color? muted,
    Color? line,
    Color? bamboo,
    Color? bambooDark,
    Color? bambooTint,
    Color? overdue,
    Color? overdueTint,
    Color? onBamboo,
  }) => PandaPalette(
    ink: ink ?? this.ink,
    rice: rice ?? this.rice,
    surface: surface ?? this.surface,
    muted: muted ?? this.muted,
    line: line ?? this.line,
    bamboo: bamboo ?? this.bamboo,
    bambooDark: bambooDark ?? this.bambooDark,
    bambooTint: bambooTint ?? this.bambooTint,
    overdue: overdue ?? this.overdue,
    overdueTint: overdueTint ?? this.overdueTint,
    onBamboo: onBamboo ?? this.onBamboo,
  );

  @override
  PandaPalette lerp(PandaPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return PandaPalette(
      ink: mix(ink, other.ink),
      rice: mix(rice, other.rice),
      surface: mix(surface, other.surface),
      muted: mix(muted, other.muted),
      line: mix(line, other.line),
      bamboo: mix(bamboo, other.bamboo),
      bambooDark: mix(bambooDark, other.bambooDark),
      bambooTint: mix(bambooTint, other.bambooTint),
      overdue: mix(overdue, other.overdue),
      overdueTint: mix(overdueTint, other.overdueTint),
      onBamboo: mix(onBamboo, other.onBamboo),
    );
  }

  List<Color> get _all => [
    ink,
    rice,
    surface,
    muted,
    line,
    bamboo,
    bambooDark,
    bambooTint,
    overdue,
    overdueTint,
    onBamboo,
  ];

  @override
  bool operator ==(Object other) => other is PandaPalette && listEquals(other._all, _all);

  @override
  int get hashCode => Object.hashAll(_all);
}

extension PandaPaletteContext on BuildContext {
  /// The light or dark palette, whichever the app is showing. Light when no Panda theme is above.
  PandaPalette get panda => Theme.of(this).extension<PandaPalette>() ?? PandaPalette.light;
}
