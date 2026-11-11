// A newer version of the app that can be installed.
class AppUpdate {
  // The build number (the part after "+" in pubspec.yaml).
  final int build;

  // The version shown to the person, for example "1.1.0".
  final String version;

  // Where the APK can be downloaded (always https).
  final String apkUrl;

  // The SHA-256 checksum of the APK, in lowercase hex. The download is only
  // installed if it matches.
  final String sha256;

  // What is new in this version. Can be empty.
  final String notes;

  // True when this phone's version is too old to keep being used.
  final bool required;

  const AppUpdate({
    required this.build,
    required this.version,
    required this.apkUrl,
    required this.sha256,
    required this.notes,
    required this.required,
  });
}

// Reads the update record (the "appConfig/android" document) and decides
// whether there is an update for a phone running [currentBuild].
// Returns null if there is no update, or if the record looks wrong, so a
// damaged record can never push a bad update.
// This is plain Dart (it does not use Firebase), so it can be tested anywhere.
AppUpdate? parseAppUpdate(
  Map<String, dynamic>? data, {
  required int currentBuild,
}) {
  if (data == null) {
    return null;
  }
  final latestBuild = data['latestBuild'];
  final version = data['latestVersion'];
  final apkUrl = data['apkUrl'];
  final sha256 = data['sha256'];
  if (latestBuild is! num ||
      version is! String ||
      apkUrl is! String ||
      sha256 is! String) {
    return null;
  }
  if (latestBuild.toInt() <= currentBuild) {
    return null;
  }
  if (!apkUrl.startsWith('https://')) {
    return null;
  }
  if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256)) {
    return null;
  }

  final minBuild = data['minBuild'];
  final notes = data['notes'];
  return AppUpdate(
    build: latestBuild.toInt(),
    version: version,
    apkUrl: apkUrl,
    sha256: sha256.toLowerCase(),
    notes: notes is String ? notes.trim() : '',
    required: minBuild is num && currentBuild < minBuild.toInt(),
  );
}
