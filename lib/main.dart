import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'data/local_store.dart';
import 'screens/wallet_screen.dart';
import 'services/currency_service.dart';
import 'services/google_drive_backup_service.dart';
import 'utils/app_lock_prefs.dart';
import 'utils/google_sign_in_web_register_stub.dart'
    if (dart.library.html) 'utils/google_sign_in_web_register.dart';
import 'widgets/app_lock_gate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ensureGoogleSignInWebRegistered();
  runApp(const BudgetWebApp());
}

class BudgetWebApp extends StatefulWidget {
  const BudgetWebApp({super.key});

  @override
  State<BudgetWebApp> createState() => _BudgetWebAppState();
}

class _BudgetWebAppState extends State<BudgetWebApp> {
  final LocalStore store = LocalStore();
  final CurrencyService currency = CurrencyService.instance;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _boot();
    store.addListener(_onStore);
    currency.addListener(_onStore);
  }

  Future<void> _boot() async {
    await Future.wait([
      store.load(),
      currency.load(),
      AppLockPrefs.isPinSet(),
      GoogleDriveBackupService.ensureInitialized().catchError((_) {}),
    ]);
    if (mounted) setState(() => _ready = true);
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    store.removeListener(_onStore);
    currency.removeListener(_onStore);
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Budget Web',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: _ready && store.loaded
          ? AppLockGate(child: WalletScreen(store: store))
          : const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
    );
  }
}
