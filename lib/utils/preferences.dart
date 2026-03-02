import 'package:shared_preferences/shared_preferences.dart';

/// Centralized access to persisted user preferences.
///
/// Wraps [SharedPreferences] with typed getters/setters for all
/// TwiCC Notify settings.
class AppPreferences {
  static const _keyUrl = 'twicc_url';
  static const _keyCfJwt = 'cf_jwt';
  static const _keySoundEnabled = 'sound_enabled';
  static const _keyNotificationsEnabled = 'notifications_enabled';
  static const _keyPollInterval = 'poll_interval';
  static const _keyAutoConnect = 'auto_connect';
  static const _keyAudioAlertEnabled = 'audio_alert_enabled';
  static const _keyAudioAlertOnQuestion = 'audio_alert_on_question';
  static const _keyAudioAlertOnWaiting = 'audio_alert_on_waiting';
  static const _keyStatsBuckets = 'ws_stats_buckets';

  late final SharedPreferences _prefs;

  /// Initialize the preferences. Must be called once at app startup.
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // --- TwiCC URL ---

  String get url => _prefs.getString(_keyUrl) ?? '';
  set url(String value) => _prefs.setString(_keyUrl, value);

  // --- Cloudflare Access JWT ---

  String? get cfJwt => _prefs.getString(_keyCfJwt);
  set cfJwt(String? value) {
    if (value == null) {
      _prefs.remove(_keyCfJwt);
    } else {
      _prefs.setString(_keyCfJwt, value);
    }
  }

  // --- Sound notifications ---

  bool get soundEnabled => _prefs.getBool(_keySoundEnabled) ?? true;
  set soundEnabled(bool value) => _prefs.setBool(_keySoundEnabled, value);

  // --- Native notifications ---

  bool get notificationsEnabled => _prefs.getBool(_keyNotificationsEnabled) ?? true;
  set notificationsEnabled(bool value) => _prefs.setBool(_keyNotificationsEnabled, value);

  // --- Poll interval (seconds, 0 = realtime) ---

  int get pollInterval => _prefs.getInt(_keyPollInterval) ?? 0;
  set pollInterval(int value) => _prefs.setInt(_keyPollInterval, value);

  /// Available poll interval options with human-readable labels.
  static const List<({int seconds, String label})> pollIntervalOptions = [
    (seconds: 0, label: 'Realtime'),
    (seconds: 30, label: '30 seconds'),
    (seconds: 60, label: '1 minute'),
    (seconds: 300, label: '5 minutes'),
    (seconds: 900, label: '15 minutes'),
  ];

  // --- Auto-connect on launch ---

  bool get autoConnect => _prefs.getBool(_keyAutoConnect) ?? false;
  set autoConnect(bool value) => _prefs.setBool(_keyAutoConnect, value);

  // --- Audio alerts (media stream, bypasses DND) ---

  bool get audioAlertEnabled => _prefs.getBool(_keyAudioAlertEnabled) ?? false;
  set audioAlertEnabled(bool value) => _prefs.setBool(_keyAudioAlertEnabled, value);

  bool get audioAlertOnQuestion => _prefs.getBool(_keyAudioAlertOnQuestion) ?? true;
  set audioAlertOnQuestion(bool value) => _prefs.setBool(_keyAudioAlertOnQuestion, value);

  bool get audioAlertOnWaiting => _prefs.getBool(_keyAudioAlertOnWaiting) ?? true;
  set audioAlertOnWaiting(bool value) => _prefs.setBool(_keyAudioAlertOnWaiting, value);

  // --- WebSocket stats persistence ---

  String? get statsJson => _prefs.getString(_keyStatsBuckets);
  Future<void> setStatsJson(String json) => _prefs.setString(_keyStatsBuckets, json);
  Future<void> clearStatsJson() => _prefs.remove(_keyStatsBuckets);

  /// Whether a URL has been configured.
  bool get isConfigured => url.isNotEmpty;

  /// Build the WebSocket URL from the configured TwiCC URL.
  ///
  /// Converts `https://` to `wss://` and appends `/ws/`.
  String? get wsUrl {
    if (!isConfigured) return null;
    final base = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final wsBase = base.replaceFirst(RegExp(r'^https?://'), 'wss://');
    return '$wsBase/ws/';
  }
}
