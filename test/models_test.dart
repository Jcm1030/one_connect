import 'package:flutter_test/flutter_test.dart';
import 'package:oneconnect/models/chat_room.dart';
import 'package:oneconnect/models/message.dart';
import 'package:oneconnect/models/profile.dart';

void main() {
  group('Profile', () {
    test('toString shows name and username', () {
      final ana = Profile(name: 'Ana', username: 'ana');
      expect(ana.toString(), 'Ana (@ana)');
    });

    test('a new profile is pink unless another color is chosen', () {
      expect(Profile(name: 'Ana', username: 'ana').color, ProfileColor.pink);
      expect(
        Profile(name: 'Ben', username: 'ben', color: ProfileColor.teal).color,
        ProfileColor.teal,
      );
    });

    test('a profile has no online account until one is linked', () {
      final ana = Profile(name: 'Ana', username: 'ana');
      expect(ana.accountId, null);
      ana.accountId = 'abc123';
      expect(ana.accountId, 'abc123');
    });

    test('the name can be changed', () {
      final ana = Profile(name: 'Ana', username: 'ana');
      ana.name = 'Anna';
      expect(ana.name, 'Anna');
      expect(ana.username, 'ana');
    });
  });

  group('Message', () {
    test('a new message is not seen and has the current time', () {
      final ana = Profile(name: 'Ana', username: 'ana');
      final message = Message(sender: ana, text: 'hi');
      expect(message.seen, false);
      expect(DateTime.now().difference(message.timestamp).inSeconds < 5, true);
    });

    test('every message gets its own 32-character id', () {
      final ana = Profile(name: 'Ana', username: 'ana');
      final first = Message(sender: ana, text: 'one');
      final second = Message(sender: ana, text: 'two');

      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(first.id), true);
      expect(first.id == second.id, false);
    });

    test('a restored message keeps the id it is given', () {
      final ana = Profile(name: 'Ana', username: 'ana');
      final id = 'a' * 32;
      expect(Message(sender: ana, text: 'hi', id: id).id, id);
    });

    test('a restored message keeps its timestamp and seen status', () {
      final ana = Profile(name: 'Ana', username: 'ana');
      final time = DateTime(2026, 10, 26, 9, 30);
      final message = Message(
        sender: ana,
        text: 'hi',
        timestamp: time,
        seen: true,
      );
      expect(message.timestamp, time);
      expect(message.seen, true);
    });
  });

  group('ChatRoom', () {
    late Profile ana;
    late Profile ben;
    late ChatRoom room;

    setUp(() {
      ana = Profile(name: 'Ana', username: 'ana');
      ben = Profile(name: 'Ben', username: 'ben');
      room = ChatRoom();
    });

    test('new rooms get a 6-character code from the allowed characters', () {
      final pattern = RegExp(r'^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$');
      for (var i = 0; i < 200; i++) {
        expect(pattern.hasMatch(ChatRoom().code), true);
      }
    });

    test('withCode keeps the code it is given', () {
      expect(ChatRoom.withCode('ABC234').code, 'ABC234');
    });

    test('two people can join, a third gets roomFull', () {
      final cara = Profile(name: 'Cara', username: 'cara');
      expect(room.addMember(ana), JoinResult.joined);
      expect(room.addMember(ben), JoinResult.joined);
      expect(room.addMember(cara), JoinResult.roomFull);
      expect(room.members.length, 2);
    });

    test('joining twice gives alreadyMember', () {
      room.addMember(ana);
      expect(room.addMember(ana), JoinResult.alreadyMember);
      expect(room.members.length, 1);
    });

    test('a non-member cannot send a message', () {
      room.addMember(ana);
      expect(room.addMessage(ben, 'hello'), null);
      expect(room.messages.isEmpty, true);
    });

    test('a member can send a message', () {
      room.addMember(ana);
      final message = room.addMessage(ana, 'hello');
      expect(message, isNotNull);
      expect(room.messages.length, 1);
      expect(room.messages.first.text, 'hello');
    });

    test('markMessagesAsSeen only marks the other persons messages', () {
      room.addMember(ana);
      room.addMember(ben);
      final fromAna = room.addMessage(ana, 'hi Ben')!;
      final fromBen = room.addMessage(ben, 'hi Ana')!;

      room.markMessagesAsSeen(ben);

      expect(fromAna.seen, true);
      expect(fromBen.seen, false);
    });

    test('countUnread counts the other persons unseen messages', () {
      room.addMember(ana);
      room.addMember(ben);
      room.addMessage(ana, 'one');
      room.addMessage(ana, 'two');
      room.addMessage(ben, 'three');

      expect(room.countUnread(ben), 2);
      expect(room.countUnread(ana), 1);

      room.markMessagesAsSeen(ben);
      expect(room.countUnread(ben), 0);
    });

    test('leaving removes the member but keeps the messages', () {
      room.addMember(ana);
      room.addMember(ben);
      room.addMessage(ben, 'bye');

      expect(room.removeMember(ben), true);
      expect(room.hasMember(ben), false);
      expect(room.messages.length, 1);
      expect(room.removeMember(ben), false);
    });

    test('a room is empty once everybody has left', () {
      room.addMember(ana);
      expect(room.isEmpty, false);
      room.removeMember(ana);
      expect(room.isEmpty, true);
    });

    test('otherMemberOf returns the other member, or null if alone', () {
      room.addMember(ana);
      expect(room.otherMemberOf(ana), null);
      room.addMember(ben);
      expect(room.otherMemberOf(ana), ben);
      expect(room.otherMemberOf(ben), ana);
    });

    test('a room closes when one of two members leaves and then refuses '
        'newcomers', () {
      final cara = Profile(name: 'Cara', username: 'cara');
      room.addMember(ana);
      room.addMember(ben);
      room.removeMember(ben);

      expect(room.closed, true);
      expect(room.addMember(cara), JoinResult.roomClosed);
      expect(room.addMember(ben), JoinResult.roomClosed); // leaver can't return
      expect(room.addMember(ana), JoinResult.alreadyMember);
      expect(room.members.length, 1);
    });

    test('a room with one member does not close when that member leaves', () {
      room.addMember(ana);
      room.removeMember(ana);
      expect(room.closed, false);
    });

    test('messages longer than 500 characters are refused', () {
      room.addMember(ana);
      expect(room.addMessage(ana, 'x' * 500), isNotNull);
      expect(room.addMessage(ana, 'x' * 501), null);
      expect(room.messages.length, 1);
    });
  });
}
