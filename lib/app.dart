import 'package:flutter/material.dart';

import 'app_state.dart';
import 'models/app_settings.dart';
import 'models/profile.dart';
import 'theme.dart';
import 'screens/sign_in_screen.dart';

// The whole app: it picks the color from the current profile and applies
// the Settings choices (theme, text size, animations).
class OneConnectApp extends StatelessWidget {
  final AppState appState;

  const OneConnectApp({super.key, required this.appState});

  ThemeMode _themeModeFor(ThemeChoice choice) {
    switch (choice) {
      case ThemeChoice.system:
        return ThemeMode.system;
      case ThemeChoice.light:
        return ThemeMode.light;
      case ThemeChoice.dark:
        return ThemeMode.dark;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds the whole app when the current user or a setting changes.
    // Purple is used while nobody is selected.
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final color = appState.currentUser?.color ?? ProfileColor.purple;
        final settings = appState.settings;

        return MaterialApp(
          title: 'oneConnect',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(color, Brightness.light),
          darkTheme: buildTheme(color, Brightness.dark),
          themeMode: _themeModeFor(settings.themeChoice),
          themeAnimationDuration: settings.reduceAnimations
              ? Duration.zero
              : const Duration(milliseconds: 300),
          // Applies the text size and the "reduce animations" choice to
          // every screen at once.
          builder: (context, child) {
            final media = MediaQuery.of(context);
            final systemTextScale = media.textScaler.scale(1.0);
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(
                  systemTextScale * settings.textScale,
                ),
                disableAnimations:
                    media.disableAnimations || settings.reduceAnimations,
              ),
              child: child!,
            );
          },
          home: SignInScreen(appState: appState),
        );
      },
    );
  }
}
