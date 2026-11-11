import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'accounts/firebase_account_service.dart';
import 'action_sound_effects.dart';
import 'app.dart';
import 'app_state.dart';
import 'firebase_options.dart';
import 'crypto/secure_key_store.dart';
import 'photos/image_picker_photo_service.dart';
import 'photos/photo_store.dart';
import 'online/online_chat_service.dart';
import 'storage/data_store.dart';
import 'storage/save_location.dart';
import 'updates/ota_update_service.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final saveFile = await defaultSaveFile();
  final appState = AppState(
    DataStore(saveFile),
    accountService: FirebaseAccountService(),
    photoService: ImagePickerPhotoService(),
    photoStore: PhotoStore(Directory('${saveFile.parent.path}/photos')),
    keyStore: SecureKeyStore(),
    onlineChatService: FirestoreOnlineChatService(),
    actionSoundEffects: AudioActionSoundEffects(),
    updateService: OtaUpdateService(),
  );
  await appState.load();

  runApp(OneConnectApp(appState: appState));
}
