import 'dart:io';

import 'package:oneconnect/models/app_settings.dart';
import 'package:oneconnect/models/chat_room.dart';
import 'package:oneconnect/models/profile.dart';
import 'package:oneconnect/storage/data_store.dart';

// A store that pretends to save, so screen tests never touch real files.
class FakeStore extends DataStore {
  FakeStore() : super(File('not-used.txt'));

  @override
  Future<bool> save(
    List<Profile> profiles,
    List<ChatRoom> rooms, {
    AppSettings? settings,
  }) async => true;
}
