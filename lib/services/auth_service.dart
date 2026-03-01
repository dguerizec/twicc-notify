import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../utils/preferences.dart';

/// Handles Cloudflare Access authentication via WebView.
///
/// Opens a WebView to the TwiCC URL, lets the user complete Google OAuth
/// through Cloudflare Access, then extracts the `CF_Authorization` JWT cookie.
class AuthService {
  final AppPreferences _prefs;

  AuthService(this._prefs);

  /// Whether a valid JWT is available.
  bool get hasToken => _prefs.cfJwt != null && _prefs.cfJwt!.isNotEmpty;

  /// Get the current JWT token, or null if not authenticated.
  String? get token => _prefs.cfJwt;

  /// Clear the stored JWT token.
  void clearToken() {
    _prefs.cfJwt = null;
  }

  /// Open a WebView for Cloudflare Access authentication.
  ///
  /// Returns the JWT token on success, or null if the user cancelled.
  /// This must be called from a widget context that can show a dialog/page.
  Future<String?> authenticate(BuildContext context) async {
    final url = _prefs.url;
    if (url.isEmpty) return null;

    final completer = Completer<String?>();

    if (!context.mounted) return null;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _AuthWebViewDialog(
          url: url,
          onToken: (token) {
            _prefs.cfJwt = token;
            completer.complete(token);
            Navigator.of(dialogContext).pop();
          },
          onCancel: () {
            completer.complete(null);
            Navigator.of(dialogContext).pop();
          },
        );
      },
    );

    return completer.future;
  }

  /// Build cookie header for WebSocket connection.
  ///
  /// Returns a map with the Cookie header if a JWT is available,
  /// or an empty map if no authentication is needed.
  Map<String, String> get wsHeaders {
    final jwt = _prefs.cfJwt;
    if (jwt == null || jwt.isEmpty) return {};
    return {'Cookie': 'CF_Authorization=$jwt'};
  }
}

/// Dialog containing a WebView for Cloudflare Access login.
class _AuthWebViewDialog extends StatefulWidget {
  final String url;
  final ValueChanged<String> onToken;
  final VoidCallback onCancel;

  const _AuthWebViewDialog({
    required this.url,
    required this.onToken,
    required this.onCancel,
  });

  @override
  State<_AuthWebViewDialog> createState() => _AuthWebViewDialogState();
}

class _AuthWebViewDialogState extends State<_AuthWebViewDialog> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _checkForToken(),
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  /// After each page load, check if the CF_Authorization cookie is present.
  Future<void> _checkForToken() async {
    if (mounted) setState(() => _loading = false);

    // Try to extract CF_Authorization cookie via JavaScript
    try {
      final cookies = await _controller.runJavaScriptReturningResult(
        'document.cookie',
      );

      final cookieString = cookies.toString().replaceAll('"', '');
      final cfToken = _extractCfToken(cookieString);
      if (cfToken != null) {
        widget.onToken(cfToken);
      }
    } catch (_) {
      // Cookie access may fail on certain pages, ignore
    }
  }

  /// Extract the CF_Authorization value from a cookie string.
  String? _extractCfToken(String cookies) {
    for (final part in cookies.split(';')) {
      final trimmed = part.trim();
      if (trimmed.startsWith('CF_Authorization=')) {
        final value = trimmed.substring('CF_Authorization='.length);
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Sign in')),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: widget.onCancel,
          ),
        ],
      ),
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: double.maxFinite,
        height: 500,
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading)
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
