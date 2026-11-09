import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../validation.dart';

class JoinRoomDialog extends StatefulWidget {
  final AppState appState;

  const JoinRoomDialog({super.key, required this.appState});

  @override
  State<JoinRoomDialog> createState() => _JoinRoomDialogState();
}

class _JoinRoomDialogState extends State<JoinRoomDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _joining = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_joining) {
      return;
    }
    final formatError = validateRoomCode(_controller.text);
    if (formatError != null) {
      setState(() => _error = formatError);
      return;
    }

    if (widget.appState.onlineChatService != null) {
      setState(() {
        _joining = true;
        _error = null;
      });
      try {
        await widget.appState.requestToJoinOnlineRoom(_controller.text);
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } on FirebaseException catch (error) {
        if (mounted) {
          final message = error.message ?? error.code;
          final normalizedMessage = message.toLowerCase();
          final firestoreApiUnavailable =
              normalizedMessage.contains('firestore api has not been used') ||
              normalizedMessage.contains('firestore api is disabled');
          setState(() {
            _joining = false;
            _error = firestoreApiUnavailable
                ? 'Cloud Firestore API is disabled for this Firebase project. '
                      'Enable it in Google Cloud Console, wait a few minutes, '
                      'then retry.'
                : 'Could not send request: $message. '
                      'Check the room code and try again.';
          });
        }
      } on StateError catch (error) {
        if (mounted) {
          setState(() {
            _joining = false;
            _error = error.message;
          });
        }
      }
      return;
    }

    switch (widget.appState.joinRoom(_controller.text)) {
      case JoinOutcome.joined:
        Navigator.of(context).pop(true);
      case JoinOutcome.roomNotFound:
        setState(() => _error = 'No room found with that code.');
      case JoinOutcome.roomFull:
        setState(
          () => _error = 'This room is full. A room can only have two people.',
        );
      case JoinOutcome.roomClosed:
        setState(
          () =>
              _error = 'This room is closed. It no longer accepts new members.',
        );
      case JoinOutcome.inAnotherRoom:
        setState(
          () => _error =
              'You are already in a room. Leave it first to join another.',
        );
      case JoinOutcome.alreadyMember:
        setState(() => _error = 'You are already in this room.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Join room'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 6,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(
          labelText: 'Room code',
          errorText: _error,
          errorMaxLines: 3,
        ),
        onSubmitted: (_) => _join(),
      ),
      actions: [
        TextButton(
          onPressed: _joining ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _joining ? null : _join,
          child: Text(
            _joining
                ? 'Sending...'
                : widget.appState.onlineChatService == null
                ? 'Join'
                : 'Request to join',
          ),
        ),
      ],
    );
  }
}
