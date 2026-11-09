import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract interface class ActionSoundEffects {
  Future<void> playSuccess();

  Future<void> dispose();
}

class AudioActionSoundEffects implements ActionSoundEffects {
  final AudioPlayer _player;

  AudioActionSoundEffects({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  @override
  Future<void> playSuccess() async {
    try {
      await _player.play(
        AssetSource('sounds/action_success.wav'),
        volume: 0.45,
      );
    } on AudioPlayerException catch (error, stackTrace) {
      debugPrint('Could not play the action sound: $error');
      debugPrintStack(stackTrace: stackTrace);
    } on MissingPluginException catch (error, stackTrace) {
      debugPrint('Audio playback is unavailable: $error');
      debugPrintStack(stackTrace: stackTrace);
    } on PlatformException catch (error, stackTrace) {
      debugPrint('Could not play the action sound: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  Future<void> dispose() => _player.dispose();
}
