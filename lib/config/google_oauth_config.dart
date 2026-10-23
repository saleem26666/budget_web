/// Google Cloud OAuth for Budget Web (browser / PWA).
///
/// Setup (once by app owner):
/// 1. https://console.cloud.google.com/ → enable **Google Drive API**
/// 2. OAuth consent screen (External + your Gmail as test user while Testing)
/// 3. Credentials → OAuth client ID → type **Web application**
/// 4. Authorized JavaScript origins (examples):
///    - http://localhost
///    - http://localhost:7357
///    - https://astounding-pothos-52f6a6.netlify.app
/// 5. Paste Client ID below (and in web/index.html meta tag)
///
/// Drive sync is **optional**. Users who never sign in keep data on-device only.
class GoogleOAuthConfig {
  GoogleOAuthConfig._();

  /// Web OAuth client ID (same project as Budget Pro Web client is OK
  /// if Netlify origin is added to that client).
  static const String webClientId =
      '723684429845-u03ai4pi869mjvpu2e8e2cjmc2rsljdn.apps.googleusercontent.com';

  /// Must see files uploaded by Budget Pro (Android) AND upload our own.
  /// `drive.file` alone cannot list backups created by the other app/client —
  /// that caused Web restore to load an old tiny BudgetWeb_ file instead of
  /// the phone Quick sync (e.g. 383k vs −3k mismatch).
  static const List<String> driveScopes = [
    'https://www.googleapis.com/auth/drive.readonly',
    'https://www.googleapis.com/auth/drive.file',
  ];
}
