import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:google_sign_in_web/google_sign_in_web.dart';

/// Ensures the web plugin is the active [GoogleSignInPlatform] instance.
///
/// Some release builds have omitted `GoogleSignInPlugin` from
/// `web_plugin_registrant.dart`; without it, `renderButton()` throws a
/// minified type-cast error.
void ensureGoogleSignInWebRegistered() {
  if (GoogleSignInPlatform.instance is GoogleSignInPlugin) return;
  GoogleSignInPlugin.registerWith(webPluginRegistrar);
}
