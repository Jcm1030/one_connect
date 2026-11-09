import 'dart:io';

import 'package:path_provider/path_provider.dart';

// Finds a safe folder for the app's data on this device and returns
// the save file inside it. Works on Windows, macOS, Android and iOS.
// It does not work in a web browser (Chrome), which has no file access.
Future<File> defaultSaveFile() async {
  final directory = await getApplicationDocumentsDirectory();
  return File('${directory.path}/oneconnect-data.txt');
}
