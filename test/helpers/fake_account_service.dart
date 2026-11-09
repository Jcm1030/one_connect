import 'package:oneconnect/accounts/account_service.dart';

class _FakeAccount {
  final String id;
  final String password;
  bool verified = false;

  _FakeAccount(this.id, this.password);
}

// An account system that lives in memory, for tests. It behaves like the
// real one in the ways the app cares about (duplicate emails, wrong
// passwords, verification), but needs no internet.
class FakeAccountService implements AccountService {
  final Map<String, _FakeAccount> _accounts = {};
  AccountUser? _current;
  int _counter = 0;

  int verificationEmailsSent = 0;
  final List<String> passwordResetsRequested = [];

  @override
  AccountUser? get currentUser => _current;

  // Pretends the person tapped the link in the verification email.
  void markEmailVerified(String email) {
    _accounts[email.trim().toLowerCase()]!.verified = true;
  }

  String _keyOf(String email) => email.trim().toLowerCase();

  AccountUser _userFor(_FakeAccount account) =>
      AccountUser(id: account.id, emailVerified: account.verified);

  @override
  Future<AccountUser> signUp(String email, String password) async {
    final key = _keyOf(email);
    if (!key.contains('@') || !key.contains('.')) {
      throw const AccountException(AccountError.invalidEmail);
    }
    if (password.length < 6) {
      throw const AccountException(AccountError.weakPassword);
    }
    if (_accounts.containsKey(key)) {
      throw const AccountException(AccountError.emailAlreadyUsed);
    }
    final account = _FakeAccount('fakeUid${++_counter}', password);
    _accounts[key] = account;
    _current = _userFor(account);
    return _current!;
  }

  @override
  Future<AccountUser> signIn(String email, String password) async {
    final account = _accounts[_keyOf(email)];
    // Same error for "no such email" and "wrong password", like the real thing.
    if (account == null || account.password != password) {
      throw const AccountException(AccountError.wrongCredentials);
    }
    _current = _userFor(account);
    return _current!;
  }

  @override
  Future<void> sendVerificationEmail() async {
    if (_current == null) {
      throw const AccountException(AccountError.notSignedIn);
    }
    verificationEmailsSent++;
  }

  @override
  Future<AccountUser> reloadUser() async {
    final current = _current;
    if (current == null) {
      throw const AccountException(AccountError.notSignedIn);
    }
    final account =
        _accounts.values.firstWhere((account) => account.id == current.id);
    _current = _userFor(account);
    return _current!;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    passwordResetsRequested.add(_keyOf(email));
  }

  @override
  Future<void> signOut() async {
    _current = null;
  }
}