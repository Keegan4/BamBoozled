import 'package:flutter/painting.dart';

/// Panda palette. Mirrors the `Panda` colour variables in the Figma file.
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

  /// Colours offered when a user creates a category, with friendly names.
  static const categoryChoices = <String, Color>{
    'Sky': sky,
    'Honey': honey,
    'Blush': blush,
    'Lavender': lavender,
    'Mint': mint,
    'Stone': stone,
  };
}
