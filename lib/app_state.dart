import 'package:flutter/foundation.dart';

import 'dart:async';
import 'dart:io';

import 'accounts/account_service.dart';
import 'action_sound_effects.dart';
import 'crypto/key_store.dart';
import 'crypto/message_crypto.dart';
import 'models/app_settings.dart';
import 'models/chat_room.dart';
import 'models/message.dart';
import 'models/profile.dart';
import 'online/online_chat_service.dart';
import 'photos/photo_service.dart';
import 'photos/photo_store.dart';
import 'storage/app_storage.dart';
import 'updates/update_service.dart';

// The possible outcomes of trying to join a room by its code.
enum JoinOutcome {
  joined,
  roomNotFound,
  roomFull,
  roomClosed,
  alreadyMember,
  inAnotherRoom,
}

// The possible outcomes of linking an online account to the current profile.
enum LinkResult {
  linked,
  notVerified,
  accountUsedByAnotherProfile,
  profileHasAnotherAccount,
}

// AppState holds everything the app knows: profiles, rooms, and who is
// currently using the app.
// Screens listen for changes, then call save() to write them to the file.
class AppState extends ChangeNotifier {
  final ActionSoundEffects? actionSoundEffects;
  final UpdateService? updateService;

  final AppStorage store;

  // The online account system. It is optional for isolated tests and
  // development configurations; onboarding requires it before opening rooms.
  final AccountService? accountService;

  // Profile photos. Both are null when photos are not set up, and then the
  // app simply shows initials.
  final PhotoService? photoService;
  final PhotoStore? photoStore;

  // Where the encryption keys are kept safely. Null when it is not set up.
  final KeyStore? keyStore;
  final OnlineChatService? onlineChatService;

  final MessageCrypto _crypto = MessageCrypto();
  StreamSubscription<List<OnlineRoom>>? _onlineRoomsSubscription;
  final Map<String, StreamSubscription<List<EncryptedChatMessage>>>
  _onlineMessageSubscriptions = {};
  final Map<String, RoomKey> _roomKeys = {};
  StreamSubscription<List<TalkRequest>>? _incomingTalkSubscription;
  StreamSubscription<List<TalkRequest>>? _outgoingTalkSubscription;

  List<TalkRequest> incomingTalkRequests = const [];
  List<TalkRequest> outgoingTalkRequests = const [];
  String? onlineError;
  final List<Profile> profiles = [];
  final List<ChatRoom> rooms = [];
  Profile? _currentUser;

  Profile? get currentUser => _currentUser;

  // Changing the user also changes the app's color, so the whole app is told.
  set currentUser(Profile? profile) {
    _currentUser = profile;
    notifyListeners();
  }

  List<String> loadWarnings = [];

  // The Settings screen choices (theme, text size, animations).
  AppSettings settings = const AppSettings();

  AppState(
    this.store, {
    this.accountService,
    this.photoService,
    this.photoStore,
    this.keyStore,
    this.onlineChatService,
    this.actionSoundEffects,
    this.updateService,
  });

  @override
  void dispose() {
    unawaited(_onlineRoomsSubscription?.cancel());
    unawaited(_incomingTalkSubscription?.cancel());
    unawaited(_outgoingTalkSubscription?.cancel());
    for (final subscription in _onlineMessageSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    unawaited(actionSoundEffects?.dispose());
    super.dispose();
  }

  // True if this profile is linked to the signed-in, email-verified account.
  bool hasVerifiedAccount(Profile profile) {
    final user = accountService?.currentUser;
    return profile.accountId != null &&
        user != null &&
        user.id == profile.accountId &&
        user.emailVerified;
  }

  // Reads the save file. Nobody is selected after loading.
  Future<void> load() async {
    final result = await store.load();
    profiles.addAll(result.profiles);
    rooms.addAll(result.rooms);
    loadWarnings = result.warnings;
    settings = result.settings;
    notifyListeners();

    // An older save file had messages without ids. Save once now, so every
    // message keeps the SAME id from here on (not a new one on each start).
    if (result.upgradedFromOldFormat) {
      await save();
    }
  }

  // Writes everything to the save file. Returns false if saving failed.
  Future<bool> save() => store.save(profiles, rooms, settings: settings);

  // Applies new settings straight away (the app redraws) and saves them.
  Future<bool> changeSettings(AppSettings newSettings) {
    settings = newSettings;
    notifyListeners();
    return save();
  }

  // Adds a new profile, makes it the current user, and saves.
  // The caller should check the name and username with validation.dart first.
  Future<bool> createProfile(
    String name,
    String username, [
    ProfileColor color = ProfileColor.pink,
  ]) async {
    return _createProfile(name, username, color, select: true);
  }

  // Creates a profile without selecting it before onboarding completes.
  Future<bool> createProfileForOnboarding(
    String name,
    String username, [
    ProfileColor color = ProfileColor.pink,
  ]) async {
    return _createProfile(name, username, color, select: false);
  }

  Future<bool> _createProfile(
    String name,
    String username,
    ProfileColor color, {
    required bool select,
  }) async {
    final profile = Profile(
      name: name.trim(),
      username: username.trim(),
      color: color,
    );
    profiles.add(profile);
    if (select) {
      currentUser = profile;
    } else {
      notifyListeners();
    }
    return save();
  }

  // Keeps one profile and removes local data belonging to every other
  // profile. The caller must confirm this destructive migration first.
  Future<bool> keepOnlyProfile(Profile profile) async {
    if (!profiles.contains(profile)) {
      throw ArgumentError.value(profile, 'profile', 'Must be a saved profile');
    }

    final oldProfiles = List<Profile>.of(profiles);
    final oldRooms = List<ChatRoom>.of(rooms);
    final oldMessages = {
      for (final room in rooms) room: List.of(room.messages),
    };
    final removedPhotoNames = profiles
        .where((other) => other.username != profile.username)
        .map((other) => other.photoFileName)
        .whereType<String>()
        .toList();

    profiles.removeWhere((other) => other.username != profile.username);
    rooms.removeWhere(
      (room) =>
          room.members.isEmpty ||
          room.members.any((member) => member.username != profile.username),
    );
    for (final room in rooms) {
      room.messages.removeWhere(
        (message) => message.sender.username != profile.username,
      );
    }

    final saved = await save();
    if (!saved) {
      profiles
        ..clear()
        ..addAll(oldProfiles);
      rooms
        ..clear()
        ..addAll(oldRooms);
      for (final room in oldRooms) {
        room.messages
          ..clear()
          ..addAll(oldMessages[room]!);
      }
      return false;
    }

    if (_currentUser != null && !profiles.contains(_currentUser)) {
      currentUser = null;
    } else {
      notifyListeners();
    }
    for (final name in removedPhotoNames) {
      await photoStore?.delete(name);
    }
    return true;
  }

  // Changes the current user's display name (the username never changes).
  // The caller should check the name with validateName first.
  void renameCurrentUser(String newName) {
    currentUser!.name = newName.trim();
    notifyListeners();
  }

  // The photo file of this person, or null if they have none (or it is gone).
  File? photoFileOf(Profile? profile) {
    final store = photoStore;
    final name = profile?.photoFileName;
    if (store == null || name == null) {
      return null;
    }
    final file = store.fileFor(name);
    return file.existsSync() ? file : null;
  }

  // Copies the picked picture into the app's photos folder, makes it this
  // person's photo (deleting their old one), and saves.
  // Returns false if the picture could not be stored or saved.
  Future<bool> setProfilePhoto(Profile profile, File picked) async {
    final store = photoStore;
    if (store == null) {
      return false;
    }
    try {
      profile.photoFileName = await store.saveCopy(
        picked,
        profile.username,
        replacing: profile.photoFileName,
      );
    } on FileSystemException {
      return false;
    }
    notifyListeners();
    return save();
  }

  Future<bool> removeProfilePhoto(Profile profile) async {
    final name = profile.photoFileName;
    if (name == null) {
      return true;
    }
    profile.photoFileName = null;
    await photoStore?.delete(name);
    notifyListeners();
    return save();
  }

  // Links a signed-in, email-verified online account to the current profile.
  // Only changes memory: the caller saves afterwards.
  LinkResult linkAccount(AccountUser user, {Profile? profile}) {
    final target = profile ?? currentUser!;
    if (!user.emailVerified) {
      return LinkResult.notVerified;
    }
    if (target.accountId == user.id) {
      return LinkResult.linked; // already linked to this very account
    }
    if (target.accountId != null) {
      return LinkResult.profileHasAnotherAccount;
    }
    if (profiles.any(
      (other) => other != target && other.accountId == user.id,
    )) {
      return LinkResult.accountUsedByAnotherProfile;
    }
    target.accountId = user.id;
    notifyListeners();
    return LinkResult.linked;
  }

  // The encryption keys of this profile's online account, or null if there are
  // none on this phone yet (or the profile is not linked, or no key storage).
  Future<PersonKeys?> loadKeys(Profile profile) async {
    final accountId = profile.accountId;
    final store = keyStore;
    if (accountId == null || store == null) {
      return null;
    }
    return store.load(accountId);
  }

  // Returns the keys of this profile's account, making and storing new ones
  // if there are none yet. Returns null if that is not possible: the profile
  // is not linked, there is no key storage, or storing the keys failed.
  Future<PersonKeys?> ensureKeys(Profile profile) async {
    final accountId = profile.accountId;
    final store = keyStore;
    if (accountId == null || store == null) {
      return null;
    }
    final existing = await store.load(accountId);
    if (existing != null) {
      return existing;
    }
    try {
      final keys = await _crypto.generateKeys();
      await store.save(accountId, keys);
      return keys;
    } catch (_) {
      return null;
    }
  }

  Future<void> startOnlineSync() async {
    final service = onlineChatService;
    final profile = currentUser;
    if (service == null || profile == null) {
      return;
    }
    final uid = service.currentUid;
    if (profile.accountId != uid) {
      throw StateError('The selected profile is not linked to this account.');
    }
    final keys = await ensureKeys(profile);
    if (keys == null) {
      throw StateError('Could not access this account’s encryption keys.');
    }

    await _onlineRoomsSubscription?.cancel();
    _onlineRoomsSubscription = service.watchMyRooms().listen(
      (onlineRooms) {
        _replaceOnlineRooms(onlineRooms).then<void>(
          (_) {
            onlineError = null;
            notifyListeners();
          },
          onError: (Object error, StackTrace stackTrace) {
            onlineError = 'Online rooms could not be synchronized: $error';
            notifyListeners();
          },
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        onlineError = 'Online rooms could not be synchronized: $error';
        notifyListeners();
      },
    );

    await _incomingTalkSubscription?.cancel();
    _incomingTalkSubscription = service.watchIncomingTalkRequests().listen(
      (requests) {
        incomingTalkRequests = requests;
        notifyListeners();
      },
      onError: (Object error, StackTrace stackTrace) {
        onlineError = 'Talk requests could not be loaded: $error';
        notifyListeners();
      },
    );
    await _outgoingTalkSubscription?.cancel();
    _outgoingTalkSubscription = service.watchOutgoingTalkRequests().listen(
      (requests) {
        outgoingTalkRequests = requests;
        notifyListeners();
      },
      onError: (Object error, StackTrace stackTrace) {
        onlineError = 'Talk requests could not be loaded: $error';
        notifyListeners();
      },
    );
  }

  Future<void> _replaceOnlineRooms(List<OnlineRoom> onlineRooms) async {
    final seenRoomCodes = <String>{};
    rooms.removeWhere((room) => room.online && !seenRoomCodes.add(room.code));

    final incomingCodes = onlineRooms.map((room) => room.code).toSet();
    final staleRooms = rooms
        .where((room) => room.online && !incomingCodes.contains(room.code))
        .toList();
    for (final room in staleRooms) {
      rooms.remove(room);
      _roomKeys.remove(room.code);
      await _onlineMessageSubscriptions.remove(room.code)?.cancel();
    }

    final profileByUid = <String, Profile>{};
    for (final onlineRoom in onlineRooms) {
      final previousIndex = rooms.indexWhere(
        (existing) => existing.online && existing.code == onlineRoom.code,
      );
      final room = previousIndex == -1
          ? ChatRoom.withCode(onlineRoom.code)
          : rooms[previousIndex];
      final previousMembers = {
        for (final member in room.members)
          if (member.accountId != null) member.accountId!: member,
      };
      room
        ..online = true
        ..ownerUid = onlineRoom.ownerUid
        ..guest = onlineRoom.guest
        ..closed = onlineRoom.closed;
      room.members.clear();
      room.publicKeys.clear();
      room.keyVerifiedUids
        ..clear()
        ..addAll(onlineRoom.verifiedUids);
      for (final entry in onlineRoom.members.entries) {
        final uid = entry.key;
        final member = entry.value;
        final profile = uid == currentUser?.accountId
            ? currentUser!
            : profileByUid.putIfAbsent(
                uid,
                () =>
                    previousMembers[uid] ??
                    Profile(
                      name: member.displayName,
                      username: 'online_$uid',
                      accountId: uid,
                    ),
              );
        room.members.add(profile);
        room.publicKeys[uid] = member.publicKey;
      }

      if (previousIndex == -1) {
        rooms.add(room);
      }
      if (!_onlineMessageSubscriptions.containsKey(room.code)) {
        _watchOnlineMessages(room);
      }
    }
    notifyListeners();
  }

  void _watchOnlineMessages(ChatRoom room) {
    unawaited(_onlineMessageSubscriptions.remove(room.code)?.cancel());
    _onlineMessageSubscriptions[room.code] = onlineChatService!
        .watchMessages(room.code)
        .listen(
          (onlineMessages) {
            _replaceOnlineMessages(room, onlineMessages).then<void>(
              (_) {
                onlineError = null;
                notifyListeners();
              },
              onError: (Object error, StackTrace stackTrace) {
                onlineError =
                    'Messages could not be decrypted or loaded: $error';
                notifyListeners();
              },
            );
          },
          onError: (Object error, StackTrace stackTrace) {
            onlineError = 'Messages could not be loaded: $error';
            notifyListeners();
          },
        );
  }

  Future<void> _replaceOnlineMessages(
    ChatRoom room,
    List<EncryptedChatMessage> onlineMessages,
  ) async {
    if (onlineMessages.isEmpty) {
      room.messages.clear();
      return;
    }
    final key = await _roomKeyFor(room);
    if (key == null) {
      throw StateError('The other room member’s public key is not available.');
    }
    final uid = onlineChatService!.currentUid;
    final messages = <Message>[];
    for (final onlineMessage in onlineMessages) {
      final sender = room.members
          .where((member) => member.accountId == onlineMessage.senderUid)
          .firstOrNull;
      if (sender == null) {
        throw StateError('A message has an unknown sender.');
      }
      final text = await _crypto.decrypt(
        key: key,
        payload: onlineMessage.ciphertext,
        messageId: onlineMessage.id,
        senderId: onlineMessage.senderUid,
        replyToId: onlineMessage.replyToId,
      );
      messages.add(
        Message(
          sender: sender,
          text: text,
          timestamp: onlineMessage.sentAt,
          seen: onlineMessage.senderUid == uid
              ? onlineMessage.seenBy.any((seenUid) => seenUid != uid)
              : onlineMessage.seenBy.contains(uid),
          id: onlineMessage.id,
          replyToId: onlineMessage.replyToId,
          reactions: onlineMessage.reactions,
        ),
      );
    }
    room.messages
      ..clear()
      ..addAll(messages);
  }

  Future<RoomKey?> _roomKeyFor(ChatRoom room) async {
    final cached = _roomKeys[room.code];
    if (cached != null) {
      return cached;
    }
    final uid = onlineChatService!.currentUid;
    final user = currentUser;
    final other = room.members
        .where((member) => member.accountId != uid)
        .firstOrNull;
    if (user == null || other?.accountId == null) {
      return null;
    }
    final keys = await ensureKeys(user);
    final otherPublicKey = room.publicKeys[other!.accountId];
    if (keys == null || otherPublicKey == null) {
      return null;
    }
    final roomKey = await _crypto.deriveRoomKey(
      mine: keys,
      otherPublicKey: PersonKeys.publicKeyFromText(otherPublicKey),
      roomId: room.code,
    );
    _roomKeys[room.code] = roomKey;
    return roomKey;
  }

  Future<ChatRoom?> createOnlineRoom() async {
    final service = onlineChatService;
    final profile = currentUser;
    if (service == null ||
        profile == null ||
        rooms.any(
          (room) => room.online && !room.guest && room.hasMember(profile),
        )) {
      return null;
    }
    final uid = service.currentUid;
    if (profile.accountId != uid) {
      throw StateError('The selected profile is not linked to this account.');
    }
    final keys = await ensureKeys(profile);
    if (keys == null) {
      throw StateError('Could not access this account’s encryption keys.');
    }
    var room = ChatRoom();
    while (findRoom(room.code) != null) {
      room = ChatRoom();
    }
    await service.createRoom(
      code: room.code,
      owner: OnlineRoomMember(
        uid: uid,
        displayName: profile.name,
        publicKey: keys.publicKeyText,
      ),
    );
    final synchronizedRoom = rooms
        .where((existing) => existing.online && existing.code == room.code)
        .firstOrNull;
    if (synchronizedRoom != null) {
      return synchronizedRoom;
    }
    room
      ..online = true
      ..ownerUid = uid
      ..publicKeys[uid] = keys.publicKeyText
      ..members.add(profile);
    rooms.add(room);
    notifyListeners();
    return room;
  }

  Future<void> requestToJoinOnlineRoom(String code) async {
    final service = onlineChatService;
    final profile = currentUser;
    if (service == null || profile == null) {
      throw StateError('Online rooms are not available.');
    }
    if (rooms.any(
      (room) => room.online && !room.guest && room.hasMember(profile),
    )) {
      throw StateError('Leave your current room before joining another.');
    }
    final uid = service.currentUid;
    if (profile.accountId != uid) {
      throw StateError('The selected profile is not linked to this account.');
    }
    final keys = await ensureKeys(profile);
    if (keys == null) {
      throw StateError('Could not access this account’s encryption keys.');
    }
    await service.requestToJoin(
      code: code.trim().toUpperCase(),
      requester: OnlineRoomMember(
        uid: uid,
        displayName: profile.name,
        publicKey: keys.publicKeyText,
      ),
    );
  }

  Stream<List<OnlineJoinRequest>> watchJoinRequests(String code) =>
      onlineChatService!.watchJoinRequests(code);

  Future<void> decideJoinRequest(
    String code,
    String requesterUid, {
    required bool approve,
  }) => onlineChatService!.decideJoinRequest(
    code: code,
    requesterUid: requesterUid,
    approve: approve,
  );

  Future<void> sendTalkRequest({
    required String toUid,
    required String toUsername,
  }) async {
    final service = onlineChatService;
    final profile = currentUser;
    if (service == null || profile == null) {
      throw StateError('Online chat is not available.');
    }
    final uid = service.currentUid;
    if (profile.accountId != uid) {
      throw StateError('The selected profile is not linked to this account.');
    }
    if (toUid == uid) {
      throw StateError('You cannot send a request to yourself.');
    }
    final alreadyChatting = rooms.any(
      (room) =>
          room.online &&
          room.guest &&
          !room.closed &&
          room.members.any((member) => member.accountId == toUid),
    );
    if (alreadyChatting) {
      throw StateError('You already have a guest chat with @$toUsername.');
    }
    final keys = await ensureKeys(profile);
    if (keys == null) {
      throw StateError('Could not access this account’s encryption keys.');
    }
    await service.sendTalkRequest(
      toUid: toUid,
      toUsername: toUsername,
      sender: OnlineRoomMember(
        uid: uid,
        displayName: profile.name,
        publicKey: keys.publicKeyText,
      ),
    );
  }

  Future<void> respondToTalkRequest(
    TalkRequest request, {
    required bool accept,
  }) async {
    final service = onlineChatService;
    final profile = currentUser;
    if (service == null || profile == null) {
      throw StateError('Online chat is not available.');
    }
    if (!accept) {
      await service.declineTalkRequest(request);
      return;
    }
    final uid = service.currentUid;
    if (profile.accountId != uid) {
      throw StateError('The selected profile is not linked to this account.');
    }
    final keys = await ensureKeys(profile);
    if (keys == null) {
      throw StateError('Could not access this account’s encryption keys.');
    }
    var code = ChatRoom().code;
    while (findRoom(code) != null) {
      code = ChatRoom().code;
    }
    await service.acceptTalkRequest(
      request: request,
      roomCode: code,
      me: OnlineRoomMember(
        uid: uid,
        displayName: profile.name,
        publicKey: keys.publicKeyText,
      ),
    );
  }

  Future<void> leaveOnlineRoom(ChatRoom room) async {
    // Stop listening first: once we leave, the rules no longer let us read
    // this room's messages, and the listener would report permission-denied.
    await _onlineMessageSubscriptions.remove(room.code)?.cancel();
    try {
      await onlineChatService!.leaveRoom(room.code);
    } catch (_) {
      _watchOnlineMessages(room); // leaving failed, so listen again
      rethrow;
    }
    onlineError = null;
    notifyListeners();
  }

  bool isRoomKeyVerified(ChatRoom room) =>
      room.online &&
      room.members.length == 2 &&
      room.members.every(
        (member) =>
            member.accountId != null &&
            room.keyVerifiedUids.contains(member.accountId),
      );

  Future<void> verifyRoomKey(ChatRoom room) async {
    await onlineChatService!.markKeyVerified(room.code);
    room.keyVerifiedUids.add(onlineChatService!.currentUid);
    notifyListeners();
  }

  Future<String?> roomSafetyCode(ChatRoom room) async {
    final user = currentUser;
    final uid = onlineChatService!.currentUid;
    final keys = user == null ? null : await ensureKeys(user);
    final other = room.members
        .where((member) => member.accountId != uid)
        .firstOrNull;
    final otherPublicKey = other?.accountId == null
        ? null
        : room.publicKeys[other!.accountId];
    if (keys == null || otherPublicKey == null) {
      return null;
    }
    return _crypto.safetyCode(
      myPublicKey: keys.publicKeyBytes,
      otherPublicKey: PersonKeys.publicKeyFromText(otherPublicKey),
    );
  }

  Future<Message?> sendMessage(
    ChatRoom room,
    String text, {
    Message? replyTo,
  }) async {
    if (!room.online) {
      return addMessage(room, text);
    }
    if (room.closed) {
      throw StateError('This room is closed.');
    }
    if (!isRoomKeyVerified(room)) {
      throw StateError('Compare and verify both safety codes before chatting.');
    }
    final uid = onlineChatService!.currentUid;
    final key = await _roomKeyFor(room);
    if (key == null) {
      throw StateError('The other room member’s public key is not available.');
    }
    final message = Message(
      sender: currentUser!,
      text: text,
      replyToId: replyTo?.id,
    );
    final ciphertext = await _crypto.encrypt(
      key: key,
      text: text,
      messageId: message.id,
      senderId: uid,
      replyToId: message.replyToId,
    );
    await onlineChatService!.sendMessage(
      code: room.code,
      messageId: message.id,
      ciphertext: ciphertext,
      replyToId: message.replyToId,
    );
    return message;
  }

  // Reacts with an emoji. Tapping the same emoji again removes it.
  Future<void> reactToMessage(
    ChatRoom room,
    Message message,
    String emoji,
  ) async {
    if (!room.online || room.closed) {
      return;
    }
    final uid = onlineChatService!.currentUid;
    final remove = message.reactions[uid] == emoji;
    await onlineChatService!.setReaction(
      code: room.code,
      messageId: message.id,
      emoji: remove ? null : emoji,
    );
  }

  Future<bool> markMessagesAsSeen(ChatRoom room) async {
    if (!room.online) {
      return markRoomMessagesAsSeen(room);
    }
    final uid = onlineChatService!.currentUid;
    final unread = room.messages
        .where((message) => message.sender.accountId != uid && !message.seen)
        .toList();
    for (final message in unread) {
      await onlineChatService!.markSeen(code: room.code, messageId: message.id);
    }
    return unread.isNotEmpty;
  }

  // Removes the link between the current profile and its online account.
  // The online account itself is not touched. Only changes memory: the caller
  // saves afterwards.
  void unlinkAccount({Profile? profile}) {
    (profile ?? currentUser!).accountId = null;
    notifyListeners();
  }

  // ---------- Rooms ----------

  // The roommate rooms the current user is a member of.
  List<ChatRoom> get myRooms {
    final user = currentUser;
    if (user == null) {
      return [];
    }
    return rooms.where((room) => !room.guest && room.hasMember(user)).toList();
  }

  List<ChatRoom> get myGuestRooms {
    final user = currentUser;
    if (user == null) {
      return [];
    }
    return rooms.where((room) => room.guest && room.hasMember(user)).toList();
  }

  ChatRoom? findRoom(String code) {
    for (final room in rooms) {
      if (room.code == code) {
        return room;
      }
    }
    return null;
  }

  // Creates a room with a code nobody else is using, and puts the
  // current user in it.
  // Each person can be in only ONE room at a time, so this returns null if
  // the current user already has a room (they must leave it first).
  ChatRoom? createRoom() {
    if (myRooms.isNotEmpty) {
      return null;
    }
    var room = ChatRoom();
    while (findRoom(room.code) != null) {
      room = ChatRoom(); // that code is already used, so pick another
    }
    room.addMember(currentUser!);
    rooms.add(room);
    notifyListeners();
    return room;
  }

  Message? addMessage(ChatRoom room, String text) {
    final user = currentUser;
    if (user == null) {
      return null;
    }
    final message = room.addMessage(user, text);
    if (message != null) {
      notifyListeners();
    }
    return message;
  }

  bool markRoomMessagesAsSeen(ChatRoom room) {
    final user = currentUser;
    if (user == null || room.countUnread(user) == 0) {
      return false;
    }
    room.markMessagesAsSeen(user);
    notifyListeners();
    return true;
  }

  // The caller should check the code format with validateRoomCode first.
  JoinOutcome joinRoom(String code) {
    final room = findRoom(code.trim().toUpperCase());
    if (room == null) {
      return JoinOutcome.roomNotFound;
    }
    // One room per person: someone who is already in a different room must
    // leave it first. (Being in THIS room is reported as "already a member".)
    if (!room.hasMember(currentUser!) && myRooms.isNotEmpty) {
      return JoinOutcome.inAnotherRoom;
    }
    final outcome = switch (room.addMember(currentUser!)) {
      JoinResult.joined => JoinOutcome.joined,
      JoinResult.roomFull => JoinOutcome.roomFull,
      JoinResult.roomClosed => JoinOutcome.roomClosed,
      JoinResult.alreadyMember => JoinOutcome.alreadyMember,
    };
    if (outcome == JoinOutcome.joined) {
      notifyListeners();
    }
    return outcome;
  }

  // Removes the current user from the room. Their messages stay for their
  // other member. If nobody is left, the room is deleted.
  // Returns true if the room was deleted.
  bool leaveRoom(ChatRoom room) {
    if (!room.removeMember(currentUser!)) {
      return false;
    }
    if (room.isEmpty) {
      rooms.remove(room);
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }
}
