// What the app needs from an online account system: sign up, sign in,
// email verification, password reset and sign out.
//
// The screens only know about this interface. In a later step a Firebase
// version plugs in; tests use a fake version, so no internet is needed.
//
// Emails and passwords only travel through these methods. The app never
// saves them anywhere.

enum AccountError {
  invalidEmail,
  weakPassword,
  emailAlreadyUsed,
  wrongCredentials,
  accountDisabled,
  tooManyAttempts,
  noNetwork,
  notSignedIn,
  unknown,
}

// Thrown when an account action fails. "error" says why.
class AccountException implements Exception {
  final AccountError error;

  const AccountException(this.error);

  @override
  String toString() => 'AccountException($error)';
}

// The signed-in person: their online account id, and whether they have
// confirmed their email address.
class AccountUser {
  final String id;
  final bool emailVerified;

  const AccountUser({required this.id, required this.emailVerified});
}

abstract class AccountService {
  // Who is signed in right now, or null.
  AccountUser? get currentUser;

  // Creates an account and signs in. Does not send the verification email.
  Future<AccountUser> signUp(String email, String password);

  Future<AccountUser> signIn(String email, String password);

  // Sends the "please confirm your email" message to the signed-in person.
  Future<void> sendVerificationEmail();

  // Asks the server again, so emailVerified is up to date after the person
  // has tapped the link in their email.
  Future<AccountUser> reloadUser();

  // Sends a password reset email. It finishes normally even if no account
  // has that email, so nobody can use it to find out who has an account.
  Future<void> sendPasswordReset(String email);

  Future<void> signOut();
}

// A friendly message for each kind of failure, ready to show on screen.
String accountErrorMessage(AccountError error) {
  switch (error) {
    case AccountError.invalidEmail:
      return 'That email address does not look right.';
    case AccountError.weakPassword:
      return 'That password is too weak. Use at least 10 characters.';
    case AccountError.emailAlreadyUsed:
      return 'An account with this email already exists. Try signing in.';
    case AccountError.wrongCredentials:
      return 'The email or password is not correct.';
    case AccountError.accountDisabled:
      return 'This account has been disabled.';
    case AccountError.tooManyAttempts:
      return 'Too many attempts. Wait a few minutes and try again.';
    case AccountError.noNetwork:
      return 'No internet connection. Check your connection and try again.';
    case AccountError.notSignedIn:
      return 'You are not signed in.';
    case AccountError.unknown:
      return 'Something went wrong. Please try again.';
  }
}