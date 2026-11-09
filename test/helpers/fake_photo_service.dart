import 'dart:io';

import 'package:oneconnect/photos/photo_service.dart';

// A photo picker for tests: "pick" returns whatever picture is set in "next".
class FakePhotoService implements PhotoService {
  File? next;
  PhotoSource? lastSource;
  bool fail = false;

  @override
  Future<File?> pick(PhotoSource source) async {
    lastSource = source;
    if (fail) {
      throw const PhotoException();
    }
    return next;
  }
}
