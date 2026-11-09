import 'models/chat_room.dart';
import 'models/profile.dart';

String _twoDigits(int value) => value.toString().padLeft(2, '0');

// Turns a message time into short 12-hour text for the chat bubble,
// for example "9:05 PM". The date is shown by the day labels in the chat.
String formatMessageTime(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final period = time.hour < 12 ? 'AM' : 'PM';
  return '$hour:${_twoDigits(time.minute)} $period';
}

// The greeting shown at the top of the main profile screen.
String greetingForTime(DateTime time) {
  if (time.hour >= 5 && time.hour < 12) {
    return 'Good morning';
  }
  if (time.hour >= 12 && time.hour < 17) {
    return 'Good afternoon';
  }
  return 'Good evening';
}

// Shows the room partner's display name, or a waiting/left-room state.
String roomMemberLabel(ChatRoom room, Profile me) {
  final other = room.otherMemberOf(me);
  if (other == null) {
    return room.closed ? 'Your roommate left' : 'Waiting for roommate';
  }
  return other.name;
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

// The label above the first message of each day: "Today", "Yesterday",
// or a date like "November 8" (with the year if it is not this year).
// "now" is passed in so the function is easy to test.
String formatDayLabel(DateTime day, DateTime now) {
  // UTC dates make the day count exact, whatever the clock changes do.
  final today = DateTime.utc(now.year, now.month, now.day);
  final date = DateTime.utc(day.year, day.month, day.day);
  final daysAgo = today.difference(date).inDays;
  if (daysAgo == 0) {
    return 'Today';
  }
  if (daysAgo == 1) {
    return 'Yesterday';
  }
  final label = '${_monthNames[date.month - 1]} ${date.day}';
  return date.year == now.year ? label : '$label, ${date.year}';
}
