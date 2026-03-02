import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/websocket_service.dart';
import '../utils/preferences.dart';

/// Settings tab content.
///
/// Provides URL configuration, connection management,
/// notification preferences, and poll interval control.
class SettingsScreen extends StatefulWidget {
  final AppPreferences prefs;
  final WebSocketService wsService;
  final AuthService authService;

  const SettingsScreen({
    super.key,
    required this.prefs,
    required this.wsService,
    required this.authService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _urlController;
  bool _authenticating = false;

  AppPreferences get _prefs => widget.prefs;
  WebSocketService get _ws => widget.wsService;
  AuthService get _auth => widget.authService;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: _prefs.url);
    _ws.addListener(_onWsStateChanged);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _ws.removeListener(_onWsStateChanged);
    super.dispose();
  }

  void _onWsStateChanged() {
    if (mounted) setState(() {});
  }

  void _saveUrl() {
    final url = _urlController.text.trim();
    _prefs.url = url;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('URL saved'), duration: Duration(seconds: 1)),
    );
  }

  /// Connect with automatic authentication mode detection.
  ///
  /// Flow:
  /// 1. Detect auth mode via GET /api/auth/check/
  /// 2. None → connect directly
  /// 3. Password → show password dialog, POST login, connect
  /// 4. Cloudflare → WebView OAuth, then re-detect (may also need password)
  Future<void> _connectWithAuth() async {
    if (!_prefs.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a TwiCC URL first')),
      );
      return;
    }

    setState(() => _authenticating = true);

    try {
      var mode = await _auth.detectAuthMode();

      // Cloudflare Access flow
      if (mode == AuthMode.cloudflare) {
        if (!mounted) return;
        final token = await _auth.authenticate(context);
        if (token == null) return; // User cancelled

        // Re-detect: now that we have a CF JWT, check if password is also needed
        mode = await _auth.detectAuthMode();
      }

      // Password flow
      if (mode == AuthMode.password) {
        if (!_auth.hasSession) {
          final ok = await _doPasswordLogin();
          if (!ok) return; // User cancelled or login failed
        }
      }

      // All auth resolved, connect
      _ws.start();
    } finally {
      if (mounted) setState(() => _authenticating = false);
    }
  }

  /// Show password dialog and attempt login.
  ///
  /// Returns true if login succeeded, false if cancelled or failed.
  Future<bool> _doPasswordLogin() async {
    if (!mounted) return false;

    final password = await showPasswordDialog(context);
    if (password == null) return false; // Cancelled

    final result = await _auth.loginWithPassword(password);
    if (result.success) return true;

    // Show error and let user retry
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Login failed'),
          backgroundColor: Colors.red,
        ),
      );
    }
    return false;
  }

  Future<void> _toggleConnection() async {
    if (_ws.isActive) {
      _ws.stop();
      return;
    }

    // Save URL first
    _saveUrl();
    await _connectWithAuth();
  }

  /// Re-authenticate after an auth failure.
  ///
  /// Detects the current auth mode and shows the appropriate login UI.
  Future<void> _reauthenticate() async {
    await _connectWithAuth();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
          // --- URL Configuration ---
          _buildSectionHeader('Server'),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'TwiCC URL',
              hintText: 'https://twicc.example.com',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.link),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            onSubmitted: (_) => _saveUrl(),
          ),
          const SizedBox(height: 16),

          // --- Connection ---
          _buildSectionHeader('Connection'),
          _buildConnectionCard(),
          const SizedBox(height: 24),

          // --- Notification Preferences ---
          _buildSectionHeader('Notifications'),
          SwitchListTile(
            title: const Text('Sound'),
            subtitle: const Text('Play sound when Claude needs attention'),
            value: _prefs.soundEnabled,
            onChanged: (value) => setState(() => _prefs.soundEnabled = value),
            secondary: const Icon(Icons.volume_up),
          ),
          SwitchListTile(
            title: const Text('Notifications'),
            subtitle: const Text('Show native notifications'),
            value: _prefs.notificationsEnabled,
            onChanged: (value) => setState(() => _prefs.notificationsEnabled = value),
            secondary: const Icon(Icons.notifications),
          ),
          const SizedBox(height: 24),

          // --- Audio Alerts (media stream, bypasses DND) ---
          _buildSectionHeader('Audio Alerts'),
          SwitchListTile(
            title: const Text('Audio alerts via media stream'),
            subtitle: const Text('Play sounds through music channel (works with BT headphones even in DND)'),
            value: _prefs.audioAlertEnabled,
            onChanged: (value) => setState(() => _prefs.audioAlertEnabled = value),
            secondary: const Icon(Icons.headphones),
          ),
          if (_prefs.audioAlertEnabled) ...[
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: SwitchListTile(
                title: const Text('Question / Permission'),
                subtitle: const Text('Sound when Claude asks a question or needs approval'),
                value: _prefs.audioAlertOnQuestion,
                onChanged: (value) => setState(() => _prefs.audioAlertOnQuestion = value),
                secondary: const Icon(Icons.help_outline),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: SwitchListTile(
                title: const Text('Turn finished'),
                subtitle: const Text('Sound when Claude finishes and waits for a new prompt'),
                value: _prefs.audioAlertOnWaiting,
                onChanged: (value) => setState(() => _prefs.audioAlertOnWaiting = value),
                secondary: const Icon(Icons.check_circle_outline),
              ),
            ),
          ],
          const SizedBox(height: 24),

          // --- Poll Interval ---
          _buildSectionHeader('Battery'),
          _buildPollIntervalSelector(),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _prefs.pollInterval == 0
                  ? 'Persistent connection. Lowest latency, higher battery usage.'
                  : 'Checks every ${_pollIntervalLabel()}. Lower battery usage, delayed notifications.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 24),

          // --- Auto-connect ---
          SwitchListTile(
            title: const Text('Auto-connect on launch'),
            subtitle: const Text('Connect automatically when the app starts'),
            value: _prefs.autoConnect,
            onChanged: (value) => setState(() => _prefs.autoConnect = value),
            secondary: const Icon(Icons.power_settings_new),
          ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _buildConnectionCard() {
    final state = _ws.state;
    final Color statusColor;
    final String statusText;
    final IconData statusIcon;

    switch (state) {
      case WsConnectionState.disconnected:
        statusColor = Colors.grey;
        statusText = 'Disconnected';
        statusIcon = Icons.cloud_off;
        break;
      case WsConnectionState.connecting:
        statusColor = Colors.orange;
        statusText = 'Connecting...';
        statusIcon = Icons.sync;
        break;
      case WsConnectionState.connected:
        statusColor = Colors.green;
        statusText = 'Connected';
        statusIcon = Icons.cloud_done;
        break;
      case WsConnectionState.authRequired:
        statusColor = Colors.orange;
        statusText = 'Authentication required';
        statusIcon = Icons.lock;
        break;
      case WsConnectionState.error:
        statusColor = Colors.red;
        statusText = _ws.errorMessage ?? 'Connection error';
        statusIcon = Icons.error;
        break;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusText,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.w500),
                  ),
                ),
                if (_authenticating)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _authenticating ? null : _toggleConnection,
                    icon: Icon(_ws.isActive ? Icons.stop : Icons.play_arrow),
                    label: Text(_ws.isActive ? 'Disconnect' : 'Connect'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _ws.isActive ? Colors.red : null,
                    ),
                  ),
                ),
                if (state == WsConnectionState.authRequired) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _authenticating ? null : _reauthenticate,
                    icon: const Icon(Icons.login),
                    label: const Text('Sign in'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPollIntervalSelector() {
    final currentInterval = _prefs.pollInterval;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SegmentedButton<int>(
        segments: AppPreferences.pollIntervalOptions.map((option) {
          return ButtonSegment<int>(
            value: option.seconds,
            label: Text(
              option.label,
              style: const TextStyle(fontSize: 11),
            ),
          );
        }).toList(),
        selected: {currentInterval},
        onSelectionChanged: (Set<int> selection) {
          setState(() {
            _prefs.pollInterval = selection.first;
          });
          // If connected, the new interval will take effect on next reconnect
        },
        showSelectedIcon: false,
      ),
    );
  }

  String _pollIntervalLabel() {
    final interval = _prefs.pollInterval;
    final match = AppPreferences.pollIntervalOptions.where((o) => o.seconds == interval);
    return match.isNotEmpty ? match.first.label.toLowerCase() : '$interval seconds';
  }
}
