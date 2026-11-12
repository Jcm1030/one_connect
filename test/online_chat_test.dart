import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oneconnect/app_state.dart';
import 'package:oneconnect/crypto/message_crypto.dart';
import 'package:oneconnect/models/chat_room.dart';
import 'package:oneconnect/models/message.dart';
import 'package:oneconnect/models/profile.dart';
import 'package:oneconnect/online/online_chat_service.dart';

import 'helpers/fake_store.dart';
import 'helpers/memory_key_store.dart';

class _FakeOnlineChatService implements OnlineChatService {
  @override
  String currentUid = 'ana-account';

  OnlineRoomMember? createdOwner;
  String? sentCiphertext;
  String? sentMessageId;
  String? sentReplyToId;
  final List<String> seenMessageIds = [];
  final List<String?> reactions = [];
  final Map<String, String> usernamesByUid = {};

  @override
  Future<void> createRoom({
    required String code,
    required OnlineRoomMember owner,
  }) async {
    createdOwner = owner;
  }

  @override
  Future<void> requestToJoin({
    required String code,
    required OnlineRoomMember requester,
  }) async {}

  @override
  Future<void> decideJoinRequest({
    required String code,
    required String requesterUid,
    required bool approve,
  }) async {}

  @override
  Future<void> leaveRoom(String code) async {}

  @override
  Future<void> markKeyVerified(String code) async {}

  @override
  Stream<List<OnlineRoom>> watchMyRooms() => Stream.value(const []);

  @override
  Stream<List<OnlineJoinRequest>> watchJoinRequests(String code) =>
      Stream.value(const []);

  @override
  Stream<List<EncryptedChatMessage>> watchMessages(String code) =>
      Stream.value(const []);

  @override
  Future<void> sendMessage({
    required String code,
    required String messageId,
    required String ciphertext,
    String? replyToId,
  }) async {
    sentMessageId = messageId;
    sentCiphertext = ciphertext;
    sentReplyToId = replyToId;
  }

  @override
  Future<void> setReaction({
    required String code,
    required String messageId,
    String? emoji,
  }) async {
    reactions.add(emoji);
  }

  @override
  Future<void> markSeen({
    required String code,
    required String messageId,
  }) async {
    seenMessageIds.add(messageId);
  }

  @override
  Future<void> sendTalkRequest({
    required String toUid,
    required String toUsername,
    required OnlineRoomMember sender,
  }) async {}

  @override
  Future<void> acceptTalkRequest({
    required TalkRequest request,
    required String roomCode,
    required OnlineRoomMember me,
  }) async {}

  @override
  Future<void> declineTalkRequest(TalkRequest request) async {}

  @override
  Future<String?> lookupUsername(String uid) async => usernamesByUid[uid];

  @override
  Stream<List<TalkRequest>> watchIncomingTalkRequests() =>
      Stream.value(const []);

  @override
  Stream<List<TalkRequest>> watchOutgoingTalkRequests() =>
      Stream.value(const []);
}

class _StreamingFakeOnlineChatService extends _FakeOnlineChatService {
  final roomUpdates = StreamController<List<OnlineRoom>>.broadcast(sync: true);

  @override
  Stream<List<OnlineRoom>> watchMyRooms() => roomUpdates.stream;
}

class _MessagingStreamingFakeOnlineChatService
    extends _StreamingFakeOnlineChatService {
  final messageUpdates = StreamController<List<EncryptedChatMessage>>.broadcast(
    sync: true,
  );

  @override
  Stream<List<EncryptedChatMessage>> watchMessages(String code) =>
      messageUpdates.stream;
}

class _CreatingStreamingFakeOnlineChatService
    extends _StreamingFakeOnlineChatService {
  @override
  Future<void> createRoom({
    required String code,
    required OnlineRoomMember owner,
  }) async {
    await super.createRoom(code: code, owner: owner);
    roomUpdates.add([
      OnlineRoom(
        code: code,
        ownerUid: owner.uid,
        members: {owner.uid: owner},
        verifiedUids: const [],
        closed: false,
      ),
    ]);
  }
}

void main() {
  test('online room member usernames are normalized for Firestore rules', () {
    const member = OnlineRoomMember(
      uid: 'ana-account',
      displayName: 'Ana',
      username: 'Ana_User',
      publicKey: 'public-key',
    );

    expect(member.toMap()['username'], 'ana_user');
  });

  test('ownership transfers to the roommate when the creator leaves', () {
    const room = OnlineRoom(
      code: 'ABC234',
      ownerUid: 'creator',
      members: {
        'creator': OnlineRoomMember(
          uid: 'creator',
          displayName: 'Ana',
          publicKey: 'creator-key',
        ),
        'roommate': OnlineRoomMember(
          uid: 'roommate',
          displayName: 'Ben',
          publicKey: 'roommate-key',
        ),
      },
      verifiedUids: [],
      closed: false,
    );

    expect(room.ownerAfterLeaving('creator'), 'roommate');
    expect(room.ownerAfterLeaving('roommate'), 'creator');
  });

  test('online room updates preserve the active room instance', () async {
    final service = _StreamingFakeOnlineChatService();
    service.usernamesByUid['ben-account'] = 'ben';
    final keyStore = MemoryKeyStore();
    final ana = Profile(
      name: 'Ana',
      username: 'ana',
      accountId: service.currentUid,
    );
    final appState = AppState(
      FakeStore(),
      keyStore: keyStore,
      onlineChatService: service,
    )..currentUser = ana;
    addTearDown(appState.dispose);
    addTearDown(service.roomUpdates.close);

    await appState.startOnlineSync();
    final publicKey = keyStore.keys[service.currentUid]!.publicKeyText;
    service.roomUpdates.add([
      OnlineRoom(
        code: 'ABC234',
        ownerUid: service.currentUid,
        members: {
          service.currentUid: OnlineRoomMember(
            uid: service.currentUid,
            displayName: 'Ana',
            publicKey: publicKey,
          ),
          'ben-account': const OnlineRoomMember(
            uid: 'ben-account',
            displayName: 'Ben',
            publicKey: 'ben-public-key',
          ),
        },
        verifiedUids: const [],
        closed: false,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    final activeRoom = appState.rooms.single;
    expect(
      activeRoom.members
          .singleWhere((member) => member.accountId == 'ben-account')
          .username,
      'ben',
    );

    service.roomUpdates.add([
      OnlineRoom(
        code: 'ABC234',
        ownerUid: service.currentUid,
        members: {
          service.currentUid: OnlineRoomMember(
            uid: service.currentUid,
            displayName: 'Ana',
            publicKey: publicKey,
          ),
        },
        verifiedUids: [service.currentUid],
        closed: false,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(identical(appState.rooms.single, activeRoom), isTrue);
    expect(activeRoom.keyVerifiedUids, contains(service.currentUid));
  });

  test(
    'a joining member sees an accepted guest room and its messages',
    () async {
      final service = _MessagingStreamingFakeOnlineChatService()
        ..currentUid = 'ben-account';
      final keyStore = MemoryKeyStore();
      final ben = Profile(
        name: 'Ben',
        username: 'ben',
        accountId: service.currentUid,
      );
      final appState = AppState(
        FakeStore(),
        keyStore: keyStore,
        onlineChatService: service,
      )..currentUser = ben;
      addTearDown(appState.dispose);
      addTearDown(service.roomUpdates.close);
      addTearDown(service.messageUpdates.close);

      await appState.startOnlineSync();
      final benKeys = keyStore.keys[service.currentUid]!;
      final anaKeys = await MessageCrypto().generateKeys();
      service.roomUpdates.add([
        OnlineRoom(
          code: 'GUEST1',
          ownerUid: 'ana-account',
          members: {
            'ana-account': OnlineRoomMember(
              uid: 'ana-account',
              displayName: 'Ana',
              username: 'ana',
              publicKey: anaKeys.publicKeyText,
            ),
            service.currentUid: OnlineRoomMember(
              uid: service.currentUid,
              displayName: 'Ben',
              username: 'ben',
              publicKey: benKeys.publicKeyText,
            ),
          },
          verifiedUids: const [],
          closed: false,
          guest: true,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(appState.myGuestRooms, hasLength(1));
      final room = appState.myGuestRooms.single;
      final roomKey = await MessageCrypto().deriveRoomKey(
        mine: anaKeys,
        otherPublicKey: benKeys.publicKeyBytes,
        roomId: room.code,
      );
      const messageId = 'guest-message';
      final ciphertext = await MessageCrypto().encrypt(
        key: roomKey,
        text: 'Hello Ben',
        messageId: messageId,
        senderId: 'ana-account',
      );
      service.messageUpdates.add([
        EncryptedChatMessage(
          id: messageId,
          senderUid: 'ana-account',
          ciphertext: ciphertext,
          sentAt: DateTime.now(),
          seenBy: const [],
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(room.messages.single.text, 'Hello Ben');
      expect(appState.onlineError, isNull);
    },
  );

  test(
    'creating an online room does not duplicate its synchronous room update',
    () async {
      final service = _CreatingStreamingFakeOnlineChatService();
      final ana = Profile(
        name: 'Ana',
        username: 'ana',
        accountId: service.currentUid,
      );
      final appState = AppState(
        FakeStore(),
        keyStore: MemoryKeyStore(),
        onlineChatService: service,
      )..currentUser = ana;
      addTearDown(appState.dispose);
      addTearDown(service.roomUpdates.close);

      await appState.startOnlineSync();
      final createdRoom = await appState.createOnlineRoom();

      expect(appState.rooms, hasLength(1));
      expect(identical(appState.rooms.single, createdRoom), isTrue);
    },
  );

  test('creating an online room publishes only the public key', () async {
    final service = _FakeOnlineChatService();
    final keyStore = MemoryKeyStore();
    final ana = Profile(
      name: 'Ana',
      username: 'ana',
      accountId: service.currentUid,
    );
    final appState = AppState(
      FakeStore(),
      keyStore: keyStore,
      onlineChatService: service,
    )..currentUser = ana;
    addTearDown(appState.dispose);

    final room = await appState.createOnlineRoom();

    expect(room, isNotNull);
    expect(room!.online, true);
    expect(room.members, contains(ana));
    expect(service.createdOwner?.uid, service.currentUid);
    expect(service.createdOwner?.username, ana.username);
    expect(service.createdOwner?.publicKey, isNotEmpty);
    expect(
      service.createdOwner?.publicKey,
      isNot(base64Encode(keyStore.keys[service.currentUid]!.privateKeyBytes)),
    );
  });

  test('online messages are encrypted before they reach the service', () async {
    final service = _FakeOnlineChatService();
    final keyStore = MemoryKeyStore();
    final ana = Profile(
      name: 'Ana',
      username: 'ana',
      accountId: service.currentUid,
    );
    final ben = Profile(
      name: 'Ben',
      username: 'online_ben',
      accountId: 'ben-account',
    );
    final appState = AppState(
      FakeStore(),
      keyStore: keyStore,
      onlineChatService: service,
    )..currentUser = ana;
    addTearDown(appState.dispose);

    final anaKeys = (await appState.ensureKeys(ana))!;
    final benKeys = await MessageCrypto().generateKeys();
    final room = ChatRoom.withCode('ABC234')
      ..online = true
      ..members.addAll([ana, ben])
      ..publicKeys[service.currentUid] = anaKeys.publicKeyText
      ..publicKeys[ben.accountId!] = benKeys.publicKeyText
      ..keyVerifiedUids.addAll([service.currentUid, ben.accountId!]);

    final message = await appState.sendMessage(room, 'Hello Ben');
    final key = await MessageCrypto().deriveRoomKey(
      mine: anaKeys,
      otherPublicKey: benKeys.publicKeyBytes,
      roomId: room.code,
    );
    final decrypted = await MessageCrypto().decrypt(
      key: key,
      payload: service.sentCiphertext!,
      messageId: service.sentMessageId!,
      senderId: service.currentUid,
    );

    expect(message?.text, 'Hello Ben');
    expect(service.sentCiphertext, isNot('Hello Ben'));
    expect(decrypted, 'Hello Ben');
  });

  test(
    'reply ids are passed to the service and authenticated by encryption',
    () async {
      final service = _FakeOnlineChatService();
      final keyStore = MemoryKeyStore();
      final ana = Profile(
        name: 'Ana',
        username: 'ana',
        accountId: service.currentUid,
      );
      final ben = Profile(
        name: 'Ben',
        username: 'online_ben',
        accountId: 'ben-account',
      );
      final appState = AppState(
        FakeStore(),
        keyStore: keyStore,
        onlineChatService: service,
      )..currentUser = ana;
      addTearDown(appState.dispose);

      final anaKeys = (await appState.ensureKeys(ana))!;
      final benKeys = await MessageCrypto().generateKeys();
      final room = ChatRoom.withCode('ABC234')
        ..online = true
        ..members.addAll([ana, ben])
        ..publicKeys[service.currentUid] = anaKeys.publicKeyText
        ..publicKeys[ben.accountId!] = benKeys.publicKeyText
        ..keyVerifiedUids.addAll([service.currentUid, ben.accountId!]);
      final original = Message(sender: ben, text: 'Original');

      final message = await appState.sendMessage(
        room,
        'Reply',
        replyTo: original,
      );
      final key = await MessageCrypto().deriveRoomKey(
        mine: anaKeys,
        otherPublicKey: benKeys.publicKeyBytes,
        roomId: room.code,
      );

      expect(message?.replyToId, original.id);
      expect(service.sentReplyToId, original.id);
      await expectLater(
        MessageCrypto().decrypt(
          key: key,
          payload: service.sentCiphertext!,
          messageId: service.sentMessageId!,
          senderId: service.currentUid,
        ),
        throwsA(isA<MessageCryptoException>()),
      );
      expect(
        await MessageCrypto().decrypt(
          key: key,
          payload: service.sentCiphertext!,
          messageId: service.sentMessageId!,
          senderId: service.currentUid,
          replyToId: original.id,
        ),
        'Reply',
      );
    },
  );

  test(
    'online messages require both people to verify the safety code',
    () async {
      final service = _FakeOnlineChatService();
      final keyStore = MemoryKeyStore();
      final ana = Profile(
        name: 'Ana',
        username: 'ana',
        accountId: service.currentUid,
      );
      final ben = Profile(
        name: 'Ben',
        username: 'online_ben',
        accountId: 'ben-account',
      );
      final appState = AppState(
        FakeStore(),
        keyStore: keyStore,
        onlineChatService: service,
      )..currentUser = ana;
      addTearDown(appState.dispose);
      final anaKeys = (await appState.ensureKeys(ana))!;
      final benKeys = await MessageCrypto().generateKeys();
      final room = ChatRoom.withCode('ABC234')
        ..online = true
        ..members.addAll([ana, ben])
        ..publicKeys[service.currentUid] = anaKeys.publicKeyText
        ..publicKeys[ben.accountId!] = benKeys.publicKeyText
        ..keyVerifiedUids.add(service.currentUid);

      await expectLater(
        appState.sendMessage(room, 'Not yet'),
        throwsA(isA<StateError>()),
      );
      expect(service.sentCiphertext, isNull);
    },
  );

  test(
    'marking online messages as seen writes their ids to the service',
    () async {
      final service = _FakeOnlineChatService();
      final ana = Profile(
        name: 'Ana',
        username: 'ana',
        accountId: service.currentUid,
      );
      final ben = Profile(
        name: 'Ben',
        username: 'online_ben',
        accountId: 'ben-account',
      );
      final room = ChatRoom.withCode('ABC234')
        ..online = true
        ..members.addAll([ana, ben])
        ..messages.add(Message(sender: ben, text: 'Hello Ana'));
      final appState = AppState(FakeStore(), onlineChatService: service)
        ..currentUser = ana;
      addTearDown(appState.dispose);

      final changed = await appState.markMessagesAsSeen(room);

      expect(changed, true);
      expect(service.seenMessageIds, [room.messages.single.id]);
    },
  );
}
