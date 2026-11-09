import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../crypto/message_crypto.dart';

class OnlineRoomMember {
  final String uid;
  final String displayName;
  final String publicKey;

  const OnlineRoomMember({
    required this.uid,
    required this.displayName,
    required this.publicKey,
  });

  Map<String, Object> toMap() => {
    'displayName': displayName,
    'publicKey': publicKey,
  };

  factory OnlineRoomMember.fromMap(String uid, Object? value) {
    if (value is! Map ||
        value['displayName'] is! String ||
        value['publicKey'] is! String) {
      throw const FormatException('Invalid online room member.');
    }
    return OnlineRoomMember(
      uid: uid,
      displayName: value['displayName'] as String,
      publicKey: value['publicKey'] as String,
    );
  }
}

class OnlineRoom {
  final String code;
  final String ownerUid;
  final Map<String, OnlineRoomMember> members;
  final List<String> verifiedUids;
  final bool closed;

  const OnlineRoom({
    required this.code,
    required this.ownerUid,
    required this.members,
    required this.verifiedUids,
    required this.closed,
  });

  String ownerAfterLeaving(String leavingUid) {
    if (ownerUid != leavingUid) {
      return ownerUid;
    }
    return members.keys.firstWhere(
      (memberUid) => memberUid != leavingUid,
      orElse: () => ownerUid,
    );
  }

  factory OnlineRoom.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null ||
        data['ownerUid'] is! String ||
        data['members'] is! Map ||
        data['verifiedUids'] is! List ||
        (data['verifiedUids'] as List).any((uid) => uid is! String) ||
        data['closed'] is! bool) {
      throw const FormatException('Invalid online room document.');
    }
    final membersData = data['members'] as Map;
    if (membersData.keys.any((uid) => uid is! String)) {
      throw const FormatException('Invalid online room member id.');
    }
    final members = <String, OnlineRoomMember>{
      for (final entry in membersData.entries)
        entry.key as String: OnlineRoomMember.fromMap(
          entry.key as String,
          entry.value,
        ),
    };
    return OnlineRoom(
      code: snapshot.id,
      ownerUid: data['ownerUid'] as String,
      members: members,
      verifiedUids: List<String>.unmodifiable(
        (data['verifiedUids'] as List).cast<String>(),
      ),
      closed: data['closed'] as bool,
    );
  }
}

class OnlineJoinRequest {
  final String requesterUid;
  final String displayName;
  final String publicKey;

  const OnlineJoinRequest({
    required this.requesterUid,
    required this.displayName,
    required this.publicKey,
  });

  factory OnlineJoinRequest.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null ||
        data['requesterUid'] is! String ||
        data['displayName'] is! String ||
        data['publicKey'] is! String) {
      throw const FormatException('Invalid room join request.');
    }
    return OnlineJoinRequest(
      requesterUid: data['requesterUid'] as String,
      displayName: data['displayName'] as String,
      publicKey: data['publicKey'] as String,
    );
  }
}

class EncryptedChatMessage {
  final String id;
  final String senderUid;
  final String ciphertext;
  final DateTime sentAt;
  final List<String> seenBy;
  final String? replyToId;
  final Map<String, String> reactions;

  const EncryptedChatMessage({
    required this.id,
    required this.senderUid,
    required this.ciphertext,
    required this.sentAt,
    required this.seenBy,
    this.replyToId,
    this.reactions = const {},
  });

  factory EncryptedChatMessage.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    final replyToId = data?['replyToId'];
    final reactionsData = data?['reactions'];
    if (data == null ||
        data['senderUid'] is! String ||
        data['ciphertext'] is! String ||
        data['sentAt'] is! Timestamp ||
        data['seenBy'] is! List ||
        (data['seenBy'] as List).any((uid) => uid is! String) ||
        (replyToId != null && replyToId is! String) ||
        (reactionsData != null &&
            (reactionsData is! Map ||
                reactionsData.entries.any(
                  (entry) => entry.key is! String || entry.value is! String,
                )))) {
      throw const FormatException('Invalid encrypted message document.');
    }
    return EncryptedChatMessage(
      replyToId: replyToId as String?,
      reactions: {
        ...?((reactionsData as Map?)?.map(
          (key, value) => MapEntry(key as String, value as String),
        )),
      },
      id: snapshot.id,
      senderUid: data['senderUid'] as String,
      ciphertext: data['ciphertext'] as String,
      sentAt: (data['sentAt'] as Timestamp).toDate(),
      seenBy: List<String>.unmodifiable(
        (data['seenBy'] as List).cast<String>(),
      ),
    );
  }
}

abstract interface class OnlineChatService {
  String get currentUid;

  Future<void> createRoom({
    required String code,
    required OnlineRoomMember owner,
  });

  Future<void> requestToJoin({
    required String code,
    required OnlineRoomMember requester,
  });

  Future<void> decideJoinRequest({
    required String code,
    required String requesterUid,
    required bool approve,
  });

  Future<void> leaveRoom(String code);

  Future<void> markKeyVerified(String code);

  Stream<List<OnlineRoom>> watchMyRooms();

  Stream<List<OnlineJoinRequest>> watchJoinRequests(String code);

  Stream<List<EncryptedChatMessage>> watchMessages(String code);

  Future<void> sendMessage({
    required String code,
    required String messageId,
    required String ciphertext,
    String? replyToId,
  });

  Future<void> setReaction({
    required String code,
    required String messageId,
    String? emoji, // null removes your reaction
  });

  Future<void> markSeen({required String code, required String messageId});
}

class FirestoreOnlineChatService implements OnlineChatService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  FirestoreOnlineChatService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  @override
  String get currentUid {
    final user = _auth.currentUser;
    if (user == null || !user.emailVerified) {
      throw StateError('A verified signed-in account is required.');
    }
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _rooms =>
      _firestore.collection('rooms');

  DocumentReference<Map<String, dynamic>> _room(String code) =>
      _rooms.doc(code);

  @override
  Future<void> createRoom({
    required String code,
    required OnlineRoomMember owner,
  }) async {
    final uid = currentUid;
    if (owner.uid != uid) {
      throw StateError('The room owner must be the signed-in account.');
    }
    await _room(code).set({
      'ownerUid': uid,
      'memberUids': [uid],
      'members': {uid: owner.toMap()},
      'verifiedUids': <String>[],
      'closed': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> requestToJoin({
    required String code,
    required OnlineRoomMember requester,
  }) async {
    final uid = currentUid;
    if (requester.uid != uid) {
      throw StateError('A join request must belong to the signed-in account.');
    }
    final requestRef = _room(code).collection('joinRequests').doc(uid);
    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(requestRef);
      if (existing.exists) {
        if (existing.data()?['status'] != 'rejected') {
          throw StateError('A join request already exists for this room.');
        }
        transaction.update(requestRef, {
          'status': 'pending',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }
      transaction.set(requestRef, {
        'requesterUid': uid,
        'displayName': requester.displayName,
        'publicKey': requester.publicKey,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<void> decideJoinRequest({
    required String code,
    required String requesterUid,
    required bool approve,
  }) async {
    final uid = currentUid;
    await _firestore.runTransaction((transaction) async {
      final roomRef = _room(code);
      final requestRef = roomRef.collection('joinRequests').doc(requesterUid);
      final roomSnapshot = await transaction.get(roomRef);
      final requestSnapshot = await transaction.get(requestRef);
      if (!roomSnapshot.exists || !requestSnapshot.exists) {
        throw StateError('The room or join request no longer exists.');
      }
      final room = OnlineRoom.fromSnapshot(roomSnapshot);
      final request = OnlineJoinRequest.fromSnapshot(requestSnapshot);
      final status = requestSnapshot.data()?['status'];
      if (room.ownerUid != uid || room.closed || status != 'pending') {
        throw StateError('This join request cannot be approved.');
      }
      if (approve) {
        PersonKeys.publicKeyFromText(request.publicKey);
        if (room.members.length >= 2 ||
            room.members.containsKey(request.requesterUid)) {
          throw StateError('The room is full or the requester already joined.');
        }
        transaction.update(roomRef, {
          'memberUids': [...room.members.keys, request.requesterUid],
          'members': {
            ...{
              for (final entry in room.members.entries)
                entry.key: entry.value.toMap(),
            },
            request.requesterUid: {
              'displayName': request.displayName,
              'publicKey': request.publicKey,
            },
          },
        });
      }
      transaction.update(requestRef, {
        'status': approve ? 'approved' : 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<void> leaveRoom(String code) async {
    final uid = currentUid;
    await _firestore.runTransaction((transaction) async {
      final roomRef = _room(code);
      final snapshot = await transaction.get(roomRef);
      if (!snapshot.exists) {
        return;
      }
      final room = OnlineRoom.fromSnapshot(snapshot);
      if (!room.members.containsKey(uid)) {
        return;
      }
      final remaining = Map<String, OnlineRoomMember>.of(room.members)
        ..remove(uid);
      transaction.update(roomRef, {
        'ownerUid': room.ownerAfterLeaving(uid),
        'memberUids': remaining.keys.toList(),
        'members': {
          for (final entry in remaining.entries) entry.key: entry.value.toMap(),
        },
        'closed': true,
      });
    });
  }

  @override
  Future<void> markKeyVerified(String code) async {
    final uid = currentUid;
    await _room(code).update({
      'verifiedUids': FieldValue.arrayUnion([uid]),
    });
  }

  @override
  Stream<List<OnlineRoom>> watchMyRooms() {
    final uid = currentUid;
    return _rooms
        .where('memberUids', arrayContains: uid)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(OnlineRoom.fromSnapshot)
              .toList(growable: false),
        );
  }

  @override
  Stream<List<OnlineJoinRequest>> watchJoinRequests(String code) {
    final uid = currentUid;
    return _room(code)
        .collection('joinRequests')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(OnlineJoinRequest.fromSnapshot)
              .where((request) => request.requesterUid != uid)
              .toList(growable: false),
        );
  }

  @override
  Stream<List<EncryptedChatMessage>> watchMessages(String code) {
    currentUid;
    return _room(code)
        .collection('messages')
        .orderBy('sentAt')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(EncryptedChatMessage.fromSnapshot)
              .toList(growable: false),
        );
  }

  @override
  Future<void> sendMessage({
    required String code,
    required String messageId,
    required String ciphertext,
    String? replyToId,
  }) async {
    final uid = currentUid;
    await _room(code).collection('messages').doc(messageId).set({
      'senderUid': uid,
      'ciphertext': ciphertext,
      'sentAt': FieldValue.serverTimestamp(),
      'seenBy': [uid],
      'replyToId': ?replyToId,
    });
  }

  @override
  Future<void> setReaction({
    required String code,
    required String messageId,
    String? emoji,
  }) async {
    final uid = currentUid;
    await _room(code).collection('messages').doc(messageId).update({
      'reactions.$uid': emoji ?? FieldValue.delete(),
    });
  }

  @override
  Future<void> markSeen({
    required String code,
    required String messageId,
  }) async {
    final uid = currentUid;
    await _room(code).collection('messages').doc(messageId).update({
      'seenBy': FieldValue.arrayUnion([uid]),
    });
  }
}
