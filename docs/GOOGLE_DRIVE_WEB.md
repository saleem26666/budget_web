# Google Drive (optional) — Budget Web

Drive sync is **optional**. The app works fully with only on-device storage if the user never signs in.

## Owner setup (once)

1. [Google Cloud Console](https://console.cloud.google.com/) → project  
2. Enable **Google Drive API**  
3. **OAuth consent screen** → External → add your Gmail as **Test user** while status is Testing  
4. **Credentials** → **OAuth client ID** → **Web application**  
5. **Authorized JavaScript origins**:
   - `http://localhost`
   - `http://localhost:7357`
   - `https://YOUR-SITE.netlify.app`  
6. Copy **Client ID** into:
   - `lib/config/google_oauth_config.dart` → `webClientId`
   - `web/index.html` → `google-signin-client_id` meta  
7. Rebuild + redeploy `build/web`

Same Web client as Budget Pro is fine if you add the Netlify origin to it.

## User flow

Settings → Google Drive → Sign in → **Backup to Drive** / **Restore from Drive**

Without sign-in: use Download backup / Import as before.
