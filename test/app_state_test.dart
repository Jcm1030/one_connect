import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oneconnect/accounts/account_service.dart';
import 'package:oneconnect/app_state.dart';
import 'package:oneconnect/models/app_settings.dart';
import 'package:oneconnect/models/chat_room.dart';
import 'package:oneconnect/models/profile.dart';
import 'package:oneconnect/photos/photo_store.dart';
import 'package:oneconnect/storage/data_store.dart';

import 'helpers/fake_account_service.dart';
import 'helpers/memory_key_store.dart';

// A storage that keeps nothing and only counts saves. It shows that AppState
// works with ANY storage, not only the text file.
class MemoryStorage implements AppStorage {
  int saveCalls = 0;
  bool saveResult = true;

  @override
  Future<LoadResult> load() async => LoadResult();

  @override
  Future<bool> save(
    List<Profile> profiles,
    List<ChatRoom> rooms, {
    AppSettings? settings,
  }) async {
    saveCalls++;
    return saveResult;
  }
}

void main() {
  late Directory tempDir;
  late File file;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('oneconnect_state_test');
    file = File('${tempDir.path}/oneconnect-data.txt');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('createProfile adds the profile, selects it and saves', () async {
    final appState = AppState(DataStore(file));

    final saved = await appState.createProfile('  Ana ', 'ana');

    expect(saved, true);
    expect(appState.profiles.length, 1);
    expect(appState.currentUser?.name, 'Ana');
    expect(await file.exists(), true);
  });

  test(
    'keepOnlyProfile removes other profiles and rooms, then saves',
    () async {
      final appState = AppState(DataStore(file));
      final ana = Profile(name: 'Ana', username: 'ana');
      final ben = Profile(name: 'Ben', username: 'ben');
      appState.profiles.addAll([ana, ben]);

      final anaRoom = ChatRoom.withCode('ANA234')..addMember(ana);
      final benRoom = ChatRoom.withCode('BEN234')..addMember(ben);
      appState.rooms.addAll([anaRoom, benRoom]);

      final saved = await appState.keepOnlyProfile(ana);

      expect(saved, true);
      expect(appState.profiles, [ana]);
      expect(appState.rooms, [anaRoom]);
      expect(appState.currentUser, isNull);
    },
  );

  test(
    'keepOnlyProfile restores data when the cleanup cannot be saved',
    () async {
      final storage = MemoryStorage()..saveResult = false;
      final appState = AppState(storage);
      final ana = Profile(name: 'Ana', username: 'ana');
      final ben = Profile(name: 'Ben', username: 'ben');
      appState.profiles.addAll([ana, ben]);
      final room = ChatRoom.withCode('ABC234')
        ..addMember(ana)
        ..addMember(ben);
      appState.rooms.add(room);
      final originalMessages = List.of(room.messages);

      final saved = await appState.keepOnlyProfile(ana);

      expect(saved, false);
      expect(appState.profiles, [ana, ben]);
      expect(appState.rooms, [room]);
      expect(room.members, [ana, ben]);
      expect(room.messages, originalMessages);
      expect(appState.currentUser, isNull);
    },
  );

  test('load restores saved profiles but selects nobody', () async {
    final first = AppState(DataStore(file));
    await first.createProfile('Ana', 'ana');

    final second = AppState(DataStore(file));
    await second.load();

    expect(second.profiles.length, 1);
    expect(second.profiles.first.username, 'ana');
    expect(second.currentUser, null);
    expect(second.loadWarnings.isEmpty, true);
  });

  group('rooms', () {
    late AppState appState;
    late Profile ana;
    late Profile ben;

    setUp(() async {
      appState = AppState(DataStore(file));
      await appState.createProfile('Ana', 'ana');
      ana = appState.currentUser!;
      await appState.createProfile('Ben', 'ben');
      ben = appState.currentUser!;
      appState.currentUser = ana;
    });

    test(
      'createRoom puts the current user in a new room with a unique code',
      () {
        final codes = <String>{};
        for (var i = 0; i < 200; i++) {
          // A different person each time: one person can only be in one room.
          appState.currentUser = Profile(name: 'P$i', username: 'p$i');
          codes.add(appState.createRoom()!.code);
        }
        expect(codes.length, 200);
        expect(appState.rooms.length, 200);
      },
    );

    test('a person who is already in a room cannot create another', () {
      expect(appState.createRoom(), isNotNull);
      expect(appState.createRoom(), null);
      expect(appState.rooms.length, 1);
    });

    test('a person in a room cannot join another, but can after leaving', () {
      final anasRoom = appState.createRoom()!;
      appState.currentUser = ben;
      final bensRoom = appState.createRoom()!;

      appState.currentUser = ana;
      expect(appState.joinRoom(bensRoom.code), JoinOutcome.inAnotherRoom);
      expect(bensRoom.members.length, 1);

      // Rejoining your own room is still reported as before.
      expect(appState.joinRoom(anasRoom.code), JoinOutcome.alreadyMember);

      appState.leaveRoom(anasRoom); // the room is empty, so it is deleted
      expect(appState.joinRoom(bensRoom.code), JoinOutcome.joined);
    });

    test('joinRoom with an unknown code gives roomNotFound', () {
      expect(appState.joinRoom('ZZZZZZ'), JoinOutcome.roomNotFound);
    });

    test(
      'joinRoom works in any case, then alreadyMember, then roomFull',
      () async {
        final room = appState.createRoom()!;

        appState.currentUser = ben;
        expect(appState.joinRoom(room.code.toLowerCase()), JoinOutcome.joined);
        expect(appState.joinRoom(room.code), JoinOutcome.alreadyMember);

        await appState.createProfile('Cara', 'cara');
        expect(appState.joinRoom(room.code), JoinOutcome.roomFull);
        expect(room.members.length, 2);
      },
    );

    test(
      'leaveRoom keeps the room and messages for the other member, deletes an '
      'empty room',
      () {
        final room = appState.createRoom()!;
        appState.currentUser = ben;
        appState.joinRoom(room.code);
        room.addMessage(ben, 'bye');

        expect(appState.leaveRoom(room), false); // Ben leaves, Ana is still in
        expect(room.hasMember(ben), false);
        expect(room.messages.length, 1);
        expect(appState.rooms.contains(room), true);

        appState.currentUser = ana;
        expect(appState.leaveRoom(room), true); // last person: room is deleted
        expect(appState.rooms.contains(room), false);
      },
    );

    test('myRooms only lists rooms the current user is in', () {
      final anasRoom = appState.createRoom()!;
      appState.currentUser = ben;
      final bensRoom = appState.createRoom()!;

      expect(appState.myRooms, [bensRoom]);
      appState.currentUser = ana;
      expect(appState.myRooms, [anasRoom]);
    });

    test(
      'after one of two people leaves, nobody else can join the room',
      () async {
        final room = appState.createRoom()!;
        appState.currentUser = ben;
        appState.joinRoom(room.code);
        appState.leaveRoom(room); // Ben leaves; the room is now closed

        await appState.createProfile('Cara', 'cara');
        expect(appState.joinRoom(room.code), JoinOutcome.roomClosed);
        expect(room.members.length, 1);
      },
    );

    test('renameCurrentUser changes the name but not the username', () {
      appState.renameCurrentUser('  Anna ');
      expect(ana.name, 'Anna');
      expect(ana.username, 'ana');
    });
  });

  test('createProfile stores the chosen color', () async {
    final appState = AppState(DataStore(file));
    await appState.createProfile('Ana', 'ana', ProfileColor.teal);
    expect(appState.currentUser?.color, ProfileColor.teal);
  });

  test('changing the current user notifies listeners', () async {
    final appState = AppState(DataStore(file));
    await appState.createProfile('Ana', 'ana');

    var calls = 0;
    appState.addListener(() => calls++);
    appState.currentUser = null;

    expect(calls, 1);
  });

  test(
    'an old save file is upgraded on load, and message ids stay the same',
    () async {
      await file.writeAsString(
        [
          'PROFILE|ana|Ana',
          'ROOM|ABC234|ana',
          'MESSAGE|ABC234|ana|2026-10-26T09:00:00|true|Old message',
        ].join('\n'),
      );

      final first = AppState(DataStore(file));
      await first.load();
      final id = first.rooms.first.messages.first.id;

      final text = await file.readAsString();
      expect(text.contains('MSG2|ABC234|ana'), true);
      expect(text.contains('MESSAGE|'), false);

      final second = AppState(DataStore(file));
      await second.load();
      expect(second.rooms.first.messages.first.id, id);
    },
  );

  test('AppState works with any storage, not only the file store', () async {
    final storage = MemoryStorage();
    final appState = AppState(storage);

    await appState.load();
    await appState.createProfile('Ana', 'ana');

    expect(storage.saveCalls, 1);
    expect(appState.profiles.length, 1);
  });

  test(
    'hasVerifiedAccount requires a matching signed-in verified account',
    () async {
      final service = FakeAccountService();
      final appState = AppState(DataStore(file), accountService: service);
      final ana = Profile(name: 'Ana', username: 'ana');

      expect(appState.hasVerifiedAccount(ana), false);

      final user = await service.signUp('ana@example.com', 'password123');
      ana.accountId = user.id;
      expect(appState.hasVerifiedAccount(ana), false);

      service.markEmailVerified('ana@example.com');
      final verifiedUser = await service.reloadUser();
      expect(verifiedUser.emailVerified, true);
      expect(appState.hasVerifiedAccount(ana), true);

      final other = Profile(
        name: 'Ben',
        username: 'ben',
        accountId: 'another-account',
      );
      expect(appState.hasVerifiedAccount(other), false);

      await service.signOut();
      expect(appState.hasVerifiedAccount(ana), false);
    },
  );

  group('linkAccount', () {
    late AppState appState;
    late Profile ana;
    late Profile ben;

    setUp(() {
      appState = AppState(DataStore(file));
      ana = Profile(name: 'Ana', username: 'ana');
      ben = Profile(name: 'Ben', username: 'ben');
      appState.profiles.addAll([ana, ben]);
      appState.currentUser = ana;
    });

    const verified = AccountUser(id: 'uid1', emailVerified: true);

    test('a verified account is linked to the current profile', () {
      expect(appState.linkAccount(verified), LinkResult.linked);
      expect(ana.accountId, 'uid1');
      // Linking the same account again is fine.
      expect(appState.linkAccount(verified), LinkResult.linked);
    });

    test('an account with an unverified email is refused', () {
      const unverified = AccountUser(id: 'uid1', emailVerified: false);
      expect(appState.linkAccount(unverified), LinkResult.notVerified);
      expect(ana.accountId, null);
    });

    test('an account that belongs to another profile is refused', () {
      appState.currentUser = ben;
      appState.linkAccount(verified);

      appState.currentUser = ana;
      expect(
        appState.linkAccount(verified),
        LinkResult.accountUsedByAnotherProfile,
      );
      expect(ana.accountId, null);
    });

    test('unlinking removes the account id from the profile', () {
      appState.linkAccount(verified);
      expect(ana.accountId, 'uid1');

      appState.unlinkAccount();

      expect(ana.accountId, null);
      // After unlinking, a different account can be linked.
      const other = AccountUser(id: 'uid2', emailVerified: true);
      expect(appState.linkAccount(other), LinkResult.linked);
    });

    test('a profile that already has a different account is refused', () {
      appState.linkAccount(verified);
      const other = AccountUser(id: 'uid2', emailVerified: true);

      expect(appState.linkAccount(other), LinkResult.profileHasAnotherAccount);
      expect(ana.accountId, 'uid1');
    });
  });

  test(
    'changeSettings applies the settings, tells listeners and saves',
    () async {
      final storage = MemoryStorage();
      final appState = AppState(storage);
      var calls = 0;
      appState.addListener(() => calls++);

      final saved = await appState.changeSettings(
        const AppSettings(themeChoice: ThemeChoice.dark),
      );

      expect(saved, true);
      expect(appState.settings.themeChoice, ThemeChoice.dark);
      expect(calls, 1);
      expect(storage.saveCalls, 1);
    },
  );

  test('settings survive a restart', () async {
    final first = AppState(DataStore(file));
    await first.changeSettings(
      const AppSettings(textSize: TextSizeChoice.large, reduceAnimations: true),
    );

    final second = AppState(DataStore(file));
    await second.load();

    expect(second.settings.textSize, TextSizeChoice.large);
    expect(second.settings.reduceAnimations, true);
  });

  group('photos', () {
    late Directory photosDir;
    late AppState appState;
    late Profile ana;
    late File picked;

    setUp(() {
      photosDir = Directory('${tempDir.path}/photos');
      appState = AppState(DataStore(file), photoStore: PhotoStore(photosDir));
      ana = Profile(name: 'Ana', username: 'ana');
      appState.profiles.add(ana);
      picked = File('${tempDir.path}/picked.png')..writeAsBytesSync([1, 2, 3]);
    });

    test(
      'a photo is copied in and saved, and removing it deletes the file',
      () async {
        expect(await appState.setProfilePhoto(ana, picked), true);

        expect(ana.photoFileName, isNotNull);
        expect(appState.photoFileOf(ana)!.readAsBytesSync(), [1, 2, 3]);
        expect(
          await file.readAsString(),
          contains('PHOTO|ana|${ana.photoFileName}'),
        );

        expect(await appState.removeProfilePhoto(ana), true);
        expect(ana.photoFileName, null);
        expect(photosDir.listSync().isEmpty, true);
      },
    );

    test('a new photo replaces the old file', () async {
      await appState.setProfilePhoto(ana, picked);
      final first = ana.photoFileName;
      await appState.setProfilePhoto(ana, picked);

      expect(ana.photoFileName == first, false);
      expect(photosDir.listSync().length, 1);
    });

    test('without a photo store nothing is stored, and a missing file shows '
        'no photo', () async {
      final plain = AppState(DataStore(file));
      expect(await plain.setProfilePhoto(ana, picked), false);

      ana.photoFileName = 'ana_9_9.jpg'; // this file does not exist
      expect(appState.photoFileOf(ana), null);
    });
  });

  group('encryption keys', () {
    late MemoryKeyStore keyStore;
    late AppState appState;
    late Profile ana;

    setUp(() {
      keyStore = MemoryKeyStore();
      appState = AppState(DataStore(file), keyStore: keyStore);
      ana = Profile(name: 'Ana', username: 'ana', accountId: 'uid1');
      appState.profiles.add(ana);
      appState.currentUser = ana;
    });

    test(
      'keys are created for a linked profile and reused afterwards',
      () async {
        expect(await appState.loadKeys(ana), null); // none yet

        final first = await appState.ensureKeys(ana);
        final second = await appState.ensureKeys(ana);

        expect(first, isNotNull);
        expect(first!.publicKeyBytes.length, 32);
        expect(second!.publicKeyBytes, first.publicKeyBytes);
        expect(keyStore.keys.length, 1);
        expect(
          (await appState.loadKeys(ana))!.privateKeyBytes,
          first.privateKeyBytes,
        );
      },
    );

    test(
      'no keys are made without an account link or without key storage',
      () async {
        final local = Profile(name: 'Ben', username: 'ben'); // not linked
        expect(await appState.ensureKeys(local), null);

        final plain = AppState(DataStore(file)); // no key storage
        expect(await plain.ensureKeys(ana), null);
        expect(await plain.loadKeys(ana), null);
        expect(keyStore.keys.isEmpty, true);
      },
    );

    test('a broken secure storage gives null instead of crashing', () async {
      keyStore.failSave = true;

      expect(await appState.ensureKeys(ana), null);
      expect(keyStore.keys.isEmpty, true);
    });
  });
}
