import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oneconnect/photos/photo_store.dart';

void main() {
  late Directory tempDir;
  late PhotoStore store;
  late File source;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('oneconnect_photo_test');
    store = PhotoStore(Directory('${tempDir.path}/photos'));
    source = File('${tempDir.path}/picked.jpg')..writeAsBytesSync([1, 2, 3]);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test(
    'saveCopy copies the picture into the photos folder with a safe name',
    () async {
      final name = await store.saveCopy(source, 'ana');

      expect(PhotoStore.isValidFileName(name), true);
      expect(name.startsWith('ana_'), true);
      expect(store.fileFor(name).readAsBytesSync(), [1, 2, 3]);
      expect(source.existsSync(), true); // the original is left alone
    },
  );

  test('replacing a photo deletes the old file', () async {
    final first = await store.saveCopy(source, 'ana');
    final second = await store.saveCopy(source, 'ana', replacing: first);

    expect(second == first, false);
    expect(store.fileFor(first).existsSync(), false);
    expect(store.fileFor(second).existsSync(), true);
  });

  test('only plain picture file names are valid', () {
    expect(PhotoStore.isValidFileName('ana_123_0.jpg'), true);
    expect(
      PhotoStore.isValidFileName('ana-1.PNG'),
      false,
    ); // capitals in the extension
    expect(PhotoStore.isValidFileName('ana_1.png'), true);
    expect(PhotoStore.isValidFileName('../evil.jpg'), false);
    expect(PhotoStore.isValidFileName('folder/pic.jpg'), false);
    expect(PhotoStore.isValidFileName('pic.exe'), false);
    expect(PhotoStore.isValidFileName('noextension'), false);
  });

  test('deleting a photo that is already gone does nothing wrong', () async {
    await store.delete('ana_999_0.jpg');
    await store.delete('../outside.jpg'); // refused, not even tried
  });
}
