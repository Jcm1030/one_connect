import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneconnect/accounts/account_service.dart';
import 'package:oneconnect/app_state.dart';
import 'package:oneconnect/models/profile.dart';
import 'package:oneconnect/screens/account_screen.dart';

import 'helpers/fake_account_service.dart';
import 'helpers/memory_key_store.dart';
import 'helpers/fake_store.dart';

void main() {
  late FakeAccountService service;
  late Profile ana;
  late AppState appState;

  setUp(() {
    service = FakeAccountService();
    ana = Profile(name: 'Ana', username: 'ana');
    appState = AppState(FakeStore(), accountService: service);
    appState.profiles.add(ana);
    appState.currentUser = ana;
  });

  // A tall test screen, so every field and button is on screen.
  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget screen() => MaterialApp(home: AccountScreen(appState: appState));

  testWidgets('a signed-out person sees the sign-in form', (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(screen());

    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2)); // email, password
  });

  testWidgets('creating an account sends the verification email and asks the '
      'person to check their email', (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(screen());

    await tester.tap(find.text('Create a new account'));
    await tester.pump();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'ana@example.com');
    await tester.enterText(fields.at(1), 'a long password');
    await tester.enterText(fields.at(2), 'a long password');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Check your email'), findsOneWidget);
    expect(service.verificationEmailsSent, 1);
    expect(service.currentUser, isNotNull);
  });

  testWidgets('passwords that do not match are caught before anything is '
      'sent', (tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(screen());

    await tester.tap(find.text('Create a new account'));
    await tester.pump();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'ana@example.com');
    await tester.enterText(fields.at(1), 'a long password');
    await tester.enterText(fields.at(2), 'a different one');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(service.currentUser, null);
  });

  testWidgets('a wrong password shows the friendly message', (tester) async {
    useTallScreen(tester);
    await service.signUp('ana@example.com', 'a long password');
    await service.signOut();
    await tester.pumpWidget(screen());

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'ana@example.com');
    await tester.enterText(fields.at(1), 'wrong password');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(
      find.text(accountErrorMessage(AccountError.wrongCredentials)),
      findsOneWidget,
    );
  });

  testWidgets('after the email is verified, the account can be linked to the '
      'profile', (tester) async {
    useTallScreen(tester);
    await service.signUp('ana@example.com', 'a long password');
    service.markEmailVerified('ana@example.com');
    await tester.pumpWidget(screen());

    // The screen starts on "check your email", because it has not asked the
    // server again yet.
    expect(find.text('Check your email'), findsOneWidget);
    await tester.tap(find.text("I've verified my email"));
    await tester.pumpAndSettle();

    expect(find.text('Link account to Ana'), findsOneWidget);
    await tester.tap(find.text('Link account to Ana'));
    await tester.pumpAndSettle();

    expect(ana.accountId, service.currentUser!.id);
    expect(
      find.text('Your profile is linked to your online account.'),
      findsOneWidget,
    );
  });

  testWidgets('a linked profile shows a notice, even when signed out', (
    tester,
  ) async {
    useTallScreen(tester);
    ana.accountId = 'uid1';
    await tester.pumpWidget(screen());

    expect(
      find.text('This profile has an online account linked.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, 'Unlink'), findsOneWidget);
  });

  testWidgets('unlinking asks first, then removes the link', (tester) async {
    useTallScreen(tester);
    ana.accountId = 'uid1';
    await tester.pumpWidget(screen());

    await tester.tap(find.widgetWithText(OutlinedButton, 'Unlink'));
    await tester.pumpAndSettle();
    expect(find.text('Unlink this profile?'), findsOneWidget);

    // Cancelling keeps the link.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(ana.accountId, 'uid1');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Unlink'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Unlink'));
    await tester.pumpAndSettle();

    expect(ana.accountId, null);
    expect(
      find.text('This profile has an online account linked.'),
      findsNothing,
    );
  });

  testWidgets('linking the account also creates the encryption keys', (
    tester,
  ) async {
    useTallScreen(tester);
    final keyStore = MemoryKeyStore();
    appState = AppState(
      FakeStore(),
      accountService: service,
      keyStore: keyStore,
    );
    appState.profiles.add(ana);
    appState.currentUser = ana;

    await service.signUp('ana@example.com', 'a long password');
    service.markEmailVerified('ana@example.com');
    await tester.pumpWidget(screen());

    await tester.tap(find.text("I've verified my email"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link account to Ana'));
    await tester.pumpAndSettle();

    expect(keyStore.keys.containsKey(service.currentUser!.id), true);
    expect(
      find.text('Your encryption keys are stored securely on this phone.'),
      findsOneWidget,
    );
  });

  testWidgets('a linked profile without keys can create them', (tester) async {
    useTallScreen(tester);
    final keyStore = MemoryKeyStore();
    appState = AppState(
      FakeStore(),
      accountService: service,
      keyStore: keyStore,
    );
    appState.profiles.add(ana);
    appState.currentUser = ana;

    final user = await service.signUp('ana@example.com', 'a long password');
    service.markEmailVerified('ana@example.com');
    ana.accountId = user.id; // already linked, but this phone has no keys
    await tester.pumpWidget(screen());

    await tester.tap(find.text("I've verified my email"));
    await tester.pumpAndSettle();
    expect(
      find.text('This phone has no encryption keys for your account yet.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Create encryption keys'));
    await tester.pumpAndSettle();

    expect(keyStore.keys.containsKey(user.id), true);
    expect(
      find.text('Your encryption keys are stored securely on this phone.'),
      findsOneWidget,
    );
  });
}
