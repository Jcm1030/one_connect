import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneconnect/action_sound_effects.dart';
import 'package:oneconnect/widgets/animations.dart';
import 'package:oneconnect/app_state.dart';
import 'package:oneconnect/models/chat_room.dart';
import 'package:oneconnect/models/message.dart';
import 'package:oneconnect/models/profile.dart';
import 'package:oneconnect/online/online_chat_service.dart';
import 'package:oneconnect/screens/rooms_screen.dart';

import 'helpers/fake_account_service.dart';
import 'helpers/fake_store.dart';

class _FakeOnlineChatService extends Fake implements OnlineChatService {
  @override
  String currentUid = 'ana-account';

  final pendingRequests = StreamController<List<OnlineJoinRequest>>.broadcast();
  String? leftRoomCode;

  @override
  Stream<List<OnlineJoinRequest>> watchJoinRequests(String code) =>
      pendingRequests.stream;

  @override
  Future<void> leaveRoom(String code) async {
    leftRoomCode = code;
  }
}

class _RecordingActionSoundEffects implements ActionSoundEffects {
  int successSoundsPlayed = 0;

  @override
  Future<void> playSuccess() async {
    successSoundsPlayed++;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  late Profile ana;
  late Profile ben;
  late AppState appState;

  setUp(() {
    ana = Profile(name: 'Ana', username: 'ana');
    ben = Profile(name: 'Ben', username: 'ben');
    appState = AppState(FakeStore());
    appState.profiles.addAll([ana, ben]);
    appState.currentUser = ana;
  });

  Widget screen() => MaterialApp(home: RoomsScreen(appState: appState));

  testWidgets('a new room shows its code with a Copy button', (tester) async {
    await tester.pumpWidget(screen());

    await tester.tap(find.text('Create room'));
    await tester.pumpAndSettle();

    expect(appState.rooms.length, 1);
    expect(find.text('Room created!'), findsOneWidget);
    expect(find.text(appState.rooms.first.code), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
  });

  testWidgets('successful room creation plays a sound effect', (tester) async {
    final soundEffects = _RecordingActionSoundEffects();
    appState = AppState(FakeStore(), actionSoundEffects: soundEffects)
      ..profiles.addAll([ana, ben])
      ..currentUser = ana;
    addTearDown(appState.dispose);

    await tester.pumpWidget(screen());
    await tester.tap(find.text('Create room'));
    await tester.pumpAndSettle();

    expect(soundEffects.successSoundsPlayed, 1);
  });

  testWidgets('the Copy button puts the room code on the clipboard', (
    tester,
  ) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(screen());
    await tester.tap(find.text('Create room'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy'));
    await tester.pump();

    expect(copied, appState.rooms.first.code);
  });

  testWidgets('an open room has a copy icon next to its code, a closed room '
      'does not', (tester) async {
    final openRoom = ChatRoom.withCode('OPEN22');
    openRoom.addMember(ana);
    appState.rooms.add(openRoom);

    await tester.pumpWidget(screen());
    expect(find.byIcon(Icons.copy), findsOneWidget);

    final closedRoom = ChatRoom.withCode('SHUT22');
    closedRoom.addMember(ana);
    closedRoom.addMember(ben);
    closedRoom.removeMember(ben);
    appState.rooms.add(closedRoom);

    await tester.pumpWidget(screen());
    await tester.pump();
    expect(find.byIcon(Icons.copy), findsOneWidget); // still just the open one
  });

  testWidgets('a closed room says that the roommate left', (tester) async {
    final room = ChatRoom.withCode('ABC234');
    room.addMember(ana);
    room.addMember(ben);
    room.removeMember(ben);
    appState.rooms.add(room);

    await tester.pumpWidget(screen());

    expect(find.text('Your roommate left'), findsOneWidget);
  });

  testWidgets('canceling leave keeps a local room intact', (tester) async {
    final room = ChatRoom.withCode('ABC234')
      ..addMember(ana)
      ..addMember(ben);
    appState.rooms.add(room);

    await tester.pumpWidget(screen());
    await tester.tap(find.byTooltip('Leave room'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(appState.myRooms, contains(room));
    expect(room.closed, isFalse);
    expect(find.text('Leave room ABC234?'), findsNothing);
  });

  testWidgets('confirming leave removes the current user from a local room', (
    tester,
  ) async {
    final room = ChatRoom.withCode('ABC234')
      ..addMember(ana)
      ..addMember(ben);
    appState.rooms.add(room);

    await tester.pumpWidget(screen());
    await tester.tap(find.byTooltip('Leave room'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();

    expect(appState.myRooms, isEmpty);
    expect(appState.rooms, contains(room));
    expect(room.closed, isTrue);
    expect(find.text('You left room ABC234.'), findsOneWidget);
  });

  testWidgets('confirming leave calls the online room service', (tester) async {
    final service = _FakeOnlineChatService();
    ana.accountId = service.currentUid;
    appState = AppState(FakeStore(), onlineChatService: service)
      ..profiles.addAll([ana, ben])
      ..currentUser = ana;
    addTearDown(appState.dispose);
    final room = ChatRoom.withCode('ABC234')
      ..online = true
      ..addMember(ana);
    appState.rooms.add(room);

    await tester.pumpWidget(screen());
    await tester.tap(find.byTooltip('Leave room'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();

    expect(service.leftRoomCode, 'ABC234');
    expect(find.text('You left room ABC234.'), findsOneWidget);
  });

  testWidgets('the online room owner is identified in the room list', (
    tester,
  ) async {
    final service = _FakeOnlineChatService();
    ana.accountId = service.currentUid;
    appState = AppState(FakeStore(), onlineChatService: service)
      ..profiles.addAll([ana, ben])
      ..currentUser = ana;
    addTearDown(appState.dispose);
    appState.rooms.add(
      ChatRoom.withCode('ABC234')
        ..online = true
        ..ownerUid = service.currentUid
        ..members.add(ana),
    );

    await tester.pumpWidget(screen());

    expect(find.text('Owner'), findsOneWidget);
  });

  testWidgets('without an account system there is no online account icon', (
    tester,
  ) async {
    await tester.pumpWidget(screen());

    expect(find.byIcon(Icons.cloud_outlined), findsNothing);
    expect(find.byIcon(Icons.cloud_done), findsNothing);
  });

  testWidgets('with an account system the icon shows, and changes once the '
      'profile is linked', (tester) async {
    appState = AppState(FakeStore(), accountService: FakeAccountService());
    appState.profiles.addAll([ana, ben]);
    appState.currentUser = ana;

    await tester.pumpWidget(screen());
    expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);

    ana.accountId = 'uid1';
    await tester.pumpWidget(screen());
    await tester.pump();
    expect(find.byIcon(Icons.cloud_done), findsOneWidget);
  });

  // These two use pump() and not pumpAndSettle(): a glowing room pulses
  // forever, so the screen never "settles".
  testWidgets('a room with new messages glows', (tester) async {
    final room = ChatRoom.withCode('ABC234');
    room.addMember(ana);
    room.addMember(ben);
    room.messages.add(Message(sender: ben, text: 'hi'));
    appState.rooms.add(room);

    await tester.pumpWidget(screen());
    await tester.pump();

    expect(tester.widget<GlowPulse>(find.byType(GlowPulse)).active, true);
  });

  testWidgets('a room without new messages does not glow', (tester) async {
    final room = ChatRoom.withCode('ABC234');
    room.addMember(ana);
    room.addMember(ben);
    room.messages.add(Message(sender: ben, text: 'hi', seen: true));
    appState.rooms.add(room);

    await tester.pumpWidget(screen());
    await tester.pump();

    expect(tester.widget<GlowPulse>(find.byType(GlowPulse)).active, false);
  });

  testWidgets('the join request icon glows while requests are pending', (
    tester,
  ) async {
    final service = _FakeOnlineChatService();
    addTearDown(service.pendingRequests.close);
    ana.accountId = service.currentUid;
    appState = AppState(FakeStore(), onlineChatService: service)
      ..profiles.addAll([ana, ben])
      ..currentUser = ana;
    addTearDown(appState.dispose);
    final room = ChatRoom.withCode('ABC234')
      ..online = true
      ..ownerUid = service.currentUid
      ..members.add(ana);
    appState.rooms.add(room);

    await tester.pumpWidget(screen());
    await tester.pump();

    final glow = find.byKey(const ValueKey('join-requests-ABC234'));
    expect(tester.widget<GlowPulse>(glow).active, false);

    service.pendingRequests.add([
      const OnlineJoinRequest(
        requesterUid: 'ben-account',
        displayName: 'Ben',
        publicKey: 'public-key',
      ),
    ]);
    await tester.pump();

    expect(tester.widget<GlowPulse>(glow).active, true);

    service.pendingRequests.add(const []);
    await tester.pump();

    expect(tester.widget<GlowPulse>(glow).active, false);
  });

  testWidgets('a person who is already in a room is told to leave it first', (
    tester,
  ) async {
    await tester.pumpWidget(screen());

    await tester.tap(find.text('Create room'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK')); // close the "Room created!" dialog
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create room'));
    await tester.pump();

    expect(
      find.text(
        'You are already in a room. Leave it first to start a new one.',
      ),
      findsOneWidget,
    );
    expect(appState.rooms.length, 1);
  });
}
