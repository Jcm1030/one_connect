import 'app_update.dart';

// Where an update is while it is being installed.
enum UpdateStatus { downloading, installing, failed }

// One step of an update: how far the download is, or why it failed.
class UpdateProgress {
  final UpdateStatus status;

  // 0 to 100, only meaningful while downloading.
  final int percent;

  // A friendly message, only set when the status is failed.
  final String? error;

  const UpdateProgress(this.status, {this.percent = 0, this.error});
}

// Thrown when the app could not check for an update (for example no network).
class UpdateException implements Exception {
  final String message;

  const UpdateException(this.message);

  @override
  String toString() => 'UpdateException($message)';
}

// What the app needs from an update system: look for a newer version, then
// download and install it.
//
// The screens only know about this interface. The real version uses Firestore
// and the phone's installer; tests can use a fake version.
abstract class UpdateService {
  // The installed version, for example "1.0.0 (1)".
  Future<String> currentVersion();

  // The newer version that is available, or null if this one is the latest.
  // Throws UpdateException if the check failed.
  Future<AppUpdate?> checkForUpdate();

  // Downloads the update and hands it to Android's installer.
  // The stream reports progress and ends when the installer takes over.
  Stream<UpdateProgress> install(AppUpdate update);

  // Stops a download that is running.
  Future<void> cancel();
}
