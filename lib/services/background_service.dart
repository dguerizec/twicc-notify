import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notification channel ID for the persistent foreground service notification.
const _foregroundChannelId = 'twicc_foreground_service_v2';
const _foregroundChannelName = 'Background Monitoring';

/// Initialize the foreground service configuration.
///
/// The foreground service serves a single purpose: keep the Android process
/// alive and retain network access when the app is in the background.
/// The WebSocket connection and notification logic run on the main isolate;
/// the service just prevents Android from killing the process.
Future<void> initializeBackgroundService() async {
  // Create the notification channel first (required on Android 8+).
  // Must exist before the foreground service tries to post its notification.
  if (Platform.isAndroid) {
    final plugin = FlutterLocalNotificationsPlugin();
    final androidPlugin = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _foregroundChannelId,
          _foregroundChannelName,
          description: 'Keeps TwiCC Notify monitoring Claude sessions in background',
          importance: Importance.low,
        ),
      );
    }
  }

  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onServiceStart,
      autoStart: false,
      isForegroundMode: true,
      foregroundServiceNotificationId: 888,
      notificationChannelId: _foregroundChannelId,
      initialNotificationTitle: 'TwiCC Notify',
      initialNotificationContent: 'Monitoring Claude sessions',
      foregroundServiceTypes: [AndroidForegroundType.remoteMessaging],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: _onServiceStart,
    ),
  );
}

/// Entry point for the background service isolate.
///
/// This runs in a separate isolate but keeps the Android process alive.
/// The actual work (WebSocket, notifications) happens on the main isolate.
@pragma('vm:entry-point')
void _onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  debugPrint('[TwiCC] Foreground service started');

  // Listen for stop command from the main isolate
  service.on('stop').listen((_) {
    debugPrint('[TwiCC] Foreground service stopping');
    service.stopSelf();
  });

  // Update the persistent notification when connection state changes
  service.on('updateNotification').listen((data) {
    if (service is AndroidServiceInstance && data != null) {
      final title = data['title'] as String? ?? 'TwiCC Notify';
      final content = data['content'] as String? ?? 'Monitoring Claude sessions';
      service.setForegroundNotificationInfo(title: title, content: content);
    }
  });
}

/// Start the foreground service to keep the process alive.
///
/// Gracefully skips if notification permission isn't granted (Android 13+),
/// since the foreground service requires a visible notification.
Future<void> startForegroundService() async {
  // On Android 13+, verify notification permission before starting.
  // Without it, startForeground() crashes with "Bad notification".
  if (Platform.isAndroid) {
    final plugin = FlutterLocalNotificationsPlugin();
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final hasPermission = await android?.areNotificationsEnabled() ?? false;
    if (!hasPermission) {
      debugPrint('[TwiCC] Notification permission not granted, skipping foreground service');
      return;
    }
  }

  final service = FlutterBackgroundService();
  final isRunning = await service.isRunning();
  if (!isRunning) {
    debugPrint('[TwiCC] Starting foreground service');
    await service.startService();
  }
}

/// Stop the foreground service.
Future<void> stopForegroundService() async {
  final service = FlutterBackgroundService();
  final isRunning = await service.isRunning();
  if (isRunning) {
    debugPrint('[TwiCC] Stopping foreground service');
    service.invoke('stop');
  }
}

/// Update the persistent notification text.
void updateForegroundNotification(String title, String content) {
  final service = FlutterBackgroundService();
  service.invoke('updateNotification', {'title': title, 'content': content});
}
