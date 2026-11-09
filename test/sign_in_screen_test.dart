import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneconnect/app_state.dart';
import 'package:oneconnect/models/profile.dart';
import 'package:oneconnect/screens/rooms_screen.dart';
import 'package:oneconnect/screens/sign_in_screen.dart';

import 'helpers/fake_account_service.dart';
import 'helpers/fake_store.dart';

void main() {
  testWidgets('Continue as you opens rooms for a verified linked profile', (
    tester,
  ) async {
    final service = FakeAccountService();
    await service.signUp('ana@example.com', 'password123');
    service.markEmailVerified('ana@example.com');
    final user = await service.reloadUser();
    final ana = Profile(name: 'Ana', username: 'ana', accountId: user.id);
    final appState = AppState(FakeStore(), accountService: service)
      ..profiles.add(ana);

    await tester.pumpWidget(
      MaterialApp(home: SignInScreen(appState: appState)),
    );
    await tester.tap(find.text('Continue as you'));
    await tester.pumpAndSettle();

    expect(appState.currentUser, same(ana));
    expect(find.byType(RoomsScreen), findsOneWidget);
  });
}
