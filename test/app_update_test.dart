import 'package:flutter_test/flutter_test.dart';
import 'package:oneconnect/updates/app_update.dart';

void main() {
  Map<String, dynamic> record({
    int latest = 2,
    int minBuild = 1,
    String url = 'https://example.com/oneconnect.apk',
    String? sha,
  }) => {
    'latestBuild': latest,
    'latestVersion': '1.1.0',
    'minBuild': minBuild,
    'apkUrl': url,
    'sha256': sha ?? 'A' * 64,
    'notes': ' Replies and reactions ',
  };

  group('parseAppUpdate', () {
    test('no record means no update', () {
      expect(parseAppUpdate(null, currentBuild: 1), isNull);
    });

    test('the same or an older build means no update', () {
      expect(parseAppUpdate(record(latest: 2), currentBuild: 2), isNull);
      expect(parseAppUpdate(record(latest: 2), currentBuild: 3), isNull);
    });

    test('a newer build gives an update with a lowercase checksum', () {
      final update = parseAppUpdate(record(), currentBuild: 1)!;

      expect(update.build, 2);
      expect(update.version, '1.1.0');
      expect(update.sha256, 'a' * 64);
      expect(update.notes, 'Replies and reactions');
      expect(update.required, isFalse);
    });

    test('the update is required when the build is below minBuild', () {
      expect(
        parseAppUpdate(record(latest: 3, minBuild: 2), currentBuild: 1)!
            .required,
        isTrue,
      );
      expect(
        parseAppUpdate(record(latest: 3, minBuild: 2), currentBuild: 2)!
            .required,
        isFalse,
      );
    });

    test('a link that is not https is rejected', () {
      expect(
        parseAppUpdate(
          record(url: 'http://example.com/oneconnect.apk'),
          currentBuild: 1,
        ),
        isNull,
      );
    });

    test('a damaged checksum is rejected', () {
      expect(parseAppUpdate(record(sha: 'abc123'), currentBuild: 1), isNull);
    });

    test('a record with missing fields is rejected', () {
      final data = record()..remove('apkUrl');

      expect(parseAppUpdate(data, currentBuild: 1), isNull);
    });
  });
}
