import '../models/app_settings.dart';
import '../models/chat_room.dart';
import '../models/profile.dart';

// What load() gives back: the data it managed to read, plus a list of
// warnings about anything it had to skip.
class LoadResult {
  final List<Profile> profiles = [];
  final List<ChatRoom> rooms = [];
  final List<String> warnings = [];
  AppSettings settings = const AppSettings();

  // True if an older save file was read, so the app should save once
  // to rewrite it in the current format.
  bool upgradedFromOldFormat = false;
}

// Anything that can keep the app's data: today a text file on the phone,
// later possibly an online service. AppState only knows about this
// interface, so the storage behind it can be swapped without touching screens.
abstract class AppStorage {
  Future<LoadResult> load();
  Future<bool> save(
    List<Profile> profiles,
    List<ChatRoom> rooms, {
    AppSettings? settings,
  });
}
