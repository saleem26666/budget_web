import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/web_only.dart' as google_web
    if (dart.library.io) 'google_sign_in_web_stub.dart';

import '../app_theme.dart';
import '../services/google_drive_backup_service.dart';
import '../utils/google_sign_in_web_register_stub.dart'
    if (dart.library.html) '../utils/google_sign_in_web_register.dart';

/// Isolated page for the GIS HtmlElementView button.
/// Keeping it out of Settings ListView avoids blank Flutter web screens.
class GoogleConnectScreen extends StatefulWidget {
  const GoogleConnectScreen({super.key});

  @override
  State<GoogleConnectScreen> createState() => _GoogleConnectScreenState();
}

class _GoogleConnectScreenState extends State<GoogleConnectScreen> {
  StreamSubscription<GoogleSignInAuthenticationEvent>? _sub;
  bool _ready = false;
  String? _error;
  Widget? _button;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      ensureGoogleSignInWebRegistered();
      await GoogleDriveBackupService.ensureInitialized();
      final existing = GoogleDriveBackupService.currentUser;
      if (existing != null && mounted) {
        Navigator.of(context).pop(existing);
        return;
      }
      await _sub?.cancel();
      _sub = GoogleSignIn.instance.authenticationEvents.listen(
        (event) {
          if (!mounted) return;
          if (event is GoogleSignInAuthenticationEventSignIn) {
            Navigator.of(context).pop(event.user);
          }
        },
        onError: (e) {
          if (mounted) setState(() => _error = e.toString());
        },
      );
      late final Widget button;
      try {
        button = google_web.renderButton();
      } catch (e) {
        if (mounted) {
          setState(() {
            _ready = false;
            _error = e.toString();
          });
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _button = button;
        _ready = true;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _ready = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect Google')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Optional cloud backup',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in only if you want Google Drive backup. '
                'Your wallet still works fully without Google.',
                style: TextStyle(
                  color: AppTheme.muted.withValues(alpha: 0.95),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 28),
              if (_error != null) ...[
                Text(
                  'Google Sign-In failed to load.\n'
                  'If this keeps happening after a fresh deploy, check Cloud '
                  'Console (Netlify origin + Test user).\n\n'
                  '$_error',
                  style: const TextStyle(color: AppTheme.expense, fontSize: 13),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _ready = false;
                      _button = null;
                    });
                    _boot();
                  },
                  child: const Text('Retry'),
                ),
              ] else if (!_ready || _button == null) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 12),
                const Text(
                  'Loading Google Sign-In…',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.muted),
                ),
              ] else
                Center(
                  child: SizedBox(
                    height: 48,
                    width: 280,
                    child: _button,
                  ),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel — keep local only'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
