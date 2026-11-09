import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneconnect/app_state.dart';
import 'package:oneconnect/online/online_chat_service.dart';
import 'package:oneconnect/screens/join_room_dialog.dart';

class _FakeOnlineChatService extends Fake implements OnlineChatService {}

class _FakeAppState extends Fake implements AppState {
  @override
  OnlineChatService? get onlineChatService => _FakeOnlineChatService();

  @override
  Future<void> requestToJoinOnlineRoom(String code) async {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'Cloud Firestore API has not been used in this project.',
    );
  }
}

void main() {
  testWidgets('a disabled Firestore API shows setup instructions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: JoinRoomDialog(appState: _FakeAppState())),
    );

    await tester.enterText(find.byType(TextField), 'ABC234');
    await tester.tap(find.text('Request to join'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'Cloud Firestore API is disabled for this Firebase project.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Enable it in Google Cloud Console'),
      findsOneWidget,
    );
  });
}
