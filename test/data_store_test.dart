import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oneconnect/models/app_settings.dart';
import 'package:oneconnect/models/chat_room.dart';
import 'package:oneconnect/models/message.dart';
import 'package:oneconnect/models/profile.dart';
import 'package:oneconnect/storage/data_store.dart';

void main() {
  late Directory tempDir;
  late File file;
  late DataStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('oneconnect_test');
    file = File('${tempDir.path}/oneconnect-data.txt');
    store = DataStore(file);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('save then load brings everything back', () async {
    final ana = Profile(name: 'Ana', username: 'ana');
    final ben = Profile(name: 'Ben | B', username: 'ben');
    final room = ChatRoom.withCode('ABC234');
    room.addMember(ana);
    room.addMember(ben);
    final time = DateTime(2026, 10, 26, 9, 30, 15, 123, 456);
    room.messages.add(
      Message(sender: ana, text: 'Hello | Ben!', timestamp: time, seen: true),
    );
    room.messages.add(
      Message(
        sender: ben,
        text: 'Hi Ana',
        timestamp: time.add(const Duration(minutes: 1)),
      ),
    );

    expect(await store.save([ana, ben], [room]), true);
    final result = await store.load();

    expect(result.warnings.isEmpty, true);
    expect(result.profiles.length, 2);
    expect(result.profiles[1].name, 'Ben | B');
    expect(result.rooms.length, 1);
    expect(result.rooms.first.code, 'ABC234');
    expect(result.rooms.first.members.length, 2);

    final messages = result.rooms.first.messages;
    expect(messages.length, 2);
    expect(messages[0].text, 'Hello | Ben!');
    expect(messages[0].timestamp, time);
    expect(messages[0].seen, true);
    expect(messages[1].seen, false);
    // The message must point at the SAME loaded profile object.
    expect(identical(messages[0].sender, result.profiles[0]), true);
  });

  test('a missing file loads as empty with no warnings', () async {
    final result = await store.load();
    expect(result.profiles.isEmpty, true);
    expect(result.rooms.isEmpty, true);
    expect(result.warnings.isEmpty, true);
  });

  test('an empty file loads as empty with no warnings', () async {
    await file.writeAsString('');
    final result = await store.load();
    expect(result.profiles.isEmpty, true);
    expect(result.rooms.isEmpty, true);
    expect(result.warnings.isEmpty, true);
  });

  test(
    'bad lines are skipped with warnings and good lines still load',
    () async {
      await file.writeAsString(
        [
          'this is not valid', // 1 unknown type
          'PROFILE|ana|Ana',
          'PROFILE|ana|Duplicate Ana', // 3 duplicate username
          'PROFILE|x|Too Short', // 4 invalid username
          'PROFILE|ben|Ben',
          'ROOM|ABC234|ana|ben',
          'ROOM|ABC234|ana', // 7 duplicate room code
          'ROOM|BAD|ana', // 8 invalid room code
          'ROOM|QWE456|ana|ghost', // 9 unknown profile
          'MESSAGE|ABC234|ana|2026-10-26T09:00:00|true|Good message',
          'MESSAGE|ABC234|ana|not-a-time|true|Bad time', // 11
          'MESSAGE|ABC234|ana|2026-10-26T09:01:00|maybe|Bad seen', // 12
          'MESSAGE|NOROOM|ana|2026-10-26T09:02:00|true|No such room', // 13
          'MESSAGE|ABC234|ghost|2026-10-26T09:03:00|true|No such sender', // 14
          'MESSAGE|ABC234|ana|2026-10-26T09:04:00|true|', // 15 no text
          'MESSAGE|ABC234', // 16 incomplete
        ].join('\n'),
      );

      final result = await store.load();

      expect(result.warnings.length, 12);
      expect(result.profiles.length, 2);
      expect(result.rooms.length, 1);
      expect(result.rooms.first.messages.length, 1);
      expect(result.rooms.first.messages.first.text, 'Good message');
    },
  );

  test('a message from someone who left the room still loads', () async {
    await file.writeAsString(
      [
        'PROFILE|ana|Ana',
        'PROFILE|ben|Ben',
        'ROOM|ABC234|ana',
        'MESSAGE|ABC234|ben|2026-10-26T09:00:00|true|I left later',
      ].join('\n'),
    );

    final result = await store.load();

    expect(result.warnings.isEmpty, true);
    expect(result.rooms.first.messages.length, 1);
  });

  test('an unreadable (non-text) file gives one warning and no data', () async {
    await file.writeAsBytes([0xff, 0xfe, 0xfd, 0x80, 0x81]);
    final result = await store.load();
    expect(result.warnings.length, 1);
    expect(result.profiles.isEmpty, true);
  });

  test('saving twice replaces the file and leaves no temp file', () async {
    final ana = Profile(name: 'Ana', username: 'ana');
    final ben = Profile(name: 'Ben', username: 'ben');

    expect(await store.save([ana], []), true);
    expect(await store.save([ana, ben], []), true);

    final result = await store.load();
    expect(result.profiles.length, 2);
    expect(File('${file.path}.tmp').existsSync(), false);
  });

  test('save returns false when the folder does not exist', () async {
    final badStore = DataStore(File('${tempDir.path}/no_such_folder/data.txt'));
    expect(await badStore.save([], []), false);
  });

  test('a closed room is still closed after saving and loading', () async {
    final ana = Profile(name: 'Ana', username: 'ana');
    final ben = Profile(name: 'Ben', username: 'ben');
    final room = ChatRoom.withCode('ABC234');
    room.addMember(ana);
    room.addMember(ben);
    room.removeMember(ben); // leaving a full room closes it
    expect(room.closed, true);

    await store.save([ana, ben], [room]);
    final result = await store.load();

    expect(result.warnings.isEmpty, true);
    expect(result.rooms.first.closed, true);
    expect(result.rooms.first.members.length, 1);
  });

  test('a room line without the closed marker loads as open, even when a '
      'username is "closed"', () async {
    await file.writeAsString(
      ['PROFILE|closed|Casey', 'ROOM|ABC234|closed'].join('\n'),
    );

    final result = await store.load();

    expect(result.warnings.isEmpty, true);
    expect(result.rooms.first.closed, false);
    expect(result.rooms.first.members.length, 1);
  });

  test(
    'each profile keeps its chosen color after saving and loading',
    () async {
      final ana = Profile(
        name: 'Ana',
        username: 'ana',
        color: ProfileColor.teal,
      );
      final ben = Profile(
        name: 'Ben',
        username: 'ben',
        color: ProfileColor.purple,
      );
      final cara = Profile(name: 'Cara', username: 'cara'); // default pink

      await store.save([ana, ben, cara], []);
      final result = await store.load();

      expect(result.warnings.isEmpty, true);
      expect(result.profiles[0].color, ProfileColor.teal);
      expect(result.profiles[1].color, ProfileColor.purple);
      expect(result.profiles[2].color, ProfileColor.pink);
    },
  );

  test('an old file with no COLOR lines loads as pink, and bad COLOR lines '
      'are skipped with warnings', () async {
    await file.writeAsString(
      [
        'PROFILE|ana|Ana',
        'COLOR|ghost|teal', // unknown profile
        'COLOR|ana|orange', // unknown color
      ].join('\n'),
    );

    final result = await store.load();

    expect(result.warnings.length, 2);
    expect(result.profiles.first.color, ProfileColor.pink);
  });

  test('message ids are saved and loaded unchanged', () async {
    final ana = Profile(name: 'Ana', username: 'ana');
    final room = ChatRoom.withCode('ABC234');
    room.addMember(ana);
    final first = room.addMessage(ana, 'one')!;
    final second = room.addMessage(ana, 'two | with a pipe')!;

    await store.save([ana], [room]);
    final result = await store.load();

    final messages = result.rooms.first.messages;
    expect(result.warnings.isEmpty, true);
    expect(result.upgradedFromOldFormat, false);
    expect(messages[0].id, first.id);
    expect(messages[1].id, second.id);
    expect(messages[1].text, 'two | with a pipe');
  });

  test('a bad or repeated message id is skipped with a warning', () async {
    final good = 'a' * 32;
    await file.writeAsString(
      [
        'PROFILE|ana|Ana',
        'ROOM|ABC234|ana',
        'MSG2|ABC234|ana|2026-10-26T09:00:00|true|$good|First',
        'MSG2|ABC234|ana|2026-10-26T09:01:00|true|$good|Same id again',
        'MSG2|ABC234|ana|2026-10-26T09:02:00|true|not-an-id|Bad id',
      ].join('\n'),
    );

    final result = await store.load();

    expect(result.warnings.length, 2);
    expect(result.rooms.first.messages.length, 1);
    expect(result.rooms.first.messages.first.text, 'First');
  });

  test(
    'old MESSAGE lines load with new ids and are marked as upgraded',
    () async {
      await file.writeAsString(
        [
          'PROFILE|ana|Ana',
          'ROOM|ABC234|ana',
          'MESSAGE|ABC234|ana|2026-10-26T09:00:00|true|Old message',
        ].join('\n'),
      );

      final result = await store.load();

      expect(result.warnings.isEmpty, true);
      expect(result.upgradedFromOldFormat, true);
      expect(result.rooms.first.messages.first.id.length, 32);
    },
  );

  test(
    'account ids are saved and loaded, local-only profiles stay without one',
    () async {
      final ana = Profile(name: 'Ana', username: 'ana', accountId: 'uid_Ana-1');
      final ben = Profile(name: 'Ben', username: 'ben'); // local only

      await store.save([ana, ben], []);
      final result = await store.load();

      expect(result.warnings.isEmpty, true);
      expect(result.profiles[0].accountId, 'uid_Ana-1');
      expect(result.profiles[1].accountId, null);
      // Only the id is written, never anything like an email or a password.
      expect((await file.readAsString()).contains('@'), false);
    },
  );

  test('bad ACCOUNT lines are skipped with warnings', () async {
    await file.writeAsString(
      [
        'PROFILE|ana|Ana',
        'PROFILE|ben|Ben',
        'ACCOUNT|ana|goodId123',
        'ACCOUNT|ghost|someId', // unknown profile
        'ACCOUNT|ben|not valid!', // invalid id
        'ACCOUNT|ben|goodId123', // already used by ana
        'ACCOUNT|ben', // incomplete
      ].join('\n'),
    );

    final result = await store.load();

    expect(result.warnings.length, 4);
    expect(result.profiles[0].accountId, 'goodId123');
    expect(result.profiles[1].accountId, null);
  });

  test('settings are saved and loaded', () async {
    await store.save(
      [],
      [],
      settings: const AppSettings(
        themeChoice: ThemeChoice.dark,
        textSize: TextSizeChoice.large,
        reduceAnimations: true,
      ),
    );

    final result = await store.load();

    expect(result.warnings.isEmpty, true);
    expect(result.settings.themeChoice, ThemeChoice.dark);
    expect(result.settings.textSize, TextSizeChoice.large);
    expect(result.settings.reduceAnimations, true);
  });

  test('a file without settings loads the default settings', () async {
    await file.writeAsString('PROFILE|ana|Ana');

    final result = await store.load();

    expect(result.warnings.isEmpty, true);
    expect(result.settings.themeChoice, ThemeChoice.system);
    expect(result.settings.textSize, TextSizeChoice.normal);
    expect(result.settings.reduceAnimations, false);
  });

  test(
    'bad SETTING lines are skipped with warnings, good ones still apply',
    () async {
      await file.writeAsString(
        [
          'SETTING|theme|dark',
          'SETTING|theme|neon', // unknown value
          'SETTING|textSize|huge', // unknown value
          'SETTING|reduceAnimations|maybe', // not true or false
          'SETTING|colour|red', // unknown setting
          'SETTING|theme', // incomplete
        ].join('\n'),
      );

      final result = await store.load();

      expect(result.warnings.length, 5);
      expect(result.settings.themeChoice, ThemeChoice.dark);
    },
  );

  test(
    'photo file names are saved and loaded, without any folder path',
    () async {
      final ana = Profile(
        name: 'Ana',
        username: 'ana',
        photoFileName: 'ana_123_0.jpg',
      );
      final ben = Profile(name: 'Ben', username: 'ben');

      await store.save([ana, ben], []);
      final result = await store.load();

      expect(result.warnings.isEmpty, true);
      expect(result.profiles[0].photoFileName, 'ana_123_0.jpg');
      expect(result.profiles[1].photoFileName, null);
      expect(await file.readAsString(), contains('PHOTO|ana|ana_123_0.jpg'));
    },
  );

  test('bad PHOTO lines are skipped with warnings', () async {
    await file.writeAsString(
      [
        'PROFILE|ana|Ana',
        'PHOTO|ghost|a.jpg', // unknown profile
        'PHOTO|ana|../evil.jpg', // tries to leave the photos folder
        'PHOTO|ana|folder/pic.jpg', // a path, not a file name
        'PHOTO|ana|noextension', // not a picture file name
        'PHOTO|ana', // incomplete
      ].join('\n'),
    );

    final result = await store.load();

    expect(result.warnings.length, 5);
    expect(result.profiles.first.photoFileName, null);
  });
}
