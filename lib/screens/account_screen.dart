import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../accounts/account_service.dart';
import '../app_state.dart';
import '../models/profile.dart';
import '../online/username_service.dart';
import '../ui_feedback.dart';
import '../validation.dart';
import '../widgets/animations.dart';
import '../widgets/screen_body.dart';
import 'sign_in_screen.dart';

// The optional online account. It shows one of three views:
//   1. Not signed in: sign in, or create a new account.
//   2. Signed in, email not verified yet: "check your email".
//   3. Signed in and verified: link the account to the current profile,
//      and choose a unique username.
// The app never saves the email or the password.
class AccountScreen extends StatefulWidget {
  final AppState appState;
  final Profile? profile;

  const AccountScreen({super.key, required this.appState, this.profile});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _usernameController = TextEditingController();

  bool _creatingAccount = false;
  bool _busy = false;
  String? _message; // an error or a short note shown at the top
  AccountUser? _user;
  bool _keysReady = false; // are this profile's keys stored on this phone?

  // Username state.
  late final _usernameService = UsernameService();
  Timer? _usernameDebounce;
  bool _usernameLoaded = false;
  String? _currentUsername; // the name saved online, or null if none yet
  String? _usernameError; // shown in red under the field
  String? _usernameHint; // shown in grey under the field

  AccountService get _service => widget.appState.accountService!;
  Profile get _profile => widget.profile ?? widget.appState.currentUser!;

  @override
  void initState() {
    super.initState();
    _user = _service.currentUser;
    if (_profile.accountId != null) {
      _loadKeyStatus();
    }
    if (_user?.emailVerified == true) {
      _loadUsername();
    }
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _loadKeyStatus() async {
    final keys = await widget.appState.loadKeys(_profile);
    if (!mounted) {
      return;
    }
    setState(() => _keysReady = keys != null);
  }

  // Makes the encryption keys if this phone has none yet.
  Future<void> _createKeys() async {
    final keys = await widget.appState.ensureKeys(_profile);
    if (!mounted) {
      return;
    }
    setState(() {
      _keysReady = keys != null;
      if (keys == null) {
        _message = 'Could not create the encryption keys on this phone.';
      }
    });
  }

  // ---------- Username ----------

  // Loads the saved username. If there is none yet, fills the field with a
  // free suggestion that the person can edit.
  Future<void> _loadUsername() async {
    _usernameLoaded = true;
    try {
      var current = await _usernameService.currentUsername();
      var claimedNow = false;
      String? problem;

      // No online username yet: claim the one chosen at sign-up, so people
      // are never asked for a username twice. Only if that name cannot be
      // used online (taken by someone else, or reserved) is the person asked.
      if (current == null) {
        final preferred = _profile.username.trim().toLowerCase();
        if (UsernameService.validate(preferred) != null) {
          problem = '@$preferred cannot be used online. Pick another one.';
        } else {
          try {
            current = await _usernameService.setUsername(preferred);
            claimedNow = true;
          } on StateError {
            problem = '@$preferred is already taken online. Pick another one.';
          }
        }
      }

      final text =
          current ?? await _usernameService.suggestUsername(_profile.name);
      if (!mounted) {
        return;
      }
      setState(() {
        _currentUsername = current;
        _usernameController.text = text;
        _usernameError = null;
        _usernameHint = current == null
            ? (problem ?? 'Suggested for you. You can change it.')
            : null;
      });
      if (claimedNow) {
        context.showAppMessage('People can now find you as @$current.');
      }
    } on FirebaseException {
      _usernameLoaded = false; // lets it try again next time
      if (mounted) {
        setState(() => _usernameError = 'Could not load your username.');
      }
    }
  }

  // Clears everything about the username (used when signing out).
  void _resetUsername() {
    _usernameDebounce?.cancel();
    _usernameLoaded = false;
    _currentUsername = null;
    _usernameError = null;
    _usernameHint = null;
    _usernameController.clear();
  }

  // Checks the name while typing: first the format, then, after a short
  // pause, whether somebody already has it.
  void _onUsernameChanged(String value) {
    _usernameDebounce?.cancel();
    final name = value.trim().toLowerCase();

    if (name.isEmpty || name == _currentUsername) {
      setState(() {
        _usernameError = null;
        _usernameHint = null;
      });
      return;
    }
    final problem = UsernameService.validate(name);
    if (problem != null) {
      setState(() {
        _usernameError = problem;
        _usernameHint = null;
      });
      return;
    }

    setState(() {
      _usernameError = null;
      _usernameHint = 'Checking…';
    });
    _usernameDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final free = await _usernameService.isAvailable(name);
        // Ignore the answer if the person kept typing meanwhile.
        if (!mounted || _usernameController.text.trim().toLowerCase() != name) {
          return;
        }
        setState(() {
          _usernameError = free ? null : 'That username is already taken.';
          _usernameHint = free ? '@$name is available.' : null;
        });
      } on FirebaseException {
        if (mounted) {
          setState(() => _usernameHint = null);
        }
      }
    });
  }

  Future<void> _saveUsername() async {
    final input = _usernameController.text;
    final problem = UsernameService.validate(input);
    if (problem != null) {
      setState(() => _usernameError = problem);
      return;
    }
    setState(() {
      _busy = true;
      _usernameError = null;
    });
    try {
      final name = await _usernameService.setUsername(input);
      if (!mounted) {
        return;
      }
      setState(() {
        _currentUsername = name;
        _usernameController.text = name;
        _usernameHint = null;
      });
      context.showAppMessage('Username set to @$name.');
    } on FormatException catch (error) {
      if (mounted) {
        setState(() => _usernameError = error.message);
      }
    } on StateError catch (error) {
      if (mounted) {
        setState(() => _usernameError = error.message);
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        context.showAppMessage(
          'Could not save: ${error.message ?? error.code}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  // ---------- Account actions ----------

  // Runs one account action. While it runs the buttons are disabled, and if
  // it fails with an AccountException the friendly message is shown.
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on AccountException catch (e) {
      _message = accountErrorMessage(e.error);
    }
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    // Once the email is verified, load (or suggest) the username.
    if (_user?.emailVerified == true && !_usernameLoaded) {
      unawaited(_loadUsername());
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    await _run(() async {
      final email = _emailController.text;
      final password = _passwordController.text;
      if (_creatingAccount) {
        _user = await _service.signUp(email, password);
        try {
          await _service.sendVerificationEmail();
        } on AccountException {
          _message =
              'Your account was created, but the verification email '
              'could not be sent. Tap Resend email.';
        }
      } else {
        _user = await _service.signIn(email, password);
      }
      _passwordController.clear();
      _confirmController.clear();
    });
  }

  Future<void> _forgotPassword() async {
    if (validateEmail(_emailController.text) != null) {
      setState(() => _message = 'Type your email address above first.');
      return;
    }
    await _run(() async {
      await _service.sendPasswordReset(_emailController.text);
      _message =
          'If an account exists for that email, '
          'a reset link has been sent.';
    });
  }

  Future<void> _checkVerified() async {
    await _run(() async {
      final user = await _service.reloadUser();
      _user = user;
      if (!user.emailVerified) {
        _message =
            'Not verified yet. Open the link in the email, '
            'then try again.';
      }
    });
  }

  Future<void> _resend() async {
    await _run(() async {
      await _service.sendVerificationEmail();
      _message = 'Verification email sent.';
    });
  }

  Future<void> _signOut() async {
    await _run(() async {
      await _service.signOut();
      _user = null;
      _resetUsername();
      await widget.appState.stopOnlineSync();
    });
    if (!mounted || _service.currentUser != null) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil<void>(
      smoothRoute<void>(SignInScreen(appState: widget.appState)),
      (_) => false,
    );
  }

  Future<void> _link() async {
    final result = widget.appState.linkAccount(_user!, profile: _profile);
    switch (result) {
      case LinkResult.linked:
        final saved = await widget.appState.save();
        if (!mounted) {
          return;
        }
        setState(() => _message = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              saved ? 'Account linked.' : 'Linked, but it could not be saved.',
            ),
          ),
        );
        // A linked account gets its encryption keys right away.
        await _createKeys();
      case LinkResult.notVerified:
        setState(() => _message = 'Verify your email first.');
      case LinkResult.accountUsedByAnotherProfile:
        setState(
          () => _message =
              'This online account is already linked to another profile.',
        );
      case LinkResult.profileHasAnotherAccount:
        setState(
          () => _message =
              'This profile is already linked to a different online account. '
              'Unlink it first.',
        );
    }
  }

  // Removes the link on this phone, after asking. The online account stays.
  Future<void> _unlink() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unlink this profile?'),
        content: const Text(
          'This only removes the link on this phone. Your online account '
          'stays. You must link a verified email account again before '
          'you can return to your rooms.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    widget.appState.unlinkAccount(profile: _profile);
    final saved = await widget.appState.save();
    if (!mounted) {
      return;
    }
    setState(
      () => _message = saved ? null : 'Unlinked, but it could not be saved.',
    );
  }

  // Shown whenever this profile is linked to an online account, whether or not
  // you are signed in, so a link can always be removed.
  Widget _buildLinkedNotice(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Expanded(
              child: Text('This profile has an online account linked.'),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: _busy ? null : _unlink,
              child: const Text('Unlink'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- The three views ----------

  Widget _buildSignedOut(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _creatingAccount ? 'Create your online account' : 'Sign in',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Your email and password are handled by Firebase. '
          'This app never saves them.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  errorMaxLines: 3,
                ),
                validator: (value) => validateEmail(value ?? ''),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: _creatingAccount
                      ? 'At least $minPasswordLength characters'
                      : null,
                  errorMaxLines: 3,
                ),
                validator: (value) {
                  if (_creatingAccount) {
                    return validatePassword(value ?? '');
                  }
                  return (value ?? '').isEmpty ? 'Enter your password.' : null;
                },
              ),
              if (_creatingAccount) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmController,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Repeat the password',
                    errorMaxLines: 3,
                  ),
                  validator: (value) => validatePasswordConfirmation(
                    _passwordController.text,
                    value ?? '',
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_creatingAccount ? 'Create account' : 'Sign in'),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _creatingAccount = !_creatingAccount;
                  _message = null;
                }),
          child: Text(
            _creatingAccount
                ? 'I already have an account'
                : 'Create a new account',
          ),
        ),
        if (!_creatingAccount)
          TextButton(
            onPressed: _busy ? null : _forgotPassword,
            child: const Text('Forgot password?'),
          ),
      ],
    );
  }

  Widget _buildVerify(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Check your email', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'We sent you a link to confirm your email address. '
          'Open it, then come back here and tap the button below.',
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _checkVerified,
          child: const Text("I've verified my email"),
        ),
        TextButton(
          onPressed: _busy ? null : _resend,
          child: const Text('Resend email'),
        ),
        TextButton(
          onPressed: _busy ? null : _signOut,
          child: const Text('Sign out'),
        ),
      ],
    );
  }

  // Shows whether this phone holds the encryption keys of the account.
  Widget _buildKeysSection(BuildContext context) {
    final theme = Theme.of(context);
    if (_keysReady) {
      return Row(
        children: [
          Icon(Icons.lock_outline, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Your encryption keys are stored securely on this phone.',
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('This phone has no encryption keys for your account yet.'),
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: _busy ? null : _createKeys,
          child: const Text('Create encryption keys'),
        ),
        const SizedBox(height: 8),
        Text(
          'If you lose this phone or reinstall the app, the keys are gone and '
          'old messages cannot be read. You would start a new room.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  // Choose or change the unique username other people can search for.
  Widget _buildUsernameSection(BuildContext context) {
    final theme = Theme.of(context);
    final typed = _usernameController.text.trim().toLowerCase();
    final canSave =
        !_busy &&
        typed.isNotEmpty &&
        typed != _currentUsername &&
        _usernameError == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Username', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          _currentUsername == null
              ? 'Pick a unique username so people can find you.'
              : 'People can find you as @$_currentUsername.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _usernameController,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: 20,
          onChanged: _onUsernameChanged,
          decoration: InputDecoration(
            labelText: 'Username',
            prefixText: '@',
            counterText: '',
            errorMaxLines: 2,
            errorText: _usernameError,
            helperText:
                _usernameHint ?? '3-20 letters, numbers or underscores.',
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: canSave ? _saveUsername : null,
          child: Text(
            _currentUsername == null ? 'Save username' : 'Change username',
          ),
        ),
      ],
    );
  }

  Widget _buildLink(BuildContext context, AccountUser user) {
    final profile = _profile;
    final linked = profile.accountId == user.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your email is verified',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          linked
              ? 'Your profile is linked to your online account.'
              : 'Link this online account to $profile, '
                    'so you can chat online later.',
        ),
        const SizedBox(height: 16),
        if (!linked)
          FilledButton(
            onPressed: _busy ? null : _link,
            child: Text('Link account to ${profile.name}'),
          ),
        if (linked && widget.appState.keyStore != null) ...[
          const SizedBox(height: 8),
          _buildKeysSection(context),
        ],
        const SizedBox(height: 24),
        _buildUsernameSection(context),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : _signOut,
          child: const Text('Sign out'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final profile = widget.profile ?? widget.appState.currentUser;
    final Widget view;
    if (user == null) {
      view = _buildSignedOut(context);
    } else if (!user.emailVerified) {
      view = _buildVerify(context);
    } else {
      view = _buildLink(context, user);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Online account')),
      body: ScreenBody(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (profile?.accountId != null) ...[
              _buildLinkedNotice(context),
              const SizedBox(height: 12),
            ],
            if (_message != null) ...[
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_message!),
                ),
              ),
              const SizedBox(height: 12),
            ],
            view,
          ],
        ),
      ),
    );
  }
}
