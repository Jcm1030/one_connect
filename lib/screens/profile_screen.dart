import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../formatting.dart';
import '../models/profile.dart';
import '../photos/photo_picker_sheet.dart';
import '../photos/photo_service.dart';
import '../theme.dart';
import '../widgets/animations.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/screen_body.dart';
import '../ui_feedback.dart';
import '../validation.dart';
import 'account_screen.dart';
import 'rooms_screen.dart';
import 'settings_screen.dart';

// The first screen. You can choose an existing profile (this replaces
// "Switch user" from the Java version) or create a new one.
// When creating a profile, the first question is which color you want.
class ProfileScreen extends StatefulWidget {
  final AppState appState;
  final bool autoContinue;
  final Profile? profileToContinue;

  const ProfileScreen({
    super.key,
    required this.appState,
    this.autoContinue = false,
    this.profileToContinue,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  ProfileColor _color = ProfileColor.purple;
  bool _saving = false;
  File? _pickedPhoto; // the photo chosen for the profile being created

  @override
  void initState() {
    super.initState();
    final profiles = widget.appState.profiles;
    final profileToContinue =
        widget.profileToContinue ??
        (widget.autoContinue && profiles.length == 1 ? profiles.single : null);
    if (profileToContinue != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _continueWithProfile(profileToContinue);
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _openRooms() async {
    await Navigator.of(
      context,
    ).push(smoothRoute<void>(RoomsScreen(appState: widget.appState)));
  }

  Future<void> _continueWithProfile(Profile profile) async {
    setState(() => _saving = true);

    if (widget.appState.accountService == null) {
      setState(() => _saving = false);
      context.showAppMessage(
        'A verified email account is required to use the app.',
      );
      return;
    }

    if (!widget.appState.hasVerifiedAccount(profile)) {
      await Navigator.of(context).push(
        smoothRoute<void>(
          AccountScreen(appState: widget.appState, profile: profile),
        ),
      );
      if (!mounted) {
        return;
      }
      if (!widget.appState.hasVerifiedAccount(profile)) {
        setState(() => _saving = false);
        context.showAppMessage(
          profile.accountId == null
              ? 'Link a verified email account to continue.'
              : 'Sign in with the verified email linked to this profile.',
        );
        return;
      }
    }

    widget.appState.currentUser = profile;
    try {
      await widget.appState.startOnlineSync();
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      context.showAppMessage(
        'Could not connect to online rooms: ${error.message ?? error.code}',
      );
      return;
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      context.showAppMessage(error.message);
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    await _openRooms();
  }

  Future<void> _chooseProfileToKeep(Profile profile) async {
    final otherProfileCount = widget.appState.profiles.length - 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Keep ${profile.name}?'),
        content: Text(
          'This keeps ${profile.name} as the only profile on this phone. '
          'It permanently removes the other $otherProfileCount '
          '${otherProfileCount == 1 ? 'profile' : 'profiles'}, their photos, '
          'and all rooms and messages involving them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Keep ${profile.name} only'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _saving = true);
    final saved = await widget.appState.keepOnlyProfile(profile);
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    if (!saved) {
      context.showAppMessage('Could not save your profile changes.');
      return;
    }
    await _continueWithProfile(profile);
  }

  void _openSettings() {
    Navigator.of(
      context,
    ).push(smoothRoute<void>(SettingsScreen(appState: widget.appState)));
  }

  Future<void> _createProfile() async {
    // Runs the validators of both fields. If any fails, it shows the
    // error text under the field and we stop here.
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _saving = true);
    final saved = await widget.appState.createProfileForOnboarding(
      _nameController.text,
      _usernameController.text,
      _color,
    );
    if (!mounted) {
      return;
    }

    // The photo chosen on this screen becomes the new profile's photo.
    final photo = _pickedPhoto;
    if (photo != null) {
      await widget.appState.setProfilePhoto(
        widget.appState.profiles.last,
        photo,
      );
      if (!mounted) {
        return;
      }
    }

    setState(() {
      _saving = false;
      _color = ProfileColor.purple;
      _pickedPhoto = null;
    });
    _nameController.clear();
    _usernameController.clear();
    _formKey.currentState!.reset();

    if (!saved) {
      context.showAppMessage(
        'Your profile was created, but it could not be saved.',
      );
    }
    await _continueWithProfile(widget.appState.profiles.last);
  }

  Future<void> _choosePhoto() async {
    try {
      final choice = await askForPhoto(
        context,
        widget.appState,
        hasPhoto: _pickedPhoto != null,
      );
      if (choice == null || !mounted) {
        return;
      }
      setState(() => _pickedPhoto = choice.remove ? null : choice.file);
    } on PhotoException {
      if (!mounted) {
        return;
      }
      context.showAppMessage('Could not open the camera or gallery.');
    }
  }

  // A round "add a photo" button. Hidden when photos are not set up.
  Widget _buildPhotoPicker(BuildContext context) {
    if (widget.appState.photoService == null) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    final photo = _pickedPhoto;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Center(
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _choosePhoto,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: colors.primaryContainer,
                      backgroundImage: photo != null ? FileImage(photo) : null,
                      onBackgroundImageError: photo != null ? (_, _) {} : null,
                      child: photo == null
                          ? Icon(
                              Icons.person,
                              size: 44,
                              color: colors.onPrimaryContainer,
                            )
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: CircleAvatar(
                        radius: 15,
                        backgroundColor: colors.primary,
                        child: Icon(
                          Icons.camera_alt,
                          size: 16,
                          color: colors.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  photo == null ? 'Add a photo (optional)' : 'Change photo',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWarnings(BuildContext context) {
    final warnings = widget.appState.loadWarnings;
    final shown = warnings.take(3).join('\n');
    final more = warnings.length > 3
        ? '\n...and ${warnings.length - 3} more.'
        : '';
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text('Some saved data could not be read:\n$shown$more'),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final profiles = widget.appState.profiles;
    final name =
        widget.appState.currentUser?.name ??
        (profiles.length == 1 ? profiles.single.name : 'there');
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            'app_logo.png',
            width: 64,
            height: 64,
            fit: BoxFit.contain,
            semanticLabel: 'One Connect logo',
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greetingForTime(DateTime.now()),
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  'Hi, $name!',
                  style: theme.textTheme.headlineSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text('One Connect', style: theme.textTheme.titleMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorPicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final color in ProfileColor.values)
          ChoiceChip(
            avatar: CircleAvatar(
              backgroundColor: seedColorFor(color),
              radius: 8,
            ),
            label: Text(colorLabel(color)),
            showCheckmark: false,
            selected: _color == color,
            onSelected: (_) => setState(() => _color = color),
          ),
      ],
    );
  }

  Widget _buildProfileCard(Profile profile) {
    return Card(
      child: ListTile(
        leading: ProfileAvatar(
          appState: widget.appState,
          profile: profile,
          radius: 22,
        ),
        title: Text(profile.name),
        subtitle: Text('@${profile.username}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _saving ? null : () => _chooseProfileToKeep(profile),
      ),
    );
  }

  Widget _buildExistingProfile(Profile profile) {
    final hasVerifiedAccount = widget.appState.hasVerifiedAccount(profile);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: ListTile(
            leading: ProfileAvatar(
              appState: widget.appState,
              profile: profile,
              radius: 26,
            ),
            title: Text(profile.name),
            subtitle: Text(
              '@${profile.username} · ${colorLabel(profile.color)}',
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          profile.accountId != null
              ? 'Sign in with the verified email linked to this profile.'
              : 'Link a verified email account to continue.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _saving ? null : () => _continueWithProfile(profile),
          child: Text(
            _saving
                ? 'Please wait...'
                : hasVerifiedAccount
                ? 'Continue'
                : profile.accountId != null
                ? 'Sign in to continue'
                : 'Link email to continue',
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) => _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final appState = widget.appState;
    final titleStyle = Theme.of(context).textTheme.titleMedium;

    return Scaffold(
      body: ScreenBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.settings),
                tooltip: 'Settings',
                onPressed: _openSettings,
              ),
            ),
            _buildHeader(context),
            if (appState.loadWarnings.isNotEmpty) _buildWarnings(context),
            if (appState.profiles.length > 1) ...[
              Text('Choose one profile to keep', style: titleStyle),
              const SizedBox(height: 8),
              const Text(
                'Only one profile can be used on this phone. '
                'Choosing one will remove the others and their room history.',
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < appState.profiles.length; i++)
                FadeSlideIn(
                  index: i,
                  child: _buildProfileCard(appState.profiles[i]),
                ),
            ] else if (appState.profiles.length == 1) ...[
              _buildExistingProfile(appState.profiles.single),
            ] else ...[
              // New installs create their one local profile here.
              AnimatedTheme(
                data: buildTheme(_color, Theme.of(context).brightness),
                duration: animationDuration(context, 300),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Welcome! Create your profile', style: titleStyle),
                    const SizedBox(height: 16),
                    _buildPhotoPicker(context),
                    Text('Choose your color', style: titleStyle),
                    const SizedBox(height: 8),
                    _buildColorPicker(),
                    const SizedBox(height: 20),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Your name',
                              errorMaxLines: 3,
                            ),
                            maxLength: maxNameLength,
                            textInputAction: TextInputAction.next,
                            validator: (value) => validateName(value ?? ''),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _usernameController,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              helperText: '3-15 letters, numbers or _',
                              helperMaxLines: 2,
                              errorMaxLines: 3,
                            ),
                            maxLength: 15,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _createProfile(),
                            validator: (value) => validateUsername(
                              value ?? '',
                              appState.profiles,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _saving ? null : _createProfile,
                              child: Text(
                                _saving ? 'Please wait...' : 'Create profile',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
