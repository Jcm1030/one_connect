import 'package:flutter_test/flutter_test.dart';
import 'package:oneconnect/accounts/account_service.dart';

import 'helpers/fake_account_service.dart';

// Matches a call that fails with one specific kind of account error.
Matcher failsWith(AccountError error) => throwsA(
      isA<AccountException>().having((e) => e.error, 'error', error),
    );

void main() {
  late FakeAccountService service;

  setUp(() {
    service = FakeAccountService();
  });

  test('signing up signs the person in, with an id and an unverified email',
      () async {
    final user = await service.signUp('ana@example.com', 'a long password');

    expect(user.id.isNotEmpty, true);
    expect(user.emailVerified, false);
    expect(service.currentUser?.id, user.id);
  });

  test('bad emails and weak passwords are refused', () async {
    await expectLater(service.signUp('not-an-email', 'a long password'),
        failsWith(AccountError.invalidEmail));
    await expectLater(service.signUp('ana@example.com', '123'),
        failsWith(AccountError.weakPassword));
    expect(service.currentUser, null);
  });

  test('the same email cannot sign up twice, even in a different case',
      () async {
    await service.signUp('ana@example.com', 'a long password');
    await expectLater(service.signUp('ANA@Example.com', 'another password'),
        failsWith(AccountError.emailAlreadyUsed));
  });

  test('a wrong password and an unknown email give the same error', () async {
    await service.signUp('ana@example.com', 'a long password');
    await service.signOut();

    await expectLater(service.signIn('ana@example.com', 'wrong password'),
        failsWith(AccountError.wrongCredentials));
    await expectLater(service.signIn('nobody@example.com', 'a long password'),
        failsWith(AccountError.wrongCredentials));

    final user = await service.signIn('ana@example.com', 'a long password');
    expect(user.id.isNotEmpty, true);
  });

  test('reloadUser shows the email as verified after it was confirmed',
      () async {
    await service.signUp('ana@example.com', 'a long password');
    await service.sendVerificationEmail();
    expect(service.verificationEmailsSent, 1);
    expect(service.currentUser!.emailVerified, false);

    service.markEmailVerified('ana@example.com');
    final reloaded = await service.reloadUser();

    expect(reloaded.emailVerified, true);
  });

  test('signing out clears the user, and account actions then need a sign-in',
      () async {
    await service.signUp('ana@example.com', 'a long password');
    await service.signOut();

    expect(service.currentUser, null);
    await expectLater(
        service.sendVerificationEmail(), failsWith(AccountError.notSignedIn));
    await expectLater(service.reloadUser(), failsWith(AccountError.notSignedIn));
  });

  test('every kind of account error has a message to show', () {
    for (final error in AccountError.values) {
      expect(accountErrorMessage(error).isNotEmpty, true);
    }
  });
}