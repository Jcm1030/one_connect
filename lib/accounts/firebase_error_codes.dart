import 'account_service.dart';

// Turns the error "code" text that Firebase sends into our own AccountError.
// This is plain Dart (it does not use Firebase), so it can be tested anywhere.
AccountError accountErrorFromFirebaseCode(String code) {
  switch (code) {
    case 'invalid-email':
      return AccountError.invalidEmail;
    case 'weak-password':
      return AccountError.weakPassword;
    case 'email-already-in-use':
      return AccountError.emailAlreadyUsed;
    // New Firebase projects report "invalid-credential" for both a wrong
    // password and an unknown email, so nobody can find out who has an
    // account. Older projects used the other names. All mean the same here.
    case 'invalid-credential':
    case 'invalid-login-credentials':
    case 'wrong-password':
    case 'user-not-found':
      return AccountError.wrongCredentials;
    case 'user-disabled':
      return AccountError.accountDisabled;
    case 'too-many-requests':
      return AccountError.tooManyAttempts;
    case 'network-request-failed':
      return AccountError.noNetwork;
    default:
      return AccountError.unknown;
  }
}