import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneconnect/app_state.dart';
import 'package:oneconnect/models/profile.dart';
import 'package:oneconnect/photos/photo_store.dart';
import 'package:oneconnect/widgets/profile_avatar.dart';

import 'helpers/fake_store.dart';

// A tiny real picture (1 pixel), so the image can be read.
final _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  late Directory tempDir;
  late PhotoStore photoStore;
  late AppState appState;
  late Profile ana;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('oneconnect_avatar_test');
    photoStore = PhotoStore(Directory('${tempDir.path}/photos'));
    appState = AppState(FakeStore(), photoStore: photoStore);
    ana = Profile(name: 'Ana', username: 'ana');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Widget avatar(Profile? profile) => MaterialApp(
    home: Scaffold(
      body: ProfileAvatar(appState: appState, profile: profile),
    ),
  );

  testWidgets('shows the initial when there is no photo', (tester) async {
    await tester.pumpWidget(avatar(ana));

    expect(find.text('A'), findsOneWidget);
    expect(
      tester.widget<CircleAvatar>(find.byType(CircleAvatar)).backgroundImage,
      null,
    );
  });

  testWidgets('shows the photo when the file exists', (tester) async {
    Directory('${tempDir.path}/photos').createSync(recursive: true);
    photoStore.fileFor('ana_1_0.png').writeAsBytesSync(_tinyPng);
    ana.photoFileName = 'ana_1_0.png';

    await tester.pumpWidget(avatar(ana));

    expect(find.text('A'), findsNothing);
    expect(
      tester.widget<CircleAvatar>(find.byType(CircleAvatar)).backgroundImage,
      isA<FileImage>(),
    );
  });

  testWidgets('shows a heart when there is no profile', (tester) async {
    await tester.pumpWidget(avatar(null));

    expect(find.byIcon(Icons.person_outline), findsOneWidget);
  });
}
