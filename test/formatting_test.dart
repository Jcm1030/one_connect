import 'package:flutter_test/flutter_test.dart';
import 'package:oneconnect/formatting.dart';
import 'package:oneconnect/models/chat_room.dart';
import 'package:oneconnect/models/profile.dart';

void main() {
  group('formatMessageTime', () {
    test('shows 12-hour time with AM and PM', () {
      expect(formatMessageTime(DateTime(2026, 11, 9, 0, 5)), '12:05 AM');
      expect(formatMessageTime(DateTime(2026, 11, 9, 9, 5)), '9:05 AM');
      expect(formatMessageTime(DateTime(2026, 11, 9, 12, 0)), '12:00 PM');
      expect(formatMessageTime(DateTime(2026, 11, 9, 13, 30)), '1:30 PM');
      expect(formatMessageTime(DateTime(2026, 11, 9, 23, 59)), '11:59 PM');
    });
  });

  group('isSameDay', () {
    test('compares only the date', () {
      expect(
        isSameDay(DateTime(2026, 11, 9, 1), DateTime(2026, 11, 9, 23)),
        isTrue,
      );
      expect(isSameDay(DateTime(2026, 11, 9), DateTime(2026, 11, 10)), isFalse);
    });
  });

  group('formatDayLabel', () {
    final now = DateTime(2026, 11, 9, 10);

    test('Today and Yesterday', () {
      expect(formatDayLabel(DateTime(2026, 11, 9, 8), now), 'Today');
      expect(formatDayLabel(DateTime(2026, 11, 8, 23), now), 'Yesterday');
    });

    test('older dates in the same year have no year', () {
      expect(formatDayLabel(DateTime(2026, 11, 1), now), 'November 1');
    });

    test('dates from another year include the year', () {
      expect(formatDayLabel(DateTime(2025, 12, 31), now), 'December 31, 2025');
    });
  });

  group('greetingForTime', () {
    test('morning, afternoon and evening', () {
      expect(greetingForTime(DateTime(2026, 11, 9, 5)), 'Good morning');
      expect(greetingForTime(DateTime(2026, 11, 9, 11)), 'Good morning');
      expect(greetingForTime(DateTime(2026, 11, 9, 12)), 'Good afternoon');
      expect(greetingForTime(DateTime(2026, 11, 9, 16)), 'Good afternoon');
      expect(greetingForTime(DateTime(2026, 11, 9, 17)), 'Good evening');
      expect(greetingForTime(DateTime(2026, 11, 9, 4)), 'Good evening');
    });
  });

  group('roomMemberLabel', () {
    test('waiting, roommate name, and roommate left', () {
      final me = Profile(name: 'Me', username: 'me_user');
      final other = Profile(name: 'Sam', username: 'sam_user');
      final room = ChatRoom.withCode('ABC234')..addMember(me);

      expect(roomMemberLabel(room, me), 'Waiting for roommate');

      room.addMember(other);
      expect(roomMemberLabel(room, me), 'Sam');

      room.removeMember(other);
      expect(roomMemberLabel(room, me), 'Your roommate left');
    });
  });
}
