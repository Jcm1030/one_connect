import 'package:flutter/material.dart';

import '../app_state.dart';
import '../photos/photo_picker_sheet.dart';
import '../photos/photo_service.dart';
import '../validation.dart';
import '../widgets/profile_avatar.dart';

class EditProfileDialog extends StatefulWidget {
  final AppState appState;

  const EditProfileDialog({super.key, required this.appState});

  @override
  State<EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<EditProfileDialog> {
  late final TextEditingController _controller;
  String? _error;
  String? _photoMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.appState.currentUser!.name,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final error = validateName(_controller.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    widget.appState.renameCurrentUser(_controller.text);
    Navigator.of(context).pop(true);
  }

  Future<void> _changePhoto() async {
    final appState = widget.appState;
    final user = appState.currentUser!;
    try {
      final choice = await askForPhoto(
        context,
        appState,
        hasPhoto: user.photoFileName != null,
      );
      if (choice == null || !mounted) {
        return;
      }
      final saved = choice.remove
          ? await appState.removeProfilePhoto(user)
          : await appState.setProfilePhoto(user, choice.file!);
      _photoMessage = saved ? null : 'Could not save the photo.';
    } on PhotoException {
      _photoMessage = 'Could not open the camera or gallery.';
    }
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildPhotoRow() {
    final appState = widget.appState;
    if (appState.photoService == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          ProfileAvatar(
            appState: appState,
            profile: appState.currentUser,
            radius: 40,
          ),
          TextButton.icon(
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Change photo'),
            onPressed: _changePhoto,
          ),
          if (_photoMessage != null)
            Text(
              _photoMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Edit profile'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPhotoRow(),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: maxNameLength,
            decoration: InputDecoration(
              labelText: 'Your name',
              helperText:
                  'Your username '
                  '(@${widget.appState.currentUser!.username}) cannot be changed.',
              helperMaxLines: 2,
              errorText: _error,
              errorMaxLines: 3,
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
