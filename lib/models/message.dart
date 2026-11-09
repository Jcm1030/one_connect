import 'dart:math';

import 'profile.dart';

// Makes a random id: 32 hex characters (16 random bytes), like "9f3a...".
// Every message gets its own id, so that when messages travel between
// phones later, the same message is never added twice.
String generateMessageId() {
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

// A Message stores one chat message: who sent it, what it says,
// when it was sent, and whether the other person has seen it.
class Message {
  final String id;
  final Profile sender;
  final String text;
  final DateTime timestamp;
  bool seen;
  final String? replyToId;
  final Map<String, String> reactions;

  // A new message gets a new id, the current time, and is not seen yet.
  // When loading a saved message, pass its saved id, timestamp and seen value.
  Message({
    required this.sender,
    required this.text,
    DateTime? timestamp,
    this.seen = false,
    String? id,
    this.replyToId,
    this.reactions = const {},
  }) : timestamp = timestamp ?? DateTime.now(),
       id = id ?? generateMessageId();

  void markAsSeen() {
    seen = true;
  }
}
