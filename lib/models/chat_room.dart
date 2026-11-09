import 'dart:math';

import 'message.dart';
import 'profile.dart';

enum JoinResult { joined, roomFull, roomClosed, alreadyMember }

class ChatRoom {
  static const int maxMessageLength = 500;
  static const String _codeCharacters = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static final Random _random = Random.secure();

  final String code;
  final List<Profile> members = [];
  final List<Message> messages = [];
  final Map<String, String> publicKeys = {};
  final Set<String> keyVerifiedUids = {};
  bool online = false;
  String? ownerUid;
  bool closed = false;

  ChatRoom() : code = _generateCode();

  ChatRoom.withCode(this.code);

  static String _generateCode() {
    return List.generate(
      6,
      (_) => _codeCharacters[_random.nextInt(_codeCharacters.length)],
    ).join();
  }

  bool get isEmpty => members.isEmpty;

  bool hasMember(Profile profile) =>
      members.any((member) => member.username == profile.username);

  JoinResult addMember(Profile profile) {
    if (hasMember(profile)) {
      return JoinResult.alreadyMember;
    }
    if (closed) {
      return JoinResult.roomClosed;
    }
    if (members.length >= 2) {
      return JoinResult.roomFull;
    }

    members.add(profile);
    return JoinResult.joined;
  }

  bool removeMember(Profile profile) {
    final index = members.indexWhere(
      (member) => member.username == profile.username,
    );
    if (index == -1) {
      return false;
    }

    members.removeAt(index);
    if (members.isNotEmpty) {
      closed = true;
    }
    return true;
  }

  Profile? otherMemberOf(Profile profile) {
    if (!hasMember(profile)) {
      return null;
    }
    for (final member in members) {
      if (member.username != profile.username) {
        return member;
      }
    }
    return null;
  }

  Message? addMessage(Profile sender, String text) {
    if (!hasMember(sender) || text.length > maxMessageLength) {
      return null;
    }

    final message = Message(sender: sender, text: text);
    messages.add(message);
    return message;
  }

  void markMessagesAsSeen(Profile reader) {
    for (final message in messages) {
      if (message.sender.username != reader.username) {
        message.markAsSeen();
      }
    }
  }

  int countUnread(Profile reader) => messages
      .where(
        (message) =>
            message.sender.username != reader.username && !message.seen,
      )
      .length;
}
