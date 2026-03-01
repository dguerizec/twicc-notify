import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../utils/preferences.dart';

/// The type of audio alert to play.
enum AlertSound {
  /// Claude is asking a question or needs permission (pending_request).
  question('sounds/question.ogg'),

  /// Claude finished its turn, waiting for a new prompt (user_turn).
  waiting('sounds/waiting.ogg');

  final String assetPath;
  const AlertSound(this.assetPath);
}

/// Plays short audio alerts through the **media** audio stream.
///
/// Unlike notification sounds (which are silenced by Do Not Disturb),
/// media-stream audio plays through connected Bluetooth headphones
/// regardless of the phone's notification/ringer volume.
///
/// This is an opt-in feature controlled by the user in settings.
class AudioAlertService {
  final AppPreferences _prefs;

  /// Single reusable player instance — plays short one-shot sounds.
  final AudioPlayer _player = AudioPlayer();

  AudioAlertService(this._prefs) {
    // Use the music stream so sounds bypass DND and play through BT headphones.
    _player.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        contentType: AndroidContentType.music,
        usageType: AndroidUsageType.media,
        audioFocus: AndroidAudioFocus.gainTransient,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.ambient,
      ),
    ));
  }

  /// Play an alert sound if audio alerts are enabled for this event type.
  ///
  /// Checks user preferences before playing. Silently returns if the
  /// feature is disabled or the specific alert type is disabled.
  Future<void> play(AlertSound alert) async {
    if (!_prefs.audioAlertEnabled) return;

    switch (alert) {
      case AlertSound.question:
        if (!_prefs.audioAlertOnQuestion) return;
      case AlertSound.waiting:
        if (!_prefs.audioAlertOnWaiting) return;
    }

    try {
      await _player.stop(); // Stop any currently playing sound
      await _player.play(AssetSource(alert.assetPath));
    } catch (e) {
      debugPrint('[TwiCC] Failed to play audio alert: $e');
    }
  }

  /// Release resources.
  void dispose() {
    _player.dispose();
  }
}
