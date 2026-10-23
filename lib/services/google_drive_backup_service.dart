import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:intl/intl.dart';

import '../config/google_oauth_config.dart';

/// Optional Google Drive backup. App works fully without signing in.
///
/// Shares the same Drive folder items with Budget Pro Android:
/// looks for BudgetPro_ / BudgetWeb_ / BudgetShared_ backups.
class GoogleDriveBackupService {
  GoogleDriveBackupService._();

  static final GoogleSignIn _gsi = GoogleSignIn.instance;
  static bool _initialized = false;
  static GoogleSignInAccount? _user;
  static StreamSubscription<GoogleSignInAuthenticationEvent>? _sub;

  static GoogleSignInAccount? get currentUser => _user;

  static String get setupHelp =>
      'Google Drive needs OAuth setup:\n'
      '1. Enable Google Drive API\n'
      '2. Web OAuth client + Authorized JavaScript origins '
      '(localhost + your Netlify URL)\n'
      '3. Client ID in google_oauth_config.dart and web/index.html\n'
      '4. Consent screen: add your Gmail as test user if app is Testing';

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    try {
      await _gsi.initialize(clientId: GoogleOAuthConfig.webClientId);
      _sub ??= _gsi.authenticationEvents.listen((event) {
        switch (event) {
          case GoogleSignInAuthenticationEventSignIn(:final user):
            _user = user;
          case GoogleSignInAuthenticationEventSignOut():
            _user = null;
        }
      }, onError: (_) {});
      try {
        await _gsi.attemptLightweightAuthentication();
      } catch (_) {}
      _initialized = true;
    } catch (_) {
      // OAuth / plugin misconfigured — app still works without Drive.
      // Do not mark initialized so a later Connect page can retry after
      // the web plugin is registered.
    }
  }

  static Future<void> disposeListener() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// Interactive sign-in (non-web). On web use [googleSignInButton].
  static Future<GoogleSignInAccount?> signInInteractive() async {
    await ensureInitialized();
    if (kIsWeb && !_gsi.supportsAuthenticate()) {
      throw 'On web, use the Google Sign-In button below.';
    }
    try {
      final account = await _gsi.authenticate();
      _user = account;
      return account;
    } catch (e) {
      final s = e.toString();
      if (s.contains('ClientID') ||
          s.contains('client_id') ||
          s.contains('idpiframe') ||
          s.contains('origin')) {
        throw setupHelp;
      }
      rethrow;
    }
  }

  static Future<void> signOut() async {
    await ensureInitialized();
    await _gsi.signOut();
    _user = null;
  }

  static Future<drive.DriveApi> _api() async {
    await ensureInitialized();
    var user = _user;
    if (user == null) {
      try {
        user = await _gsi.attemptLightweightAuthentication();
      } catch (_) {}
    }
    if (user == null && _gsi.supportsAuthenticate()) {
      user = await _gsi.authenticate();
    }
    if (user == null) {
      throw 'Sign in with Google first (optional — local backup still works).';
    }
    _user = user;

    final auth = await user.authorizationClient.authorizeScopes(
      GoogleOAuthConfig.driveScopes,
    );
    final client = auth.authClient(scopes: GoogleOAuthConfig.driveScopes);
    return drive.DriveApi(client);
  }

  static String timestampedName() {
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    // Shared prefix so Android and Web both find each other's files.
    return 'BudgetShared_Web_$stamp.json';
  }

  static Future<DateTime?> uploadBackup(String jsonContent) async {
    final api = await _api();
    final bytes = utf8.encode(jsonContent);
    final media = drive.Media(
      Stream.value(bytes),
      bytes.length,
      contentType: 'application/json',
    );
    final result = await api.files.create(
      drive.File()
        ..name = timestampedName()
        ..mimeType = 'application/json',
      uploadMedia: media,
    );
    return result.modifiedTime;
  }

  static bool _isBackupName(String? name) {
    if (name == null || name.isEmpty) return false;
    final n = name.toLowerCase();
    final prefix = n.contains('budgetpro_') ||
        n.contains('budgetweb_') ||
        n.contains('budgetshared_');
    if (!prefix) return false;
    return n.contains('.json') ||
        n.contains('.budgetpro') ||
        n.endsWith('.gz');
  }

  static int _backupRank(String? name) {
    final n = (name ?? '').toLowerCase();
    // Prefer phone Budget Pro backups over older browser-only files.
    if (n.contains('budgetpro_')) return 3;
    if (n.contains('budgetshared_')) return 2;
    if (n.contains('budgetweb_')) return 1;
    return 0;
  }

  static Future<List<drive.File>> listBackupFiles() async {
    final api = await _api();
    final list = await api.files.list(
      q: "(name contains 'BudgetPro_' or "
          "name contains 'BudgetWeb_' or "
          "name contains 'BudgetShared_') and trashed = false",
      spaces: 'drive',
      $fields: 'files(id, name, modifiedTime, size)',
      orderBy: 'modifiedTime desc',
      pageSize: 40,
    );
    final files =
        (list.files ?? []).where((f) => _isBackupName(f.name)).toList();
    // Newest first; phone BudgetPro_ wins only on identical timestamps.
    files.sort((a, b) {
      final ta = a.modifiedTime?.millisecondsSinceEpoch ?? 0;
      final tb = b.modifiedTime?.millisecondsSinceEpoch ?? 0;
      if (tb != ta) return tb.compareTo(ta);
      return _backupRank(b.name).compareTo(_backupRank(a.name));
    });
    return files;
  }

  static Future<drive.File?> _findLatest(drive.DriveApi api) async {
    // Prefer newest BudgetPro_ (phone). Fall back to any shared backup.
    final files = await listBackupFiles();
    if (files.isEmpty) return null;
    final pro = files.where((f) {
      final n = (f.name ?? '').toLowerCase();
      return n.contains('budgetpro_');
    });
    if (pro.isNotEmpty) return pro.first;
    return files.first;
  }

  static bool _looksGzip(Uint8List bytes) =>
      bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;

  static Future<({String json, String fileName, DateTime? modified})>
      _downloadFile(drive.File file) async {
    final api = await _api();
    final fileName = file.name ?? 'backup';
    final media = await api.files.get(
      file.id!,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final chunks = <int>[];
    await for (final chunk in media.stream) {
      chunks.addAll(chunk);
    }
    var bytes = Uint8List.fromList(chunks);
    if (_looksGzip(bytes) || fileName.toLowerCase().endsWith('.gz')) {
      // Force Dart/web inflater — more reliable for large Drive backups.
      try {
        bytes = Uint8List.fromList(
            const GZipDecoderWeb().decodeBytes(bytes, verify: true));
      } catch (_) {
        bytes = Uint8List.fromList(const GZipDecoderWeb().decodeBytes(bytes));
      }
    }
    final text = utf8.decode(bytes);
    if (!text.trimLeft().startsWith('{')) {
      throw 'Backup download looked corrupt (not JSON).\n'
          'File: $fileName\n'
          'Phone pe Quick sync (no pictures) dubara karein.';
    }
    return (
      json: text,
      fileName: fileName,
      modified: file.modifiedTime,
    );
  }

  /// Downloads latest phone BudgetPro_ backup (falls back to other shared files).
  static Future<({String json, String fileName, DateTime? modified})>
      downloadLatestBackup() async {
    final api = await _api();
    final file = await _findLatest(api);
    if (file?.id == null) {
      throw 'No shared backup on Google Drive yet.\n'
          'On phone: Settings → Quick sync.\n'
          'Then Sign out Google here → Connect again (allow Drive) → Restore.';
    }
    return _downloadFile(file!);
  }

  /// Download a specific Drive file by id (user picked from list).
  static Future<({String json, String fileName, DateTime? modified})>
      downloadBackupById(String fileId, {String? name, DateTime? modified}) async {
    final api = await _api();
    final meta = await api.files.get(
      fileId,
      $fields: 'id,name,modifiedTime',
    ) as drive.File;
    return _downloadFile(meta);
  }
}
