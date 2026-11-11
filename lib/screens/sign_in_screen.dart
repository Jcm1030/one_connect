import 'package:flutter/material.dart';

import '../accounts/account_service.dart';
import '../app_state.dart';
import '../models/profile.dart';
import '../ui_feedback.dart';
import '../validation.dart';
import '../widgets/animations.dart';
import '../widgets/screen_body.dart';
import 'profile_screen.dart';

// The brand color of the sign-in design and the soft page color behind it.
const _indigo = Color(0xFF3B3FD8);
const _lightPage = Color(0xFFF3F4F9);

// The first screen: sign in, or create an online account.
// When it works, the profile screen finishes the setup (profile, email
// verification, linking the account). The app never saves the email or
// the password.
class SignInScreen extends StatefulWidget {
  final AppState appState;

  const SignInScreen({super.key, required this.appState});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _creatingAccount = false;
  bool _busy = false;
  String? _message; // an error or a short note shown inside the card

  AccountService? get _service => widget.appState.accountService;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

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
  }

  // Moves on to the profile screen, which asks for a profile if there is
  // none, then verifies the email and links the account.
  void _openProfileScreen({
    bool autoContinue = false,
    Profile? profileToContinue,
  }) {
    Navigator.of(context).pushReplacement(
      smoothRoute<void>(
        ProfileScreen(
          appState: widget.appState,
          autoContinue: autoContinue,
          profileToContinue: profileToContinue,
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final service = _service;
    if (service == null) {
      setState(() => _message = 'Online accounts are not available.');
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }
    String? signedInAccountId;
    await _run(() async {
      final email = _emailController.text;
      final password = _passwordController.text;
      if (_creatingAccount) {
        final user = await service.signUp(email, password);
        signedInAccountId = user.id;
        try {
          await service.sendVerificationEmail();
        } on AccountException {
          // The account exists. "Resend email" on the next step can try again.
        }
      } else {
        final user = await service.signIn(email, password);
        signedInAccountId = user.id;
      }
    });
    if (signedInAccountId == null || !mounted) {
      return;
    }
    _passwordController.clear();
    _confirmController.clear();
    final matchingProfile = widget.appState.profiles
        .where((profile) => profile.accountId == signedInAccountId)
        .firstOrNull;
    _openProfileScreen(profileToContinue: matchingProfile);
  }

  Future<void> _forgotPassword() async {
    final service = _service;
    if (service == null) {
      setState(() => _message = 'Online accounts are not available.');
      return;
    }
    if (validateEmail(_emailController.text) != null) {
      setState(() => _message = 'Type your email address above first.');
      return;
    }
    await _run(() async {
      await service.sendPasswordReset(_emailController.text);
      _message =
          'If an account exists for that email, '
          'a reset link has been sent.';
    });
  }

  // Quick way back in: when this phone is already signed in with a verified
  // account that is linked to the saved profile, go straight to the rooms.
  void _continueAsYou() {
    final appState = widget.appState;
    final profiles = appState.profiles;
    if (profiles.any(appState.hasVerifiedAccount)) {
      _openProfileScreen(autoContinue: profiles.length == 1);
      return;
    }
    context.showAppMessage(
      'Sign in first. "Continue as you" works once this phone is already '
      'signed in.',
    );
  }

  void _toggleMode() {
    setState(() {
      _creatingAccount = !_creatingAccount;
      _message = null;
      _confirmController.clear();
    });
  }

  // ---------- Look ----------

  Widget _buildHeader(ThemeData theme) {
    return Column(
      children: [
        Text(
          'One connect',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Fast, private',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  // A white rounded box with a thin border, used for both cards.
  Widget _buildCard({required Widget child}) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: dark ? theme.colorScheme.surfaceContainer : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: child,
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    String? helper,
  }) {
    return InputDecoration(
      hintText: hint,
      helperText: helper,
      prefixIcon: Icon(icon),
      errorMaxLines: 3,
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildSignInCard() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return _buildCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _creatingAccount ? 'Create account' : 'Sign In',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              _fieldLabel('Email'),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                decoration: _inputDecoration(
                  hint: 'name@domain.com',
                  icon: Icons.mail_outline,
                ),
                validator: (value) => validateEmail(value ?? ''),
              ),
              const SizedBox(height: 16),
              _fieldLabel('Password'),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: _creatingAccount
                    ? TextInputAction.next
                    : TextInputAction.done,
                onFieldSubmitted: _creatingAccount || _busy
                    ? null
                    : (_) => _submit(),
                decoration: _inputDecoration(
                  hint: 'Password',
                  icon: Icons.lock_outline,
                  helper: _creatingAccount
                      ? 'At least $minPasswordLength characters'
                      : null,
                ),
                validator: (value) {
                  if (_creatingAccount) {
                    return validatePassword(value ?? '');
                  }
                  return (value ?? '').isEmpty ? 'Enter your password.' : null;
                },
              ),
              if (_creatingAccount) ...[
                const SizedBox(height: 16),
                _fieldLabel('Repeat the password'),
                TextFormField(
                  controller: _confirmController,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: _busy ? null : (_) => _submit(),
                  decoration: _inputDecoration(
                    hint: 'Repeat the password',
                    icon: Icons.lock_outline,
                  ),
                  validator: (value) => validatePasswordConfirmation(
                    _passwordController.text,
                    value ?? '',
                  ),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _message!,
                    style: TextStyle(color: colors.onSecondaryContainer),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: _indigo,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _busy
                      ? 'Please wait...'
                      : (_creatingAccount ? 'Create account' : 'Sign In'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (!_creatingAccount)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy ? null : _forgotPassword,
                    style: TextButton.styleFrom(
                      foregroundColor: colors.onSurface,
                    ),
                    child: const Text('Forgot password?'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchMode() {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            _creatingAccount
                ? 'Already have an account?'
                : "Don't have an account?",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TextButton(
          onPressed: _busy ? null : _toggleMode,
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurface,
          ),
          child: Text(
            _creatingAccount ? 'Sign in' : 'Create your account',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: dark ? theme.colorScheme.surface : _lightPage,
      body: ScreenBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
          children: [
            _buildHeader(theme),
            const SizedBox(height: 24),
            FadeSlideIn(index: 0, child: _buildSignInCard()),
            const SizedBox(height: 24),
            _buildSwitchMode(),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _busy ? null : _continueAsYou,
              icon: const Icon(Icons.person_outline),
              label: const Text('Continue as you'),
            ),
          ],
        ),
      ),
    );
  }
}
