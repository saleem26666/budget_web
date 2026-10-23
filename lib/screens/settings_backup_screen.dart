import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../data/budget_pro_import.dart';
import '../data/local_store.dart';
import '../models/models.dart';
import '../services/backup_share.dart';
import '../services/currency_service.dart';
import '../services/google_drive_backup_service.dart';
import '../services/report_pdf_service.dart';
import '../utils/app_lock_biometric.dart';
import '../utils/app_lock_prefs.dart';
import 'google_connect_screen.dart';
import 'reports_screen.dart';

class SettingsBackupScreen extends StatefulWidget {
  final LocalStore store;

  const SettingsBackupScreen({super.key, required this.store});

  @override
  State<SettingsBackupScreen> createState() => _SettingsBackupScreenState();
}

class _SettingsBackupScreenState extends State<SettingsBackupScreen> {
  LocalStore get store => widget.store;
  bool _busy = false;
  bool _pinSet = false;
  bool _bioOn = false;
  bool _bioDeviceOk = false;
  GoogleSignInAccount? _googleUser;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _googleSub;

  @override
  void initState() {
    super.initState();
    _refreshLockState();
    _listenGoogle();
  }

  Future<void> _listenGoogle() async {
    try {
      await GoogleDriveBackupService.ensureInitialized();
      if (!mounted) return;
      setState(() => _googleUser = GoogleDriveBackupService.currentUser);
      _googleSub = GoogleSignIn.instance.authenticationEvents.listen(
        (event) {
          if (!mounted) return;
          setState(() {
            switch (event) {
              case GoogleSignInAuthenticationEventSignIn(:final user):
                _googleUser = user;
              case GoogleSignInAuthenticationEventSignOut():
                _googleUser = null;
            }
          });
        },
        onError: (_) {},
      );
    } catch (_) {
      // Google optional — Settings must still render.
    }
  }

  Future<void> _openGoogleConnect() async {
    final user = await Navigator.of(context).push<GoogleSignInAccount>(
      MaterialPageRoute(builder: (_) => const GoogleConnectScreen()),
    );
    if (!mounted) return;
    if (user != null) {
      setState(() => _googleUser = user);
      _toast('Signed in: ${user.email}');
    } else {
      setState(() => _googleUser = GoogleDriveBackupService.currentUser);
    }
  }

  @override
  void dispose() {
    _googleSub?.cancel();
    super.dispose();
  }

  Future<void> _refreshLockState() async {
    try {
      final pin = await AppLockPrefs.isPinSet();
      final bio = await AppLockPrefs.isBiometricEnabled();
      var device = false;
      try {
        device = await AppLockBiometric.isAvailable();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _pinSet = pin;
        _bioOn = bio;
        _bioDeviceOk = device;
      });
    } catch (_) {}
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      await BackupShare.exportJson(
        store.exportJson(),
        fileName: 'BudgetWeb_$stamp.json',
      );
      _toast('Backup downloaded');
    } catch (e) {
      _toast('Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      await BackupShare.shareText(
        store.exportJson(),
        subject: 'Budget Web backup',
      );
    } catch (e) {
      _toast('Share failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyBackupRaw(
    String raw, {
    required String successPrefix,
    String? driveFileName,
  }) async {
    late final ({
      List<ImportedProfile> profiles,
      String? preferredProfileId,
      String sourceLabel,
    }) all;
    try {
      all = BudgetProImport.parseAll(raw);
    } catch (e) {
      _toast('$e');
      return;
    }

    final n = all.profiles.length;
    final txCount =
        all.profiles.fold<int>(0, (s, p) => s + p.transactions.length);
    final accCount =
        all.profiles.fold<int>(0, (s, p) => s + p.accounts.length);
    final fileLine = (driveFileName != null && driveFileName.isNotEmpty)
        ? 'Drive file: $driveFileName\n\n'
        : '';
    final balLines = all.profiles.map((p) {
      final b = BudgetProImport.previewBalance(p);
      return '• ${p.name}: ${b.toStringAsFixed(0)} '
          '(${p.accounts.length} acc · ${p.transactions.length} tx)';
    }).join('\n');

    final looksLikePhoneMiss = driveFileName != null &&
        !driveFileName.toLowerCase().contains('budgetpro_');
    if (looksLikePhoneMiss && mounted) {
      final cont = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Not a phone BudgetPro_ file'),
          content: Text(
            '$fileLine'
            'Balances in this file:\n$balLines\n\n'
            'Phone Quick sync files start with BudgetPro_.\n'
            '1) Phone → Quick sync again\n'
            '2) Restore and pick the newest BudgetPro_ file\n'
            'Or Import a .budgetpro from the phone.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Import anyway')),
          ],
        ),
      );
      if (cont != true) return;
    }

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(n > 1 ? 'Import all $n profiles?' : 'Replace wallet data?'),
        content: SingleChildScrollView(
          child: Text(
            '$fileLine'
            'From ${all.sourceLabel}.\n\n'
            'Balances (should match phone):\n$balLines\n\n'
            '$n profile(s) · $accCount accounts · $txCount txs.\n\n'
            'If july2026 is not ~382655, cancel and pick another Drive file.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(n > 1 ? 'Import all' : 'Replace'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await store.replaceAllProfiles(
        imported: all.profiles,
        preferredProfileId: all.preferredProfileId,
      );
      final tip = driveFileName != null ? ' · $driveFileName' : '';
      _toast('$successPrefix · ${all.sourceLabel}$tip');
    } catch (e) {
      _toast('Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final raw = await BackupShare.pickBackupText();
    if (raw == null) return;
    await _applyBackupRaw(raw, successPrefix: 'Imported');
  }

  Future<void> _switchProfile() async {
    if (store.profiles.isEmpty) return;
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text('Switch profile',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            ...store.profiles.map(
              (p) => ListTile(
                leading: Icon(
                  p.id == store.activeProfileId
                      ? Icons.check_circle
                      : Icons.person_outline,
                  color: p.id == store.activeProfileId
                      ? AppTheme.primary
                      : AppTheme.muted,
                ),
                title: Text(p.name,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${p.accounts.length} accounts · ${p.transactions.length} txs',
                  style: const TextStyle(fontSize: 12.5),
                ),
                onTap: () => Navigator.pop(ctx, p.id),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (id == null) return;
    await store.switchProfile(id);
    setState(() {});
    _toast('Switched to ${store.activeProfileName}');
  }

  Future<void> _addProfile() async {
    final c = TextEditingController();
    var copyAccounts = store.profiles.isNotEmpty;
    var copyCategories = true;
    var sourceId = store.activeProfileId;
    final now = DateTime.now();
    var asOf = now.month == 1
        ? DateTime(now.year - 1, 12, 31)
        : DateTime(now.year, now.month, 0);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('New profile'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: c,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Profile name',
                    hintText: 'e.g. Oct 2026',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Copy old accounts?'),
                  subtitle: const Text(
                    'New month: opening = closing as of a date',
                  ),
                  value: copyAccounts,
                  onChanged: (v) => setLocal(() => copyAccounts = v),
                ),
                if (copyAccounts) ...[
                  DropdownButtonFormField<String>(
                    initialValue: store.profiles.any((p) => p.id == sourceId)
                        ? sourceId
                        : store.profiles.first.id,
                    items: store.profiles
                        .map((p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(p.name),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setLocal(() => sourceId = v);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Copy from profile',
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Balances as of'),
                    subtitle: Text(DateFormat('EEE, d MMM yyyy').format(asOf)),
                    trailing: const Icon(Icons.edit_calendar_outlined),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: asOf,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (d != null) setLocal(() => asOf = d);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Copy categories too'),
                    value: copyCategories,
                    onChanged: (v) => setLocal(() => copyCategories = v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final name = c.text.trim();
    if (name.isEmpty) return;
    if (copyAccounts) {
      await store.addProfileFromSource(
        name: name,
        sourceId: sourceId,
        asOf: asOf,
        copyCategories: copyCategories,
      );
    } else {
      await store.addEmptyProfile(name);
    }
    setState(() {});
    _toast('Profile added · ${store.activeProfileName}');
  }

  Future<void> _exportStatement() async {
    if (store.accounts.isEmpty) {
      _toast('Add an account first');
      return;
    }
    final account = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final h = MediaQuery.sizeOf(ctx).height * 0.55;
        return AlertDialog(
          title: const Text('Statement for account'),
          content: SizedBox(
            width: double.maxFinite,
            height: h,
            child: ListView.builder(
              itemCount: store.accounts.length,
              itemBuilder: (_, i) {
                final a = store.accounts[i];
                return ListTile(
                  title: Text(a.name),
                  onTap: () => Navigator.pop(ctx, a.name),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
    if (account == null || !mounted) return;

    // Same readable PDF as Reports (Opening / In / Out / Closing + table).
    final now = DateTime.now();
    final from = DateTime(2000, 1, 1);
    final to = DateTime(now.year, now.month, now.day);
    try {
      setState(() => _busy = true);
      final report = store.reportForAccount(
        accountName: account,
        from: from,
        to: to,
      );
      final bytes = await ReportPdfService.buildAccountPdf(report);
      final stamp = DateFormat('yyyyMMdd').format(now);
      final safe = account.replaceAll(RegExp(r'[^\w\-]+'), '_');
      await BackupShare.downloadBytes(
        bytes,
        fileName: 'BudgetWeb_${safe}_$stamp.pdf',
        mime: 'application/pdf',
      );
      _toast('PDF statement downloaded');
    } catch (e) {
      _toast('Statement failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickCurrency() async {
    final cur = CurrencyService.instance;
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Default currency'),
        children: CurrencyService.currencies
            .map(
              (c) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, c.code),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      child: Text(c.symbol,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    Expanded(child: Text(c.label)),
                    if (c.code == cur.code)
                      const Icon(Icons.check, color: AppTheme.primary, size: 20),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
    if (code != null) {
      await cur.setCurrency(code);
      setState(() {});
      _toast('Currency: $code');
    }
  }

  Future<String?> _askPin(String title, {String? subtitle}) async {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (subtitle != null) ...[
              Text(subtitle, style: const TextStyle(color: AppTheme.muted)),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '4-digit PIN',
                counterText: '',
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _setOrChangePin() async {
    if (_pinSet) {
      final current = await _askPin('Current PIN');
      if (current == null) return;
      if (!await AppLockPrefs.verify(current)) {
        _toast('Wrong PIN');
        return;
      }
    }
    final next = await _askPin('New PIN',
        subtitle: 'App will ask this PIN when you open Budget Web.');
    if (next == null) return;
    final confirm = await _askPin('Confirm PIN');
    if (confirm == null) return;
    if (next != confirm) {
      _toast('PINs do not match');
      return;
    }
    try {
      await AppLockPrefs.setPin(next);
      await _refreshLockState();
      _toast('App lock PIN saved');
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _removePin() async {
    if (!_pinSet) return;
    final current = await _askPin('Enter PIN to remove lock');
    if (current == null) return;
    if (!await AppLockPrefs.verify(current)) {
      _toast('Wrong PIN');
      return;
    }
    await AppLockPrefs.clear();
    await _refreshLockState();
    _toast('App lock removed');
  }

  Future<void> _toggleBiometric() async {
    if (!_pinSet) {
      _toast('Set a PIN first');
      return;
    }
    if (_bioOn) {
      await AppLockPrefs.setBiometricEnabled(false);
      await _refreshLockState();
      _toast('Fingerprint / Face unlock off');
      return;
    }
    if (!_bioDeviceOk) {
      _toast(
          'This browser/device has no fingerprint / Face ID for websites. PIN still works.');
      return;
    }
    final pin = await _askPin('Confirm PIN to enable biometrics');
    if (pin == null) return;
    if (!await AppLockPrefs.verify(pin)) {
      _toast('Wrong PIN');
      return;
    }
    final ok = await AppLockBiometric.enroll();
    await _refreshLockState();
    _toast(ok
        ? 'Fingerprint / Face unlock enabled'
        : 'Could not enable biometrics — use PIN');
  }

  Future<void> _driveSignInNative() async {
    setState(() => _busy = true);
    try {
      final u = await GoogleDriveBackupService.signInInteractive();
      setState(() => _googleUser = u ?? GoogleDriveBackupService.currentUser);
      _toast(u == null ? 'Sign-in cancelled' : 'Signed in: ${u.email}');
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _driveSignOut() async {
    await GoogleDriveBackupService.signOut();
    setState(() => _googleUser = null);
    _toast('Google signed out — local data unchanged');
  }

  Future<void> _driveUpload() async {
    setState(() => _busy = true);
    try {
      final when =
          await GoogleDriveBackupService.uploadBackup(store.exportJson());
      _toast(when == null
          ? 'Backup uploaded to Google Drive'
          : 'Drive backup saved · $when');
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _driveRestore() async {
    setState(() => _busy = true);
    try {
      final files = await GoogleDriveBackupService.listBackupFiles();
      if (!mounted) return;
      setState(() => _busy = false);
      if (files.isEmpty) {
        _toast('No backups on Drive. Phone → Quick sync first.');
        return;
      }

      final picked = await showModalBottomSheet<drive.File>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) {
          final h = MediaQuery.sizeOf(ctx).height * 0.55;
          return SizedBox(
            height: h,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    'Choose Drive backup',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Pick newest BudgetPro_… (phone Quick sync)',
                    style: TextStyle(color: AppTheme.muted, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: files.length,
                    itemBuilder: (_, i) {
                      final f = files[i];
                      final name = f.name ?? 'backup';
                      final when = f.modifiedTime?.toLocal().toString() ?? '';
                      final isPro =
                          name.toLowerCase().contains('budgetpro_');
                      return ListTile(
                        leading: Icon(
                          isPro ? Icons.phone_android : Icons.web,
                          color: isPro ? AppTheme.primary : AppTheme.muted,
                        ),
                        title: Text(name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(when,
                            style: const TextStyle(fontSize: 12)),
                        onTap: () => Navigator.pop(ctx, f),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
      if (picked?.id == null) return;

      setState(() => _busy = true);
      final got = await GoogleDriveBackupService.downloadBackupById(
        picked!.id!,
        name: picked.name,
        modified: picked.modifiedTime,
      );
      if (mounted) setState(() => _busy = false);
      await _applyBackupRaw(
        got.json,
        successPrefix: 'Restored from Drive',
        driveFileName: got.fileName,
      );
    } catch (e) {
      _toast('$e');
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editAccount(Account a, void Function(void Function()) setLocal) async {
    final nameC = TextEditingController(text: a.name);
    final balC = TextEditingController(
        text: a.initialBalance.toStringAsFixed(
            a.initialBalance % 1 == 0 ? 0 : 2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Edit account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameC,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: balC,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Opening balance'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && nameC.text.trim().isNotEmpty) {
      await store.updateAccount(
        Account(
          id: a.id,
          name: nameC.text.trim(),
          initialBalance: double.tryParse(balC.text.trim()) ?? 0,
        ),
        oldName: a.name,
      );
      setLocal(() {});
    }
  }

  Future<void> _editCategory(Category c, void Function(void Function()) setLocal) async {
    final nameC = TextEditingController(text: c.name);
    final budgetC = TextEditingController(
        text: c.budget == null
            ? ''
            : c.budget!.toStringAsFixed(c.budget! % 1 == 0 ? 0 : 2));
    final subsC = TextEditingController(text: c.subCategories.join(', '));
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Edit category'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameC,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: budgetC,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Monthly budget (optional)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: subsC,
                decoration: const InputDecoration(
                  labelText: 'Sub-categories',
                  hintText: 'Lunch, Dinner, Snacks',
                  helperText: 'Comma-separated',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && nameC.text.trim().isNotEmpty) {
      final budgetRaw = budgetC.text.trim();
      final subs = subsC.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      await store.updateCategory(Category(
        id: c.id,
        name: nameC.text.trim(),
        budget: budgetRaw.isEmpty ? null : double.tryParse(budgetRaw),
        subCategories: subs,
      ));
      setLocal(() {});
    }
  }

  Future<void> _manageAccounts() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final money = CurrencyService.instance;
            final maxH = MediaQuery.sizeOf(ctx).height * 0.85;
            return SizedBox(
              height: maxH,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Accounts',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Scroll for more · Add account below',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.muted.withValues(alpha: 0.95),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.builder(
                        itemCount: store.accounts.length,
                        itemBuilder: (_, i) {
                          final a = store.accounts[i];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(a.name),
                            subtitle: Text(
                                'Opening: ${money.format(a.initialBalance)}'),
                            onTap: () => _editAccount(a, setLocal),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _editAccount(a, setLocal),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: AppTheme.expense),
                                  onPressed: store.accounts.length <= 1
                                      ? null
                                      : () async {
                                          await store.deleteAccount(a.id);
                                          setLocal(() {});
                                        },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () async {
                        final nameC = TextEditingController();
                        final balC = TextEditingController(text: '0');
                        final ok = await showDialog<bool>(
                          context: ctx,
                          builder: (d) => AlertDialog(
                            title: const Text('New account'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextField(
                                  controller: nameC,
                                  decoration: const InputDecoration(
                                      labelText: 'Name'),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: balC,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText: 'Opening balance'),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(d, false),
                                  child: const Text('Cancel')),
                              FilledButton(
                                  onPressed: () => Navigator.pop(d, true),
                                  child: const Text('Add')),
                            ],
                          ),
                        );
                        if (ok == true && nameC.text.trim().isNotEmpty) {
                          await store.addAccount(
                            nameC.text.trim(),
                            double.tryParse(balC.text.trim()) ?? 0,
                          );
                          setLocal(() {});
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add account'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    setState(() {});
  }

  Future<void> _manageCategories() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final money = CurrencyService.instance;
            final day = DateTime.now();
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Categories',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: ListView(
                      shrinkWrap: true,
                      children: store.categories.map((c) {
                        final spent =
                            store.categorySpentInMonth(c.name, day);
                        final budget = c.budget;
                        String sub = '';
                        if (budget != null && budget > 0) {
                          sub =
                              'Spent ${money.format(spent)} / ${money.format(budget)}';
                        } else if (c.subCategories.isNotEmpty) {
                          sub = c.subCategories.join(', ');
                        }
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(c.name),
                          subtitle: sub.isEmpty ? null : Text(sub),
                          onTap: () => _editCategory(c, setLocal),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _editCategory(c, setLocal),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: AppTheme.expense),
                                onPressed: store.categories.length <= 1
                                    ? null
                                    : () async {
                                        await store.deleteCategory(c.id);
                                        setLocal(() {});
                                      },
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () async {
                      final nameC = TextEditingController();
                      final budgetC = TextEditingController();
                      final subsC = TextEditingController();
                      final ok = await showDialog<bool>(
                        context: ctx,
                        builder: (d) => AlertDialog(
                          title: const Text('New category'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(
                                controller: nameC,
                                autofocus: true,
                                decoration:
                                    const InputDecoration(labelText: 'Name'),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: budgetC,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: 'Monthly budget (optional)'),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: subsC,
                                decoration: const InputDecoration(
                                  labelText: 'Sub-categories',
                                  hintText: 'A, B, C',
                                ),
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(d, false),
                                child: const Text('Cancel')),
                            FilledButton(
                                onPressed: () => Navigator.pop(d, true),
                                child: const Text('Add')),
                          ],
                        ),
                      );
                      if (ok == true && nameC.text.trim().isNotEmpty) {
                        final budgetRaw = budgetC.text.trim();
                        final subs = subsC.text
                            .split(',')
                            .map((e) => e.trim())
                            .where((e) => e.isNotEmpty)
                            .toList();
                        await store.addCategory(
                          nameC.text.trim(),
                          budget: budgetRaw.isEmpty
                              ? null
                              : double.tryParse(budgetRaw),
                          subs: subs,
                        );
                        setLocal(() {});
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add category'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    setState(() {});
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset wallet?'),
        content: const Text(
          'Deletes all transactions and restores default Cash/Bank accounts. Export a backup first if you need it.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true) {
      await store.clearAll();
      _toast('Wallet reset');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings & backup')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          _section('Profiles'),
          _tile(
            Icons.switch_account_outlined,
            'Active: ${store.activeProfileName}',
            store.profiles.length <= 1
                ? '1 profile · restore from phone to sync all'
                : '${store.profiles.length} profiles · tap to switch',
            _switchProfile,
          ),
          _tile(
            Icons.person_add_alt_1_outlined,
            'Add empty profile',
            'New blank wallet on this browser',
            _addProfile,
          ),
          const SizedBox(height: 8),
          _section('Wallet'),
          _tile(
            Icons.currency_exchange,
            'Default currency',
            CurrencyService.instance.current.label,
            _pickCurrency,
          ),
          _tile(
            Icons.assessment_outlined,
            'Reports & PDF',
            'Account history by date · download PDF',
            () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReportsScreen(store: store),
                ),
              );
            },
          ),
          _tile(
            Icons.account_balance_wallet_outlined,
            'Accounts',
            '${store.accounts.length} accounts · tap to edit',
            _manageAccounts,
          ),
          _tile(
            Icons.category_outlined,
            'Categories',
            '${store.categories.length} · budget & sub-categories',
            _manageCategories,
          ),
          const SizedBox(height: 8),
          _section('Security'),
          _tile(
            Icons.lock_outline,
            _pinSet ? 'Change app PIN' : 'Set app PIN',
            _pinSet
                ? 'PIN required when opening this app'
                : 'Lock Budget Web on this device/browser',
            _setOrChangePin,
          ),
          if (_pinSet)
            _tile(
              Icons.fingerprint,
              'Fingerprint / Face unlock',
              _bioOn
                  ? 'On · tap to turn off'
                  : (_bioDeviceOk
                      ? 'Off · tap to enable (after PIN)'
                      : 'Not available in this browser — PIN only'),
              _toggleBiometric,
            ),
          if (_pinSet)
            _tile(
              Icons.lock_open_outlined,
              'Remove app lock',
              'Open without PIN on this browser',
              _removePin,
              danger: true,
            ),
          const SizedBox(height: 8),
          _section('Google Drive (optional)'),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Sync: Phone Quick sync → here Sign out Google → Connect again '
              '(allow “See your Drive files”) → Restore. '
              'Must see BudgetPro_… file (not old BudgetWeb_). '
              'File Import also works without Google.',
              style: TextStyle(
                color: AppTheme.muted.withValues(alpha: 0.95),
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
          if (_googleUser != null) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cloud_done_outlined,
                  color: AppTheme.primary),
              title: Text(_googleUser!.email,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Signed in · Drive sync available',
                  style: TextStyle(color: AppTheme.muted, fontSize: 12.5)),
            ),
            const SizedBox(height: 8),
            _tile(
              Icons.cloud_upload_outlined,
              'Backup to Google Drive',
              'Upload shared backup (phone + browser can use)',
              _driveUpload,
            ),
            _tile(
              Icons.cloud_download_outlined,
              'Restore from Google Drive',
              'Phone backup → all profiles sync here',
              _driveRestore,
            ),
            _tile(
              Icons.logout,
              'Sign out of Google',
              'Does not delete local or Drive files',
              _driveSignOut,
            ),
          ] else ...[
            _tile(
              Icons.login,
              'Connect Google (optional)',
              kIsWeb
                  ? 'Opens Google sign-in on a separate page'
                  : 'Optional cloud backup',
              kIsWeb ? _openGoogleConnect : _driveSignInNative,
            ),
            _tile(
              Icons.info_outline,
              'Drive setup (owner)',
              'Add Netlify origin in Cloud Console · Test user = your Gmail',
              () => _toast(GoogleDriveBackupService.setupHelp),
            ),
          ],
          const SizedBox(height: 8),
          _section('Backup'),
          _tile(
            Icons.download_outlined,
            'Download backup',
            'JSON file for this browser',
            _export,
          ),
          _tile(
            Icons.ios_share_outlined,
            'Share backup',
            'Use system share when available',
            _share,
          ),
          _tile(
            Icons.upload_file_outlined,
            'Import Budget Pro / JSON',
            'Wallet tables only · replaces local data',
            _import,
          ),
          _tile(
            Icons.description_outlined,
            'Account statement',
            'PDF: Opening / In / Out / Closing + Description',
            _exportStatement,
          ),
          const SizedBox(height: 8),
          _section('Danger zone'),
          _tile(
            Icons.delete_forever_outlined,
            'Reset wallet',
            'Clear all transactions',
            _clear,
            danger: true,
          ),
          const SizedBox(height: 24),
          Text(
            'Data stays in this browser’s local storage. '
            'Export regularly. Import accepts Budget Pro .budgetpro / .json '
            '(accounts, categories, transactions only).',
            style: TextStyle(
              color: AppTheme.muted.withValues(alpha: 0.9),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        child: Text(
          t.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: AppTheme.muted,
          ),
        ),
      );

  Widget _tile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _busy ? null : onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: AppTheme.listTile(),
            child: Row(
              children: [
                Icon(icon,
                    color: danger ? AppTheme.expense : AppTheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: danger ? AppTheme.expense : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppTheme.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
