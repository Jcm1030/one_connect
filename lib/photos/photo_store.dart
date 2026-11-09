import 'dart:io';

// Keeps the profile photos in a folder inside the app's private storage.
// A photo is COPIED there, so it stays even if the original is deleted.
// Only the file NAME is saved in the save file, never a full path.
class PhotoStore {
  final Directory directory;

  PhotoStore(this.directory);

  static int _counter = 0;

  // A safe file name: letters, numbers, _ or -, then .jpg / .jpeg / .png / .webp.
  // No folders and no "..", so a damaged save file cannot point elsewhere.
  static bool isValidFileName(String name) =>
      name.length <= 100 &&
      RegExp(r'^[A-Za-z0-9_-]+\.(jpg|jpeg|png|webp)$').hasMatch(name);

  File fileFor(String fileName) => File('${directory.path}/$fileName');

  // Copies the picture into the photos folder and returns its new file name.
  // If "replacing" is given, that older photo is deleted afterwards.
  Future<String> saveCopy(
    File source,
    String username, {
    String? replacing,
  }) async {
    await directory.create(recursive: true);

    final lower = source.path.toLowerCase();
    var extension = 'jpg';
    for (final candidate in ['jpeg', 'png', 'webp']) {
      if (lower.endsWith('.$candidate')) {
        extension = candidate;
      }
    }
    final name =
        '${username}_${DateTime.now().millisecondsSinceEpoch}_${_counter++}.$extension';
    await source.copy('${directory.path}/$name');

    if (replacing != null && replacing != name) {
      await delete(replacing);
    }
    return name;
  }

  // Deletes a photo. Does nothing if it is already gone.
  Future<void> delete(String fileName) async {
    if (!isValidFileName(fileName)) {
      return;
    }
    try {
      final file = fileFor(fileName);
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // Nothing more to do: an old photo that cannot be deleted is harmless.
    }
  }
}
