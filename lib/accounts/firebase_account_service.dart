import 'package:firebase_auth/firebase_auth.dart';

import 'account_service.dart';
import 'firebase_error_codes.dart';

// The real account system: Firebase Authentication.
// It does exactly what AccountService promises, and nothing is saved by the app.
class FirebaseAccountService implements AccountService {
  final FirebaseAuth _auth;

  FirebaseAccountService({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  AccountUser _toUser(User user) =>
      AccountUser(id: user.uid, emailVerified: user.emailVerified);

  @override
  AccountUser? get currentUser {
    final user = _auth.currentUser;
    return user == null ? null : _toUser(user);
  }

  // Runs an action. If Firebase reports an error, it becomes our AccountException.
  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AccountException {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw AccountException(accountErrorFromFirebaseCode(e.code));
    } catch (_) {
      throw const AccountException(AccountError.unknown);
    }
  }

  User _signedInUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AccountException(AccountError.notSignedIn);
    }
    return user;
  }

  @override
  Future<AccountUser> signUp(String email, String password) => _run(() async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return _toUser(credential.user!);
  });

  @override
  Future<AccountUser> signIn(String email, String password) => _run(() async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return _toUser(credential.user!);
  });

  @override
  Future<void> sendVerificationEmail() => _run(() async {
    await _signedInUser().sendEmailVerification();
  });

  @override
  Future<AccountUser> reloadUser() => _run(() async {
    final user = _signedInUser();
    await user.reload();
    // Also refresh the login token, so server rules see the new
    // "email verified" state straight away.
    await user.getIdToken(true);
    return _toUser(_signedInUser());
  });

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _run(() => _auth.sendPasswordResetEmail(email: email.trim()));
    } on AccountException catch (e) {
      // Do not reveal whether an account with this email exists.
      if (e.error != AccountError.wrongCredentials) {
        rethrow;
      }
    }
  }

  @override
  Future<void> signOut() => _run(() => _auth.signOut());
}
