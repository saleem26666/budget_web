import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web/web.dart' as web;

import 'app_lock_prefs.dart';

/// Device biometrics on web via WebAuthn (Windows Hello / Touch ID / fingerprint).
/// Many mobile browsers do not expose this to websites — PIN always works.
class AppLockBiometric {
  static Future<bool> isAvailable() async {
    if (!kIsWeb) return false;
    try {
      final result = await web.PublicKeyCredential
          .isUserVerifyingPlatformAuthenticatorAvailable()
          .toDart;
      return result.toDart;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> canUse() async {
    if (!await AppLockPrefs.isBiometricEnabled()) return false;
    if (!await isAvailable()) return false;
    final id = await AppLockPrefs.webAuthnCredentialId();
    return id != null && id.isNotEmpty;
  }

  static JSUint8Array _randomJs(int n) {
    final data = Uint8List(n);
    web.window.crypto.getRandomValues(data.toJS);
    return data.toJS;
  }

  static Future<bool> enroll() async {
    if (!await isAvailable()) return false;
    try {
      final userId = _randomJs(16);
      final challenge = _randomJs(32);
      final params = <web.PublicKeyCredentialParameters>[
        web.PublicKeyCredentialParameters(type: 'public-key', alg: -7),
        web.PublicKeyCredentialParameters(type: 'public-key', alg: -257),
      ];
      final cred = await web.window.navigator.credentials
          .create(
            web.CredentialCreationOptions(
              publicKey: web.PublicKeyCredentialCreationOptions(
                challenge: challenge,
                rp: web.PublicKeyCredentialRpEntity(
                  name: 'Budget Web',
                  id: web.window.location.hostname,
                ),
                user: web.PublicKeyCredentialUserEntity(
                  id: userId,
                  name: 'budget_web',
                  displayName: 'Budget Web',
                ),
                pubKeyCredParams: params.toJS,
                authenticatorSelection: web.AuthenticatorSelectionCriteria(
                  authenticatorAttachment: 'platform',
                  userVerification: 'required',
                  residentKey: 'preferred',
                ),
                timeout: 60000,
              ),
            ),
          )
          .toDart;
      if (cred == null) return false;
      final pk = cred as web.PublicKeyCredential;
      final id = pk.id;
      if (id.isEmpty) return false;
      await AppLockPrefs.setWebAuthnCredentialId(id);
      await AppLockPrefs.setBiometricEnabled(true);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate({
    String reason = 'Unlock Budget Web',
  }) async {
    if (!await canUse()) return false;
    try {
      final id = await AppLockPrefs.webAuthnCredentialId();
      if (id == null || id.isEmpty) return false;
      final allow = [
        web.PublicKeyCredentialDescriptor(
          type: 'public-key',
          id: _credentialIdToBuffer(id),
        ),
      ];
      final cred = await web.window.navigator.credentials
          .get(
            web.CredentialRequestOptions(
              publicKey: web.PublicKeyCredentialRequestOptions(
                challenge: _randomJs(32),
                timeout: 60000,
                userVerification: 'required',
                allowCredentials: allow.toJS,
              ),
            ),
          )
          .toDart;
      return cred != null;
    } catch (_) {
      return false;
    }
  }

  static web.BufferSource _credentialIdToBuffer(String id) {
    // Credential.id is base64url.
    var s = id.replaceAll('-', '+').replaceAll('_', '/');
    while (s.length % 4 != 0) {
      s += '=';
    }
    final binary = web.window.atob(s);
    final bytes = Uint8List(binary.length);
    for (var i = 0; i < binary.length; i++) {
      bytes[i] = binary.codeUnitAt(i);
    }
    return bytes.toJS;
  }
}
