import 'dart:async';

import 'package:flutter/material.dart';

import '../online/username_service.dart';

// Type a username, see matches, tap one to pick it.
// Closes with the chosen UsernameResult (or null if cancelled).
class UsernameSearchDialog extends StatefulWidget {
  final UsernameService service;

  const UsernameSearchDialog({super.key, required this.service});

  @override
  State<UsernameSearchDialog> createState() => _UsernameSearchDialogState();
}

class _UsernameSearchDialogState extends State<UsernameSearchDialog> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<UsernameResult> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // Waits for a short pause in typing so we don't search on every keystroke.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String value) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await widget.service.search(value);
      if (mounted) {
        setState(() => _results = results);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not search right now.');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Find a username'),
      content: SizedBox(
        width: 360,
        height: 320,
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                prefixText: '@',
                hintText: 'username',
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : _results.isEmpty
                  ? const Center(child: Text('Type at least 2 letters.'))
                  : ListView(
                      children: [
                        for (final result in _results)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.alternate_email),
                            title: Text(result.username),
                            onTap: () => Navigator.of(context).pop(result),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
