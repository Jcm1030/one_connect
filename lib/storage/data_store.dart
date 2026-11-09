import 'dart:io';

import '../models/app_settings.dart';
import '../models/chat_room.dart';
import '../models/message.dart';
import '../models/profile.dart';
import '../photos/photo_store.dart';
import 'app_storage.dart';

// Code that imports data_store.dart can also use LoadResult and AppStorage.
export 'app_storage.dart';

// DataStore saves everything to one plain text file and loads it back.
//
// Each line is one record, with fields separated by "|":
//   SETTING|theme|dark   (also textSize and reduceAnimations)
//   PROFILE|username|name
//   COLOR|username|teal    (or purple / pink; no line means pink)
//   ACCOUNT|username|accountId   (only for profiles with an online account)
//   PHOTO|username|fileName      (only for profiles with a photo)
//   ROOM|code|username1|username2   (a closed room ends with |#closed)
//   MSG2|code|senderUsername|timestamp|seen|messageId|text
//   MESSAGE|code|senderUsername|timestamp|seen|text   (older files, no id)
//
// The free-text field (name or message text) is always LAST,
// so a "|" typed inside it cannot break the file.
class DataStore implements AppStorage {
  final File file;

  DataStore(this.file);

  // ---------- Saving ----------

  // Returns true if the data was saved, false if something went wrong.
  @override
  Future<bool> save(
    List<Profile> profiles,
    List<ChatRoom> rooms, {
    AppSettings? settings,
  }) async {
    final lines = <String>[];

    if (settings != null) {
      lines.add('SETTING|theme|${settings.themeChoice.name}');
      lines.add('SETTING|textSize|${settings.textSize.name}');
      lines.add('SETTING|reduceAnimations|${settings.reduceAnimations}');
    }

    for (final profile in profiles) {
      lines.add('PROFILE|${profile.username}|${profile.name}');
    }

    // Colors get their own lines, so older save files (without any) still load.
    for (final profile in profiles) {
      lines.add('COLOR|${profile.username}|${profile.color.name}');
    }

    // Only the NAME of each photo file is saved, never a full path.
    for (final profile in profiles) {
      final photo = profile.photoFileName;
      if (photo != null) {
        lines.add('PHOTO|${profile.username}|$photo');
      }
    }

    // Only the account id is saved. Emails and passwords are never stored here.
    for (final profile in profiles) {
      final accountId = profile.accountId;
      if (accountId != null) {
        lines.add('ACCOUNT|${profile.username}|$accountId');
      }
    }

    for (final room in rooms.where((room) => !room.online)) {
      var line = 'ROOM|${room.code}';
      for (final member in room.members) {
        line += '|${member.username}';
      }
      if (room.closed) {
        // "#" cannot be part of a username, so this can't be mistaken for one.
        line += '|#closed';
      }
      lines.add(line);
    }

    for (final room in rooms.where((room) => !room.online)) {
      for (final message in room.messages) {
        lines.add(
          'MSG2|${room.code}'
          '|${message.sender.username}'
          '|${message.timestamp.toIso8601String()}'
          '|${message.seen}'
          '|${message.id}'
          '|${message.text}',
        );
      }
    }

    // Write to a temporary file first, then replace the real file.
    // This way a crash in the middle of saving cannot ruin the old data.
    final tempFile = File('${file.path}.tmp');
    try {
      final content = lines.isEmpty ? '' : '${lines.join('\n')}\n';
      await tempFile.writeAsString(content, flush: true);
      await tempFile.rename(file.path);
      return true;
    } on FileSystemException {
      return false;
    }
  }

  // ---------- Loading ----------

  // Reads the save file. If it is missing or empty, nothing is loaded.
  // Bad lines are skipped and described in result.warnings.
  @override
  Future<LoadResult> load() async {
    final result = LoadResult();

    if (!await file.exists()) {
      return result;
    }

    List<String> lines;
    try {
      lines = await file.readAsLines();
    } catch (e) {
      result.warnings.add(
        'Could not read the save file. Starting with no saved data.',
      );
      return result;
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        continue;
      }
      final problem = _loadLine(line, result);
      if (problem != null) {
        result.warnings.add('Skipped line ${i + 1} ($problem).');
      }
    }
    return result;
  }

  // Reads one line. Returns null if it worked, or a short reason if it did not.
  String? _loadLine(String line, LoadResult result) {
    if (line.startsWith('SETTING|')) {
      return _loadSetting(line, result);
    }
    if (line.startsWith('PROFILE|')) {
      return _loadProfile(line, result);
    }
    if (line.startsWith('COLOR|')) {
      return _loadColor(line, result);
    }
    if (line.startsWith('ACCOUNT|')) {
      return _loadAccount(line, result);
    }
    if (line.startsWith('PHOTO|')) {
      return _loadPhoto(line, result);
    }
    if (line.startsWith('ROOM|')) {
      return _loadRoom(line, result);
    }
    if (line.startsWith('MSG2|')) {
      return _loadMessage(line, result, hasId: true);
    }
    if (line.startsWith('MESSAGE|')) {
      return _loadMessage(line, result, hasId: false);
    }
    return 'unknown line type';
  }

  String? _loadSetting(String line, LoadResult result) {
    final parts = line.split('|');
    if (parts.length != 3) {
      return 'setting line is incomplete';
    }
    final value = parts[2];

    switch (parts[1]) {
      case 'theme':
        final choice = _byName(ThemeChoice.values, value);
        if (choice == null) {
          return 'unknown theme setting';
        }
        result.settings = result.settings.copyWith(themeChoice: choice);
        return null;
      case 'textSize':
        final choice = _byName(TextSizeChoice.values, value);
        if (choice == null) {
          return 'unknown text size setting';
        }
        result.settings = result.settings.copyWith(textSize: choice);
        return null;
      case 'reduceAnimations':
        if (value != 'true' && value != 'false') {
          return 'invalid animations setting';
        }
        result.settings = result.settings.copyWith(
          reduceAnimations: value == 'true',
        );
        return null;
      default:
        return 'unknown setting';
    }
  }

  // Finds the enum value with this name, or null.
  T? _byName<T extends Enum>(List<T> values, String name) {
    for (final value in values) {
      if (value.name == name) {
        return value;
      }
    }
    return null;
  }

  String? _loadProfile(String line, LoadResult result) {
    final parts = _splitMax(line, 3);
    if (parts.length < 3) {
      return 'profile line is incomplete';
    }
    final username = parts[1];
    final name = parts[2];

    if (!RegExp(r'^[A-Za-z0-9_]{3,15}$').hasMatch(username)) {
      return 'invalid username';
    }
    if (name.isEmpty) {
      return 'profile has no name';
    }
    if (_findProfile(result.profiles, username) != null) {
      return 'duplicate username';
    }
    result.profiles.add(Profile(name: name, username: username));
    return null;
  }

  String? _loadPhoto(String line, LoadResult result) {
    final parts = line.split('|');
    if (parts.length != 3) {
      return 'photo line is incomplete';
    }
    final profile = _findProfile(result.profiles, parts[1]);
    if (profile == null) {
      return 'photo refers to an unknown profile';
    }
    if (!PhotoStore.isValidFileName(parts[2])) {
      return 'invalid photo file name';
    }
    profile.photoFileName = parts[2];
    return null;
  }

  String? _loadAccount(String line, LoadResult result) {
    final parts = line.split('|');
    if (parts.length != 3) {
      return 'account line is incomplete';
    }
    final profile = _findProfile(result.profiles, parts[1]);
    if (profile == null) {
      return 'account refers to an unknown profile';
    }
    final accountId = parts[2];
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(accountId)) {
      return 'invalid account id';
    }
    if (result.profiles.any((other) => other.accountId == accountId)) {
      return 'account id already belongs to another profile';
    }
    profile.accountId = accountId;
    return null;
  }

  String? _loadColor(String line, LoadResult result) {
    final parts = line.split('|');
    if (parts.length != 3) {
      return 'color line is incomplete';
    }
    final profile = _findProfile(result.profiles, parts[1]);
    if (profile == null) {
      return 'color refers to an unknown profile';
    }
    for (final color in ProfileColor.values) {
      if (color.name == parts[2]) {
        profile.color = color;
        return null;
      }
    }
    return 'unknown color';
  }

  String? _loadRoom(String line, LoadResult result) {
    final parts = List<String>.of(line.split('|'));
    // An optional last field "#closed" marks a room that no longer accepts
    // new members. Older save files simply do not have it.
    var closed = false;
    if (parts.last == '#closed') {
      closed = true;
      parts.removeLast();
    }
    if (parts.length < 3 || parts.length > 4) {
      return 'a room needs 1 or 2 members';
    }
    final code = parts[1];
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(code)) {
      return 'invalid room code';
    }
    if (_findRoom(result.rooms, code) != null) {
      return 'duplicate room code';
    }

    final room = ChatRoom.withCode(code);
    for (var i = 2; i < parts.length; i++) {
      final member = _findProfile(result.profiles, parts[i]);
      if (member == null) {
        return 'room refers to an unknown profile';
      }
      if (room.addMember(member) != JoinResult.joined) {
        return 'could not add a room member';
      }
    }
    room.closed =
        closed; // set after adding members, because closed rooms refuse them
    result.rooms.add(room);
    return null;
  }

  // Reads a message line. Newer lines (MSG2) carry an id. Older lines
  // (MESSAGE) do not, so they get a new id and the file is marked for upgrade.
  String? _loadMessage(String line, LoadResult result, {required bool hasId}) {
    final fieldCount = hasId ? 7 : 6;
    final parts = _splitMax(line, fieldCount);
    if (parts.length < fieldCount) {
      return 'message line is incomplete';
    }

    final room = _findRoom(result.rooms, parts[1]);
    if (room == null) {
      return 'message refers to an unknown room';
    }
    final sender = _findProfile(result.profiles, parts[2]);
    if (sender == null) {
      return 'message refers to an unknown sender';
    }

    final timestamp = DateTime.tryParse(parts[3]);
    if (timestamp == null) {
      return 'invalid timestamp';
    }

    if (parts[4] != 'true' && parts[4] != 'false') {
      return 'invalid seen status';
    }
    final seen = parts[4] == 'true';

    String id;
    if (hasId) {
      id = parts[5];
      if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) {
        return 'invalid message id';
      }
      if (room.messages.any((message) => message.id == id)) {
        return 'duplicate message id';
      }
    } else {
      id = generateMessageId();
    }

    final text = parts[fieldCount - 1];
    if (text.isEmpty) {
      return 'message has no text';
    }

    // A message can come from someone who has since left the room,
    // so we do not require the sender to still be a member.
    room.messages.add(
      Message(
        sender: sender,
        text: text,
        timestamp: timestamp,
        seen: seen,
        id: id,
      ),
    );
    if (!hasId) {
      result.upgradedFromOldFormat = true;
    }
    return null;
  }

  // Splits a line at "|" into at most maxParts pieces. The last piece keeps
  // any remaining "|" characters (Dart's split() has no limit option).
  List<String> _splitMax(String line, int maxParts) {
    final parts = <String>[];
    var start = 0;
    while (parts.length < maxParts - 1) {
      final index = line.indexOf('|', start);
      if (index == -1) {
        break;
      }
      parts.add(line.substring(start, index));
      start = index + 1;
    }
    parts.add(line.substring(start));
    return parts;
  }

  Profile? _findProfile(List<Profile> profiles, String username) {
    for (final profile in profiles) {
      if (profile.username.toLowerCase() == username.toLowerCase()) {
        return profile;
      }
    }
    return null;
  }

  ChatRoom? _findRoom(List<ChatRoom> rooms, String code) {
    for (final room in rooms) {
      if (room.code == code) {
        return room;
      }
    }
    return null;
  }
}
