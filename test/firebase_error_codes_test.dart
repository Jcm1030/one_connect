import 'package:flutter_test/flutter_test.dart';
import 'package:oneconnect/accounts/account_service.dart';
import 'package:oneconnect/accounts/firebase_error_codes.dart';

void main() {
  test('Firebase error codes become our own account errors', () {
    expect(accountErrorFromFirebaseCode('invalid-email'),
        AccountError.invalidEmail);
    expect(accountErrorFromFirebaseCode('weak-password'),
        AccountError.weakPassword);
    expect(accountErrorFromFirebaseCode('email-already-in-use'),
        AccountError.emailAlreadyUsed);
    expect(accountErrorFromFirebaseCode('user-disabled'),
        AccountError.accountDisabled);
    expect(accountErrorFromFirebaseCode('too-many-requests'),
        AccountError.tooManyAttempts);
    expect(accountErrorFromFirebaseCode('network-request-failed'),
        AccountError.noNetwork);
  });

  test('wrong password, unknown email and invalid-credential all look the '
      'same, and unknown codes become unknown', () {
    for (final code in [
      'invalid-credential',
      'invalid-login-credentials',
      'wrong-password',
      'user-not-found',
    ]) {
      expect(accountErrorFromFirebaseCode(code), AccountError.wrongCredentials);
    }
    expect(accountErrorFromFirebaseCode('something-new'), AccountError.unknown);
  });
}