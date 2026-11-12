import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneconnect/app_state.dart';
import 'package:oneconnect/models/chat_room.dart';
import 'package:oneconnect/models/message.dart';
import 'package:oneconnect/models/profile.dart';
import 'package:oneconnect/screens/chat_screen.dart';
import 'package:oneconnect/theme.dart';
import 'helpers/fake_store.dart';

void main() {
  late Profile ana;
  late Profile ben;
  late ChatRoom room;
  late AppState appState;

  setUp(() {
    ana = Profile(name: 'Ana', username: 'ana');
    ben = Profile(name: 'Ben', username: 'ben');
    room = ChatRoom.withCode('ABC234');
    room.addMember(ana);
    room.addMember(ben);
    appState = AppState(FakeStore());
    appState.profiles.addAll([ana, ben]);
    appState.rooms.add(room);
    appState.currentUser = ana;
  });

  Widget screen() => MaterialApp(
    home: ChatScreen(appState: appState, room: room),
  );

  testWidgets('sending a message shows it with the Sent status', (
    tester,
  ) async {
    var clickSounds = 0;
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemSound.play') {
        clickSounds++;
      }
      return null;
    });
    try {
      await tester.pumpWidget(screen());

      await tester.enterText(find.byType(TextField), 'Hello Ben');
      clickSounds = 0;
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    }

    expect(room.messages.length, 1);
    expect(find.text('Hello Ben'), findsOneWidget);
    expect(find.byTooltip('Sent'), findsOneWidget);
    expect(clickSounds, 1);
  });

  testWidgets('chat header shows the other person and chat actions', (
    tester,
  ) async {
    await tester.pumpWidget(screen());

    expect(find.text('Ben'), findsOneWidget);
    expect(find.text('@ben'), findsOneWidget);
    expect(find.text('add'), findsOneWidget);
    expect(find.byTooltip('More options'), findsOneWidget);
  });

  testWidgets('guest chat tells the remaining member when the other leaves', (
    tester,
  ) async {
    await tester.pumpWidget(screen());

    room
      ..online = true
      ..guest = true
      ..closed = true;
    appState.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.text('Guest room closed'), findsOneWidget);
    expect(find.textContaining('left the guest room'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Guest room closed'), findsNothing);
  });

  testWidgets('focusing the message box scrolls to the latest message', (
    tester,
  ) async {
    for (var index = 0; index < 30; index++) {
      room.messages.add(Message(sender: ben, text: 'Message $index'));
    }

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    final list = tester.widget<ListView>(find.byType(ListView));
    final scrollController = list.controller!;
    expect(
      scrollController.position.pixels,
      scrollController.position.maxScrollExtent,
    );

    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(
      scrollController.position.pixels,
      lessThan(scrollController.position.maxScrollExtent),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(
      scrollController.position.pixels,
      scrollController.position.maxScrollExtent,
    );
  });

  testWidgets('a new message scrolls the chat to the latest message', (
    tester,
  ) async {
    for (var index = 0; index < 30; index++) {
      room.messages.add(
        Message(sender: ben, text: 'Message $index', seen: true),
      );
    }

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    final list = tester.widget<ListView>(find.byType(ListView));
    final scrollController = list.controller!;
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(
      scrollController.position.pixels,
      lessThan(scrollController.position.maxScrollExtent),
    );

    room.messages.add(Message(sender: ben, text: 'A new message', seen: true));
    appState.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.text('A new message'), findsOneWidget);
    expect(
      scrollController.position.pixels,
      scrollController.position.maxScrollExtent,
    );
  });

  testWidgets('sending while scrolled up brings the sent message into view', (
    tester,
  ) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    for (var index = 0; index < 40; index++) {
      room.messages.add(
        Message(
          sender: ben,
          text: List.filled(index % 4 + 1, 'Earlier message $index').join(' '),
          seen: true,
        ),
      );
    }

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Just sent');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    final listRect = tester.getRect(find.byType(ListView));
    final messageRect = tester.getRect(find.text('Just sent'));
    final composerRect = tester.getRect(find.byType(TextField));
    expect(messageRect.overlaps(listRect), isTrue);
    expect(messageRect.bottom, lessThan(composerRect.top));
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(
      list.controller!.position.pixels,
      list.controller!.position.maxScrollExtent,
    );
  });

  testWidgets('an empty message is refused with a message', (tester) async {
    await tester.pumpWidget(screen());

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(room.messages.isEmpty, true);
    expect(find.text("Message can't be empty."), findsOneWidget);
  });

  testWidgets('opening the chat marks the other persons messages as seen', (
    tester,
  ) async {
    final fromBen = Message(sender: ben, text: 'Hi Ana');
    final fromAna = Message(sender: ana, text: 'Hi Ben');
    room.messages.addAll([fromBen, fromAna]);

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    expect(fromBen.seen, true);
    expect(fromAna.seen, false); // your own messages do not change
  });

  testWidgets('the message box has its own menu, so Copy and Cut can be '
      'removed', (tester) async {
    await tester.pumpWidget(screen());

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.contextMenuBuilder, isNotNull);
  });

  testWidgets('the message box and composer use dark theme colors', (
    tester,
  ) async {
    final darkTheme = buildTheme(ProfileColor.purple, Brightness.dark);
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        darkTheme: darkTheme,
        themeMode: ThemeMode.dark,
        home: ChatScreen(appState: appState, room: room),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(
      field.decoration!.fillColor,
      darkTheme.colorScheme.surfaceContainerHighest,
    );
    expect(
      find.ancestor(
        of: find.byType(TextField),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).color ==
                  darkTheme.colorScheme.surface,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('message text cannot be selected, so it cannot be copied', (
    tester,
  ) async {
    room.messages.add(Message(sender: ben, text: 'Secret hello'));
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    expect(find.text('Secret hello'), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.byType(SelectionArea), findsNothing);
  });

  testWidgets('messages waiting when the chat opens get a New messages line', (
    tester,
  ) async {
    room.messages.add(Message(sender: ben, text: 'Are you there?'));

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    expect(find.text('New messages'), findsOneWidget);
    expect(find.text('Are you there?'), findsOneWidget);
  });

  testWidgets(
    'there is no New messages line when everything was already seen',
    (tester) async {
      room.messages.add(Message(sender: ben, text: 'Old news', seen: true));

      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();

      expect(find.text('New messages'), findsNothing);
    },
  );
}
