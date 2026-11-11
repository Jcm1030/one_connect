import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_update.dart';
import 'update_service.dart';

// The real update system. The newest version is described in the Firestore
// document "appConfig/android", which you edit by hand in the Firebase
// Console when you publish a new APK. The APK itself is downloaded from the
// link in that document and installed only if its SHA-256 checksum matches.
class OtaUpdateService implements UpdateService {
  final FirebaseFirestore _firestore;

  OtaUpdateService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  @override
  Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return '${info.version} (${info.buildNumber})';
  }

  @override
  Future<AppUpdate?> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final snapshot = await _firestore.doc('appConfig/android').get();
      return parseAppUpdate(
        snapshot.data(),
        currentBuild: int.tryParse(info.buildNumber) ?? 0,
      );
    } on FirebaseException catch (error) {
      throw UpdateException(error.message ?? error.code);
    } catch (_) {
      throw const UpdateException('Could not check for updates.');
    }
  }

  @override
  Stream<UpdateProgress> install(AppUpdate update) async* {
    try {
      await for (final event in OtaUpdate().execute(
        update.apkUrl,
        destinationFilename: 'oneconnect-${update.build}.apk',
        sha256checksum: update.sha256,
      )) {
        yield _toProgress(event);
      }
    } catch (_) {
      yield const UpdateProgress(
        UpdateStatus.failed,
        error: 'The update could not be started.',
      );
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await OtaUpdate().cancel();
    } catch (_) {
      // Nothing to cancel.
    }
  }

  // Turns the plugin's event into our own progress. Status names are used
  // (instead of the plugin's enum values) so a renamed value cannot break
  // the build: anything ending in ERROR is a failure.
  UpdateProgress _toProgress(OtaEvent event) {
    final name = event.status.name;
    if (name == 'DOWNLOADING') {
      return UpdateProgress(
        UpdateStatus.downloading,
        percent: (int.tryParse(event.value ?? '') ?? 0).clamp(0, 100),
      );
    }
    if (name.contains('ERROR') || name == 'CANCELED') {
      return UpdateProgress(UpdateStatus.failed, error: _errorText(name));
    }
    // INSTALLING, or the installer finishing: the system takes over from here.
    return const UpdateProgress(UpdateStatus.installing);
  }

  String _errorText(String status) {
    switch (status) {
      case 'PERMISSION_NOT_GRANTED_ERROR':
        return 'Allow installs from this app in your phone settings, '
            'then try again.';
      case 'CHECKSUM_ERROR':
        return 'The downloaded file did not match, so it was not installed. '
            'Try again later.';
      case 'DOWNLOAD_ERROR':
        return 'The download failed. Check your connection and try again.';
      case 'ALREADY_RUNNING_ERROR':
        return 'An update is already running.';
      case 'CANCELED':
        return 'The update was canceled.';
      default:
        return 'The update could not be installed.';
    }
  }
}
