import 'package:flutter/material.dart';

import 'models/profile.dart';

Color seedColorFor(ProfileColor color) {
  switch (color) {
    case ProfileColor.purple:
      return const Color(0xFF7C5CE6); 
    case ProfileColor.teal:
      return Colors.teal;
    case ProfileColor.pink:
      return Colors.pink;
  }
}

String colorLabel(ProfileColor color) {
  switch (color) {
    case ProfileColor.purple:
      return 'Purple';
    case ProfileColor.teal:
      return 'Teal';
    case ProfileColor.pink:
      return 'Pink';
  }
}

// Builds the whole look of the app from one chosen color.
// Called twice: once for light mode and once for dark mode.
ThemeData buildTheme(ProfileColor color, Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seedColorFor(color),
    brightness: brightness,
  );
  final dark = brightness == Brightness.dark;
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // Light mode: a colored top bar. Dark mode: a plain dark one.
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? scheme.surface : scheme.primary,
      foregroundColor: dark ? scheme.onSurface : scheme.onPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: rounded),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: rounded),
    ),
  );
}