import 'dart:io';

import 'package:flutter/material.dart';

import '../app_state.dart';
import 'photo_service.dart';

enum _PhotoAction { gallery, camera, remove }

// What the person decided: a new picture, or to remove the current one.
class PhotoChoice {
  final File? file;
  final bool remove;

  const PhotoChoice({this.file, this.remove = false});
}

// Shows "Choose from gallery / Take a photo / Remove photo", then opens the
// gallery or camera. Returns null if the person cancelled at any point.
// Throws PhotoException if the gallery or camera could not be opened.
Future<PhotoChoice?> askForPhoto(
  BuildContext context,
  AppState appState, {
  required bool hasPhoto,
}) async {
  final service = appState.photoService;
  if (service == null) {
    return null;
  }

  final action = await showModalBottomSheet<_PhotoAction>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.of(sheetContext).pop(_PhotoAction.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.of(sheetContext).pop(_PhotoAction.camera),
          ),
          if (hasPhoto)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove photo'),
              onTap: () => Navigator.of(sheetContext).pop(_PhotoAction.remove),
            ),
        ],
      ),
    ),
  );

  if (action == null) {
    return null;
  }
  if (action == _PhotoAction.remove) {
    return const PhotoChoice(remove: true);
  }
  final file = await service.pick(
    action == _PhotoAction.camera ? PhotoSource.camera : PhotoSource.gallery,
  );
  return file == null ? null : PhotoChoice(file: file);
}
