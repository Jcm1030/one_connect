import 'dart:io';

// Where a profile photo can come from.
enum PhotoSource { gallery, camera }

// Thrown when the camera or gallery could not be opened.
class PhotoException implements Exception {
  const PhotoException();

  @override
  String toString() => 'PhotoException';
}

// Lets the person pick a photo. The app only knows this interface; the real
// one uses the phone's gallery and camera, and tests use a fake.
abstract class PhotoService {
  // Returns the chosen picture, or null if the person cancelled.
  // Throws PhotoException if the gallery or camera could not be opened.
  Future<File?> pick(PhotoSource source);
}
