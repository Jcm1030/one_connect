import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneconnect/models/profile.dart';
import 'package:oneconnect/theme.dart';

void main() {
  test('each color gives a different theme', () {
    final teal = buildTheme(ProfileColor.teal, Brightness.light);
    final purple = buildTheme(ProfileColor.purple, Brightness.light);
    final pink = buildTheme(ProfileColor.pink, Brightness.light);

    expect(teal.colorScheme.primary == purple.colorScheme.primary, false);
    expect(purple.colorScheme.primary == pink.colorScheme.primary, false);
    expect(teal.colorScheme.primary == pink.colorScheme.primary, false);
  });

  test('the theme can be built for light and dark mode', () {
    expect(
      buildTheme(ProfileColor.teal, Brightness.light).brightness,
      Brightness.light,
    );
    expect(
      buildTheme(ProfileColor.teal, Brightness.dark).brightness,
      Brightness.dark,
    );
  });
}
