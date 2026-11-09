import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneconnect/app_state.dart';
import 'package:oneconnect/models/chat_room.dart';
import 'package:oneconnect/models/profile.dart';
import 'package:oneconnect/photos/photo_service.dart';
import 'package:oneconnect/screens/profile_screen.dart';

import 'helpers/fake_account_service.dart';
import 'helpers/fake_photo_service.dart';
import 'helpers/fake_store.dart';

final _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('oneconnect_profile_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Widget screen(AppState appState) =>
      MaterialApp(home: ProfileScreen(appState: appState));

  testWidgets('without a photo picker there is no photo button', (
    tester,
  ) async {
    await tester.pumpWidget(screen(AppState(FakeStore())));
    await tester.pump();

    expect(find.text('Add a photo (optional)'), findsNothing);
  });

  testWidgets('new profile stays unselected until its email is verified', (
    tester,
  ) async {
    final appState = AppState(
      FakeStore(),
      accountService: FakeAccountService(),
    );
    await tester.pumpWidget(screen(appState));

    await tester.enterText(find.byType(TextFormField).at(0), 'Ana');
    await tester.enterText(find.byType(TextFormField).at(1), 'ana');
    await tester.tap(find.text('Create profile'));
    await tester.pumpAndSettle();

    expect(appState.profiles, hasLength(1));
    expect(appState.currentUser, isNull);
    expect(find.text('Online account'), findsOneWidget);
  });

  testWidgets('greets the current user and shows the time-based greeting', (
    tester,
  ) async {
    final appState = AppState(FakeStore())
      ..currentUser = Profile(name: 'Ana', username: 'ana');
    await tester.pumpWidget(screen(appState));

    expect(find.text('Hi, Ana!'), findsOneWidget);
    expect(find.text('One Connect'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image && widget.semanticLabel == 'One Connect logo',
      ),
      findsOneWidget,
    );
    final headerRow = find.ancestor(
      of: find.byWidgetPredicate(
        (widget) =>
            widget is Image && widget.semanticLabel == 'One Connect logo',
      ),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: headerRow, matching: find.text('Hi, Ana!')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: headerRow, matching: find.text('One Connect')),
      findsOneWidget,
    );
    final hour = DateTime.now().hour;
    final greeting = hour >= 5 && hour < 12
        ? 'Good morning'
        : hour >= 12 && hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    expect(find.text(greeting), findsOneWidget);
  });

  testWidgets('with a photo picker the photo button is shown', (tester) async {
    final appState = AppState(FakeStore(), photoService: FakePhotoService());
    await tester.pumpWidget(screen(appState));
    await tester.pump();

    expect(find.text('Add a photo (optional)'), findsOneWidget);
  });

  testWidgets('an existing profile must link an email before continuing', (
    tester,
  ) async {
    final ana = Profile(name: 'Ana', username: 'ana');
    final appState = AppState(FakeStore(), accountService: FakeAccountService())
      ..profiles.add(ana);

    await tester.pumpWidget(screen(appState));
    expect(find.text('Link email to continue'), findsOneWidget);
    expect(appState.currentUser, isNull);

    await tester.tap(find.text('Link email to continue'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(find.text('Rooms'), findsNothing);
    expect(appState.currentUser, isNull);
  });

  testWidgets('a linked profile can continue without creating another', (
    tester,
  ) async {
    final service = FakeAccountService();
    final signedUp = await service.signUp('ana@example.com', 'password123');
    service.markEmailVerified('ana@example.com');
    final verifiedUser = await service.reloadUser();
    final ana = Profile(
      name: 'Ana',
      username: 'ana',
      accountId: verifiedUser.id,
    );
    final appState = AppState(FakeStore(), accountService: service)
      ..profiles.add(ana);

    expect(signedUp.id, verifiedUser.id);
    await tester.pumpWidget(screen(appState));
    expect(find.text('Create profile'), findsNothing);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Rooms'), findsOneWidget);
    expect(appState.currentUser, same(ana));
  });

  testWidgets('auto continues a single linked verified profile', (
    tester,
  ) async {
    final service = FakeAccountService();
    await service.signUp('ana@example.com', 'password123');
    service.markEmailVerified('ana@example.com');
    final verifiedUser = await service.reloadUser();
    final ana = Profile(
      name: 'Ana',
      username: 'ana',
      accountId: verifiedUser.id,
    );
    final appState = AppState(FakeStore(), accountService: service)
      ..profiles.add(ana);

    await tester.pumpWidget(
      MaterialApp(home: ProfileScreen(appState: appState, autoContinue: true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rooms'), findsOneWidget);
    expect(appState.currentUser, same(ana));
  });

  testWidgets('a saved link is not enough when the linked account is signed '
      'out', (tester) async {
    final ana = Profile(name: 'Ana', username: 'ana', accountId: 'uid1');
    final appState = AppState(FakeStore(), accountService: FakeAccountService())
      ..profiles.add(ana);

    await tester.pumpWidget(screen(appState));
    expect(find.text('Sign in to continue'), findsOneWidget);

    await tester.tap(find.text('Sign in to continue'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(find.text('Rooms'), findsNothing);
  });

  testWidgets('keeping one legacy profile requires confirmation and removes '
      'other profiles and their rooms', (tester) async {
    final ana = Profile(name: 'Ana', username: 'ana');
    final ben = Profile(name: 'Ben', username: 'ben');
    final anaRoom = ChatRoom.withCode('ANA234')..addMember(ana);
    final benRoom = ChatRoom.withCode('BEN234')..addMember(ben);
    final appState = AppState(FakeStore(), accountService: FakeAccountService())
      ..profiles.addAll([ana, ben])
      ..rooms.addAll([anaRoom, benRoom]);

    await tester.pumpWidget(screen(appState));
    expect(find.text('Create profile'), findsNothing);
    await tester.tap(find.text('Ana').first);
    await tester.pumpAndSettle();

    expect(find.text('Keep Ana?'), findsOneWidget);
    expect(find.textContaining('rooms and messages'), findsOneWidget);
    await tester.tap(find.text('Keep Ana only'));
    await tester.pumpAndSettle();

    expect(appState.profiles, [ana]);
    expect(appState.rooms, [anaRoom]);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('choosing a photo from the gallery shows it on the form', (
    tester,
  ) async {
    final picture = File('${tempDir.path}/picked.png')
      ..writeAsBytesSync(_tinyPng);
    final fakePicker = FakePhotoService()..next = picture;
    final appState = AppState(FakeStore(), photoService: fakePicker);

    await tester.pumpWidget(screen(appState));
    await tester.pump();

    await tester.tap(find.text('Add a photo (optional)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // the sheet slides up

    await tester.tap(find.text('Choose from gallery'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // the sheet closes
    await tester.pump();

    expect(fakePicker.lastSource, PhotoSource.gallery);
    expect(find.text('Change photo'), findsOneWidget);
  });
}
