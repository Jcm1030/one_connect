import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../ui_feedback.dart';
import 'app_update.dart';
import 'update_service.dart';

// Looks for a newer version and, if there is one, shows the update dialog.
// "manual" is true when the person tapped "Check for updates": then they also
// get a message when there is nothing new or the check failed. The automatic
// check at startup stays silent in those cases.
Future<void> checkForUpdateAndAsk(
  BuildContext context,
  AppState appState, {
  bool manual = false,
}) async {
  final service = appState.updateService;
  if (service == null) {
    if (manual) {
      context.showAppMessage('Updates are not available.');
    }
    return;
  }

  final AppUpdate? update;
  try {
    update = await service.checkForUpdate();
  } on UpdateException {
    if (manual && context.mounted) {
      context.showAppMessage('Could not check for updates. Try again later.');
    }
    return;
  }
  if (!context.mounted) {
    return;
  }
  if (update == null) {
    if (manual) {
      context.showAppMessage('You have the latest version.');
    }
    return;
  }

  await showDialog<void>(
    context: context,
    // A required update cannot be dismissed.
    barrierDismissible: !update.required,
    builder: (_) => UpdateDialog(service: service, update: update!),
  );
}

// "Update available": what is new, a progress bar while downloading, and the
// buttons. Android's own installer takes over once the download is done.
class UpdateDialog extends StatefulWidget {
  final UpdateService service;
  final AppUpdate update;

  const UpdateDialog({super.key, required this.service, required this.update});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  StreamSubscription<UpdateProgress>? _subscription;
  UpdateProgress? _progress;
  String? _error;

  // True while downloading or installing, so the dialog cannot be closed.
  bool get _busy =>
      _progress != null && _progress!.status != UpdateStatus.failed;

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _start() {
    setState(() {
      _error = null;
      _progress = const UpdateProgress(UpdateStatus.downloading);
    });
    unawaited(_subscription?.cancel());
    _subscription = widget.service.install(widget.update).listen((progress) {
      if (!mounted) {
        return;
      }
      setState(() {
        _progress = progress;
        if (progress.status == UpdateStatus.failed) {
          _error = progress.error;
        }
      });
    });
  }

  Future<void> _cancel() async {
    await widget.service.cancel();
    await _subscription?.cancel();
    if (mounted) {
      setState(() => _progress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final update = widget.update;
    final status = _progress?.status;
    final downloading = status == UpdateStatus.downloading;
    final installing = status == UpdateStatus.installing;
    final percent = _progress?.percent ?? 0;

    return PopScope(
      canPop: !_busy && !update.required,
      child: AlertDialog(
        scrollable: true,
        title: const Text('Update available'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version ${update.version}',
              style: theme.textTheme.titleSmall,
            ),
            if (update.required) ...[
              const SizedBox(height: 8),
              const Text(
                'This version is no longer supported. '
                'Please update to keep using the app.',
              ),
            ],
            if (update.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(update.notes),
            ],
            if (downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: percent / 100),
              const SizedBox(height: 4),
              Text('Downloading... $percent%'),
            ],
            if (installing) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 4),
              const Text('Installing...'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
        actions: [
          if (!update.required && !_busy)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
          if (downloading)
            TextButton(onPressed: _cancel, child: const Text('Cancel')),
          FilledButton(
            onPressed: _busy ? null : _start,
            child: Text(_error == null ? 'Update' : 'Try again'),
          ),
        ],
      ),
    );
  }
}
