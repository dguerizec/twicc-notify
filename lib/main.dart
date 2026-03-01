import 'package:flutter/material.dart';

import 'screens/settings_screen.dart';
import 'services/auth_service.dart';
import 'services/background_service.dart';
import 'services/notification_service.dart';
import 'services/websocket_service.dart';
import 'utils/preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the foreground service (keeps the process alive in background)
  await initializeBackgroundService();

  // Initialize preferences
  final prefs = AppPreferences();
  await prefs.init();

  // Initialize services
  final authService = AuthService(prefs);
  final notificationService = NotificationService(prefs);
  await notificationService.init();

  final wsService = WebSocketService(prefs, authService, notificationService);

  // Auto-connect if configured
  if (prefs.autoConnect && prefs.isConfigured) {
    wsService.start();
  }

  runApp(TwiccNotifyApp(
    prefs: prefs,
    wsService: wsService,
    authService: authService,
  ));
}

/// Root widget for TwiCC Notify.
class TwiccNotifyApp extends StatelessWidget {
  final AppPreferences prefs;
  final WebSocketService wsService;
  final AuthService authService;

  const TwiccNotifyApp({
    super.key,
    required this.prefs,
    required this.wsService,
    required this.authService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TwiCC Notify',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6366F1), // Indigo — matches TwiCC brand
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF6366F1),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: SettingsScreen(
        prefs: prefs,
        wsService: wsService,
        authService: authService,
      ),
    );
  }
}
