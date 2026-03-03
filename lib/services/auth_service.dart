import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../utils/preferences.dart';

/// Thrown when the server presents a self-signed or untrusted TLS certificate
/// and the user has not opted in to accepting it.
class SelfSignedCertificateException implements Exception {
  final String host;
  SelfSignedCertificateException(this.host);

  @override
  String toString() => 'Self-signed certificate rejected for $host';
}

/// Authentication mode detected from the TwiCC server.
enum AuthMode {
  /// No authentication required (no password, no Cloudflare).
  none,

  /// TwiCC password authentication (POST /api/auth/login/).
  password,

  /// Cloudflare Access authentication (OAuth via WebView).
  cloudflare,
}

/// Result of an authentication attempt.
class AuthResult {
  final bool success;
  final String? error;

  const AuthResult.ok() : success = true, error = null;
  const AuthResult.failed(this.error) : success = false;
}

/// Handles authentication for TwiCC connections.
///
/// Supports three modes:
/// - **None**: No auth needed, direct WebSocket connection.
/// - **Password**: TwiCC built-in password. POST to /api/auth/login/
///   to obtain a Django session cookie.
/// - **Cloudflare**: Cloudflare Access OAuth via WebView to obtain
///   a CF_Authorization JWT cookie.
///
/// Detection is automatic via GET /api/auth/check/.
class AuthService {
  final AppPreferences _prefs;

  AuthService(this._prefs);

  // --- Token state ---

  /// Whether a Cloudflare Access JWT is available.
  bool get hasToken => _prefs.cfJwt != null && _prefs.cfJwt!.isNotEmpty;

  /// Whether a Django session cookie is available.
  bool get hasSession =>
      _prefs.sessionCookie != null && _prefs.sessionCookie!.isNotEmpty;

  /// Whether any form of authentication credential is stored.
  bool get hasCredentials => hasToken || hasSession;

  /// Clear the Cloudflare JWT token.
  void clearToken() {
    _prefs.cfJwt = null;
  }

  /// Clear the Django session cookie.
  void clearSession() {
    _prefs.sessionCookie = null;
  }

  /// Clear all stored credentials.
  void clearAll() {
    clearToken();
    clearSession();
  }

  // --- HTTP client factory ---

  /// Create an [HttpClient] with proper TLS certificate handling.
  ///
  /// Self-signed certificates are only accepted if the user has explicitly
  /// enabled it in settings. Otherwise, a [SelfSignedCertificateException]
  /// is thrown when a bad certificate is encountered, allowing the UI to
  /// prompt the user for confirmation.
  HttpClient _createHttpClient() {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    client.badCertificateCallback = (cert, host, port) {
      if (_prefs.acceptSelfSignedCerts) {
        debugPrint('[TwiCC Auth] Accepting self-signed cert for $host:$port');
        return true;
      }
      debugPrint('[TwiCC Auth] Rejecting self-signed cert for $host:$port');
      return false;
    };
    return client;
  }

  // --- Auth mode detection ---

  /// Detect the authentication mode by probing the server.
  ///
  /// Calls GET /api/auth/check/ to determine what authentication
  /// the server requires:
  /// - JSON response with `password_required: false` → [AuthMode.none]
  /// - JSON response with `password_required: true` → [AuthMode.password]
  /// - Redirect or non-JSON response → [AuthMode.cloudflare]
  ///
  /// If a CF JWT is stored, it's included in the probe request so
  /// the check can pass through Cloudflare Access.
  ///
  /// Throws [SelfSignedCertificateException] if the server uses
  /// a self-signed certificate and the user hasn't accepted it.
  Future<AuthMode> detectAuthMode() async {
    final url = _prefs.url;
    if (url.isEmpty) return AuthMode.none;

    final client = _createHttpClient();

    try {
      final base = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
      final request = await client.getUrl(Uri.parse('$base/api/auth/check/'));
      request.followRedirects = false;

      // Include CF JWT if available (needed to pass through Cloudflare)
      final jwt = _prefs.cfJwt;
      if (jwt != null && jwt.isNotEmpty) {
        request.headers.set('Cookie', 'CF_Authorization=$jwt');
      }

      // Include session cookie if available
      final session = _prefs.sessionCookie;
      if (session != null && session.isNotEmpty) {
        final existing = request.headers.value('Cookie') ?? '';
        final separator = existing.isNotEmpty ? '; ' : '';
        request.headers.set('Cookie', '$existing${separator}sessionid=$session');
      }

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      // Redirect → Cloudflare Access is intercepting
      if (response.statusCode >= 300 && response.statusCode < 400) {
        debugPrint('[TwiCC Auth] Redirect detected → Cloudflare mode');
        return AuthMode.cloudflare;
      }

      // Try to parse JSON response from Django
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        final passwordRequired = json['password_required'] as bool? ?? false;

        if (!passwordRequired) {
          debugPrint('[TwiCC Auth] No password required → no auth mode');
          return AuthMode.none;
        }

        final authenticated = json['authenticated'] as bool? ?? false;
        if (authenticated) {
          debugPrint('[TwiCC Auth] Already authenticated via session');
          return AuthMode.none;
        }

        debugPrint('[TwiCC Auth] Password required → password mode');
        return AuthMode.password;
      } catch (_) {
        // Non-JSON response (e.g. Cloudflare login HTML page)
        debugPrint('[TwiCC Auth] Non-JSON response → Cloudflare mode');
        return AuthMode.cloudflare;
      }
    } on HandshakeException catch (_) {
      // TLS handshake failed — likely a self-signed certificate
      final host = Uri.parse(url).host;
      throw SelfSignedCertificateException(host);
    } catch (e) {
      // Network error — can't detect, let WebSocket try without auth
      debugPrint('[TwiCC Auth] Detection failed: $e');
      return AuthMode.none;
    } finally {
      client.close();
    }
  }

  // --- Password login ---

  /// Login with TwiCC password.
  ///
  /// POST to /api/auth/login/ with the password. On success, extracts
  /// and stores the Django session cookie for use in WebSocket connections.
  ///
  /// Returns [AuthResult.ok] on success, [AuthResult.failed] with an
  /// error message on failure.
  ///
  /// Throws [SelfSignedCertificateException] if the server uses
  /// a self-signed certificate and the user hasn't accepted it.
  Future<AuthResult> loginWithPassword(String password) async {
    final url = _prefs.url;
    if (url.isEmpty) return const AuthResult.failed('No URL configured');

    final client = _createHttpClient();

    try {
      final base = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
      final request =
          await client.postUrl(Uri.parse('$base/api/auth/login/'));
      request.headers.contentType = ContentType.json;

      // Include CF JWT if needed (for CF + password scenario)
      final jwt = _prefs.cfJwt;
      if (jwt != null && jwt.isNotEmpty) {
        request.headers.set('Cookie', 'CF_Authorization=$jwt');
      }

      request.write(jsonEncode({'password': password}));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        // Extract sessionid cookie from Set-Cookie headers
        final cookies = response.headers['set-cookie'];
        if (cookies != null) {
          for (final cookie in cookies) {
            final sessionId = _extractSessionId(cookie);
            if (sessionId != null) {
              _prefs.sessionCookie = sessionId;
              debugPrint('[TwiCC Auth] Password login successful, session stored');
              return const AuthResult.ok();
            }
          }
        }
        // Login succeeded but no session cookie in response
        // (shouldn't happen with Django, but handle gracefully)
        debugPrint('[TwiCC Auth] Login OK but no session cookie found');
        return const AuthResult.ok();
      }

      // Parse error message from response
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        final error = json['error'] as String? ?? 'Login failed';
        return AuthResult.failed(error);
      } catch (_) {
        return AuthResult.failed('Login failed (HTTP ${response.statusCode})');
      }
    } on HandshakeException catch (_) {
      final host = Uri.parse(url).host;
      throw SelfSignedCertificateException(host);
    } catch (e) {
      debugPrint('[TwiCC Auth] Login error: $e');
      return AuthResult.failed('Connection error: $e');
    } finally {
      client.close();
    }
  }

  /// Extract the sessionid value from a Set-Cookie header string.
  String? _extractSessionId(String setCookieHeader) {
    for (final part in setCookieHeader.split(';')) {
      final trimmed = part.trim();
      if (trimmed.startsWith('sessionid=')) {
        final value = trimmed.substring('sessionid='.length);
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  // --- Cloudflare Access authentication ---

  /// Open a WebView for Cloudflare Access authentication.
  ///
  /// Returns the JWT token on success, or null if the user cancelled.
  /// This must be called from a widget context that can show a dialog.
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

  // --- WebSocket headers ---

  /// Build Cookie header for WebSocket connections.
  ///
  /// Combines CF JWT and/or Django session cookie as needed.
  /// Returns an empty map if no credentials are stored.
  Map<String, String> get wsHeaders {
    final parts = <String>[];

    final jwt = _prefs.cfJwt;
    if (jwt != null && jwt.isNotEmpty) {
      parts.add('CF_Authorization=$jwt');
    }

    final session = _prefs.sessionCookie;
    if (session != null && session.isNotEmpty) {
      parts.add('sessionid=$session');
    }

    if (parts.isEmpty) return {};
    return {'Cookie': parts.join('; ')};
  }
}

// ---------------------------------------------------------------------------
// Self-signed certificate confirmation dialog
// ---------------------------------------------------------------------------

/// Show a dialog asking the user to accept a self-signed TLS certificate.
///
/// Returns true if the user accepts, false otherwise.
Future<bool> showSelfSignedCertDialog(BuildContext context, String host) async {
  return await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 40),
        title: const Text('Untrusted Certificate'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The server at $host uses a self-signed or untrusted TLS certificate.',
            ),
            const SizedBox(height: 12),
            const Text(
              'This is common for local or development servers, but could '
              'also indicate a security risk.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            const Text(
              'Accept self-signed certificates for this app?',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Refuse'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Accept'),
          ),
        ],
      );
    },
  ) ?? false;
}

// ---------------------------------------------------------------------------
// Password login dialog
// ---------------------------------------------------------------------------

/// Show a dialog prompting the user for the TwiCC password.
///
/// Returns the entered password on submit, or null if cancelled.
Future<String?> showPasswordDialog(BuildContext context) async {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();

  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('TwiCC Password'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              hintText: 'Enter TwiCC password',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Password is required';
              }
              return null;
            },
            onFieldSubmitted: (_) {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogContext).pop(controller.text.trim());
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(dialogContext).pop(controller.text.trim());
              }
            },
            child: const Text('Sign in'),
          ),
        ],
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Cloudflare Access WebView dialog (existing)
// ---------------------------------------------------------------------------

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
