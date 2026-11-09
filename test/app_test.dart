import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneconnect/app.dart';
import 'package:oneconnect/app_state.dart';
import 'package:oneconnect/models/app_settings.dart';
import 'package:oneconnect/screens/sign_in_screen.dart';

import 'helpers/fake_store.dart';

// The first screen has a fade-in animation, so these tests use pump()
// instead of pumpAndSettle().
void main() {
  late AppState appState;

  setUp(() {
    appState = AppState(FakeStore());
  });

  MediaQueryData mediaOfFirstScreen(WidgetTester tester) =>
      MediaQuery.of(tester.element(find.byType(SignInScreen)));

  testWidgets('the theme follows the Settings choice', (tester) async {
    appState.settings = const AppSettings(themeChoice: ThemeChoice.dark);
    await tester.pumpWidget(OneConnectApp(appState: appState));

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );

    await appState.changeSettings(
      const AppSettings(themeChoice: ThemeChoice.light),
    );
    await tester.pump();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
  });

  testWidgets('the text size setting scales the text on every screen', (
    tester,
  ) async {
    appState.settings = const AppSettings(textSize: TextSizeChoice.large);
    await tester.pumpWidget(OneConnectApp(appState: appState));

    expect(mediaOfFirstScreen(tester).textScaler.scale(10), closeTo(12, 0.001));
  });

  testWidgets('reduce animations is passed on to every screen', (tester) async {
    await tester.pumpWidget(OneConnectApp(appState: appState));
    expect(mediaOfFirstScreen(tester).disableAnimations, false);

    await appState.changeSettings(const AppSettings(reduceAnimations: true));
    await tester.pump();

    expect(mediaOfFirstScreen(tester).disableAnimations, true);
  });
}
