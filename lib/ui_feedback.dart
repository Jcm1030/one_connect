import 'package:flutter/material.dart';

import 'app_state.dart';

extension AppFeedback on BuildContext {
  void showAppMessage(String message) {
    final messenger = ScaffoldMessenger.of(this);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> saveAndWarn(
    AppState appState, {
    String failureMessage = 'Could not save your changes.',
  }) async {
    final saved = await appState.save();
    if (mounted && !saved) {
      showAppMessage(failureMessage);
    }
    return saved;
  }
}
