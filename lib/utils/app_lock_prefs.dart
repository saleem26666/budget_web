import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App open lock (PIN) — stored as salted SHA-256 hash in this browser only.
class AppLockPrefs {
  static const _hashKey = 'budget_web_lock_hash';
  static const _saltKey = 'budget_web_lock_salt';
  static const _bioKey = 'budget_web_lock_bio';
  static const _credKey = 'budget_web_lock_webauthn_id';

  static Future<bool> isPinSet() async {
    final prefs = await SharedPreferences.getInstance();
    final h = prefs.getString(_hashKey);
    return h != null && h.isNotEmpty;
  }

  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_bioKey) ?? false;
  }

  static Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_bioKey, enabled);
    if (!enabled) await prefs.remove(_credKey);
  }

  static Future<String?> webAuthnCredentialId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_credKey);
  }

  static Future<void> setWebAuthnCredentialId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_credKey, id);
  }

  static String _hash(String pin, String salt) {
    final bytes = utf8.encode('$salt::$pin');
    return sha256.convert(bytes).toString();
  }

  static Future<void> setPin(String pin) async {
    final clean = pin.trim();
    if (clean.length != 4) {
      throw 'PIN must be exactly 4 digits';
    }
    if (!RegExp(r'^\d{4}$').hasMatch(clean)) {
      throw 'PIN must be numbers only';
    }
    final salt = DateTime.now().microsecondsSinceEpoch.toString();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_saltKey, salt);
    await prefs.setString(_hashKey, _hash(clean, salt));
  }

  static Future<bool> verify(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = prefs.getString(_saltKey);
    final expected = prefs.getString(_hashKey);
    if (salt == null || expected == null || expected.isEmpty) return true;
    return _hash(pin.trim(), salt) == expected;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hashKey);
    await prefs.remove(_saltKey);
    await prefs.remove(_bioKey);
    await prefs.remove(_credKey);
  }
}
