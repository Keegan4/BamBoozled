import 'package:flutter/material.dart';

import 'colors.dart';

/// Text styles matching the Figma type ramp (Nunito).
abstract final class PandaText {
  static const _family = 'Nunito';
  static const display = TextStyle(fontFamily: _family, fontSize: 28, height: 36 / 28, fontWeight: FontWeight.w800);
  static const title = TextStyle(fontFamily: _family, fontSize: 20, height: 28 / 20, fontWeight: FontWeight.w700);
  static const heading = TextStyle(fontFamily: _family, fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w700);
  static const body = TextStyle(fontFamily: _family, fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w400);
  static const bodyStrong = TextStyle(fontFamily: _family, fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w600);
  static const caption = TextStyle(fontFamily: _family, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w400);
  static const captionStrong = TextStyle(
    fontFamily: _family,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
  );
}

/// Spacing and radii used across the app.
abstract final class PandaSizes {
  static const minTouch = 48.0;
  static const cardRadius = 24.0;
  static const tileRadius = 16.0;
  static const pill = 999.0;
}

/// The app theme. [brightness] picks the light or dark [PandaPalette]; layout, type and shapes are the same.
ThemeData buildPandaTheme({Brightness brightness = Brightness.light}) {
  final p = brightness == Brightness.dark ? PandaPalette.dark : PandaPalette.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: PandaColors.bamboo,
    brightness: brightness,
    primary: p.bamboo,
    onPrimary: p.onBamboo,
    secondary: p.bambooDark,
    surface: p.surface,
    onSurface: p.ink,
    error: p.overdue,
  );
  const pillShape = StadiumBorder();
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: [p],
    fontFamily: 'Nunito',
    scaffoldBackgroundColor: p.rice,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    textTheme: const TextTheme(
      headlineMedium: PandaText.display,
      titleLarge: PandaText.title,
      titleMedium: PandaText.heading,
      bodyLarge: PandaText.body,
      bodyMedium: PandaText.body,
      labelLarge: PandaText.bodyStrong,
      bodySmall: PandaText.caption,
    ).apply(bodyColor: p.ink, displayColor: p.ink),
    dividerColor: p.line,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.bamboo,
        foregroundColor: p.onBamboo,
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: pillShape,
        textStyle: PandaText.heading,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        side: BorderSide(color: p.ink, width: 1.5),
        shape: pillShape,
        textStyle: PandaText.heading,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.bambooDark,
        minimumSize: const Size(48, 48),
        textStyle: PandaText.bodyStrong,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.rice,
      hintStyle: PandaText.body.copyWith(color: p.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: p.line, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: p.line, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: p.bambooDark, width: 2),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.ink,
      contentTextStyle: TextStyle(fontFamily: 'Nunito', fontSize: 16, color: p.rice),
    ),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 400)),
  );
}
