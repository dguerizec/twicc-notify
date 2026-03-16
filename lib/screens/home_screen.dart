import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/quota_service.dart';
import '../services/stats_service.dart';
import '../services/websocket_service.dart';
import '../utils/preferences.dart';
import 'quotas_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

/// Root screen with bottom navigation between Settings and Stats.
class HomeScreen extends StatefulWidget {
  final AppPreferences prefs;
  final WebSocketService wsService;
  final AuthService authService;
  final StatsService statsService;
  final QuotaService quotaService;
  final NotificationService notificationService;

  const HomeScreen({
    super.key,
    required this.prefs,
    required this.wsService,
    required this.authService,
    required this.statsService,
    required this.quotaService,
    required this.notificationService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    // Show Settings tab first when not yet configured, Quotas otherwise.
    _selectedIndex = widget.prefs.isConfigured ? 0 : 1;
  }

  static const _titles = ['Quotas', 'TwiCC Notify', 'Stats'];

  /// Open TwiCC in an in-app browser tab.
  ///
  /// Opens the last notified session URL if available,
  /// otherwise opens the TwiCC home page.
  Future<void> _openTwicc() async {
    final url = widget.notificationService.lastUrlOrHome;
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        actions: [
          if (widget.prefs.isConfigured)
            IconButton(
              onPressed: _openTwicc,
              icon: const Icon(Icons.open_in_browser),
              tooltip: 'Open TwiCC',
            ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          QuotasScreen(
            quotaService: widget.quotaService,
          ),
          SettingsScreen(
            prefs: widget.prefs,
            wsService: widget.wsService,
            authService: widget.authService,
          ),
          StatsScreen(
            statsService: widget.statsService,
            wsService: widget.wsService,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.speed_outlined),
            selectedIcon: Icon(Icons.speed),
            label: 'Quotas',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Stats',
          ),
        ],
      ),
    );
  }
}
