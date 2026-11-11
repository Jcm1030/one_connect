import 'package:flutter/material.dart';

import 'app_state.dart';
import 'models/app_settings.dart';
import 'models/profile.dart';
import 'theme.dart';
import 'screens/profile_screen.dart';
import 'screens/sign_in_screen.dart';

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
    final accountId = appState.accountService?.currentUser?.id;
    final linkedProfile = accountId == null
        ? null
        : appState.profiles
              .where((profile) => profile.accountId == accountId)
              .firstOrNull;
    final initialScreen = accountId == null
        ? SignInScreen(appState: appState)
        : ProfileScreen(appState: appState, profileToContinue: linkedProfile);

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
          home: initialScreen,
        );
      },
    );
  }
}
