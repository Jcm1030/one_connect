import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneconnect/app.dart';
import 'package:oneconnect/app_state.dart';
import 'package:oneconnect/models/app_settings.dart';
import 'package:oneconnect/models/profile.dart';
import 'package:oneconnect/screens/profile_screen.dart';
import 'package:oneconnect/screens/rooms_screen.dart';
import 'package:oneconnect/screens/sign_in_screen.dart';

import 'helpers/fake_account_service.dart';
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

  testWidgets('a signed-in user skips the sign-in screen', (tester) async {
    final accountService = FakeAccountService();
    await accountService.signUp('ana@example.com', 'password123');
    final signedInAppState = AppState(
      FakeStore(),
      accountService: accountService,
    );

    await tester.pumpWidget(OneConnectApp(appState: signedInAppState));

    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.byType(SignInScreen), findsNothing);
  });

  testWidgets('startup continues the profile linked to the signed-in account', (
    tester,
  ) async {
    final accountService = FakeAccountService();
    final user = await accountService.signUp('ana@example.com', 'password123');
    accountService.markEmailVerified('ana@example.com');
    await accountService.reloadUser();
    final other = Profile(name: 'Ben', username: 'ben', accountId: 'other');
    final ana = Profile(name: 'Ana', username: 'ana', accountId: user.id);
    final signedInAppState = AppState(
      FakeStore(),
      accountService: accountService,
    )..profiles.addAll([other, ana]);

    await tester.pumpWidget(OneConnectApp(appState: signedInAppState));
    await tester.pumpAndSettle();

    expect(signedInAppState.currentUser, same(ana));
    expect(find.byType(RoomsScreen), findsOneWidget);
  });

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
