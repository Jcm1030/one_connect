import 'dart:io';

import 'package:image_picker/image_picker.dart';

import 'photo_service.dart';

// The real photo picker, using the image_picker package.
// Pictures are shrunk to at most 512 x 512 pixels, which is plenty for a
// round profile picture and keeps files small.
class ImagePickerPhotoService implements PhotoService {
  final ImagePicker _picker = ImagePicker();

  @override
  Future<File?> pick(PhotoSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source == PhotoSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      return picked == null ? null : File(picked.path);
    } catch (_) {
      throw const PhotoException();
    }
  }
}
