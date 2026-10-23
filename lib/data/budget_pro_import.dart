import 'dart:convert';

/// One wallet profile extracted from a Budget Pro / Budget Web backup.
class ImportedProfile {
  final String id;
  final String name;
  final String? currencyCode;
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> transactions;
  /// Phone-computed total embedded in newer backups (authoritative check).
  final double? walletTotal;

  const ImportedProfile({
    required this.id,
    required this.name,
    required this.accounts,
    required this.categories,
    required this.transactions,
    this.currencyCode,
    this.walletTotal,
  });
}

/// Parses Budget Pro `.budgetpro` / JSON and extracts wallet tables only.
class BudgetProImport {
  static Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  static List<Map<String, dynamic>> _asList(dynamic v) {
    if (v is! List) return [];
    return v
        .map((e) => _asMap(e))
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  static String _profileId(Map<String, dynamic> p) =>
      (p['profile_id'] ?? p['id'] ?? '').toString();

  static String _profileName(Map<String, dynamic> p) =>
      (p['profile_name'] ?? p['name'] ?? _profileId(p)).toString();

  /// All wallet profiles in a backup (1 item for single-profile files).
  static ({
    List<ImportedProfile> profiles,
    String? preferredProfileId,
    String sourceLabel,
  }) parseAll(String raw) {
    final decoded = jsonDecode(raw);
    final root = _asMap(decoded);
    if (root == null) throw 'Invalid backup file';

    final scope = root['backup_scope']?.toString();

    // Multi-profile (Budget Pro phone, or Budget Web all_profiles export)
    if (scope == 'all_profiles' ||
        (root['app']?.toString() == 'budget_web' &&
            root['profiles'] is List)) {
      final list = _asList(root['profiles']);
      if (list.isEmpty) throw 'No profiles in backup';
      final profiles = <ImportedProfile>[];
      for (final p in list) {
        var id = _profileId(p);
        if (id.isEmpty) id = 'p${profiles.length + 1}';
        final name = _profileName(p);
        final embedded = p['wallet_total'];
        profiles.add(ImportedProfile(
          id: id,
          name: name.isEmpty ? id : name,
          currencyCode: p['currency_code']?.toString() ??
              root['currency_code']?.toString(),
          accounts: _asList(p['accounts']),
          categories: _asList(p['categories']),
          transactions: _asList(p['transactions']),
          walletTotal: embedded is num ? embedded.toDouble() : null,
        ));
      }
      final prefer = root['last_used_profile_id']?.toString() ??
          root['active_profile_id']?.toString() ??
          root['vault_home_profile_id']?.toString();
      return (
        profiles: profiles,
        preferredProfileId: prefer,
        sourceLabel: 'Budget Pro · ${profiles.length} profiles',
      );
    }

    // Native single-wallet Budget Web backup
    if (root['app']?.toString() == 'budget_web' ||
        scope == 'wallet_only') {
      final embedded = root['wallet_total'];
      return (
        profiles: [
          ImportedProfile(
            id: root['profile_id']?.toString() ?? 'web_main',
            name: root['profile_name']?.toString() ?? 'Personal',
            currencyCode: root['currency_code']?.toString(),
            accounts: _asList(root['accounts']),
            categories: _asList(root['categories']),
            transactions: _asList(root['transactions']),
            walletTotal: embedded is num ? embedded.toDouble() : null,
          ),
        ],
        preferredProfileId: null,
        sourceLabel: 'Budget Web backup',
      );
    }

    // single_profile or legacy flat
    if (root.containsKey('accounts') || root.containsKey('transactions')) {
      final id = root['profile_id']?.toString() ?? 'imported';
      final label = root['profile_name']?.toString();
      final embedded = root['wallet_total'];
      return (
        profiles: [
          ImportedProfile(
            id: id.isEmpty ? 'imported' : id,
            name: (label != null && label.isNotEmpty) ? label : 'Personal',
            currencyCode: root['currency_code']?.toString(),
            accounts: _asList(root['accounts']),
            categories: _asList(root['categories']),
            transactions: _asList(root['transactions']),
            walletTotal: embedded is num ? embedded.toDouble() : null,
          ),
        ],
        preferredProfileId: null,
        sourceLabel: label != null && label.isNotEmpty
            ? 'Budget Pro · $label'
            : 'Budget Pro backup',
      );
    }

    throw 'No wallet data found in this file';
  }

  /// Returns wallet payload for one profile (preferred / active / first).
  static ({
    List<Map<String, dynamic>> accounts,
    List<Map<String, dynamic>> categories,
    List<Map<String, dynamic>> transactions,
    String sourceLabel,
    String? currencyCode,
  }) parse(String raw, {String? preferredProfileId}) {
    final all = parseAll(raw);
    ImportedProfile chosen = all.profiles.first;
    final prefer = preferredProfileId ?? all.preferredProfileId;
    if (prefer != null && prefer.isNotEmpty) {
      chosen = all.profiles.firstWhere(
        (p) => p.id == prefer,
        orElse: () => all.profiles.first,
      );
    }
    return (
      accounts: chosen.accounts,
      categories: chosen.categories,
      transactions: chosen.transactions,
      sourceLabel: all.profiles.length > 1
          ? 'Budget Pro · ${chosen.name}'
          : all.sourceLabel,
      currencyCode: chosen.currencyCode,
    );
  }

  /// Profile names for all_profiles backups (for picker UI).
  static List<Map<String, String>> listProfiles(String raw) {
    try {
      return parseAll(raw)
          .profiles
          .map((p) => {'id': p.id, 'name': p.name})
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Prefer phone-embedded [walletTotal] when present (matches Android UI).
  static double previewBalance(ImportedProfile p) {
    if (p.walletTotal != null) return p.walletTotal!;
    double initial = 0;
    final seen = <String, double>{};
    for (final a in p.accounts) {
      final name = (a['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final open = (a['initial_balance'] is num)
          ? (a['initial_balance'] as num).toDouble()
          : double.tryParse(
                  '${a['initial_balance'] ?? a['initialBalance'] ?? 0}'
                      .replaceAll(',', '')) ??
              0;
      seen[name] = open; // last wins
    }
    for (final v in seen.values) {
      initial += v;
    }
    double income = 0, expense = 0;
    for (final t in p.transactions) {
      final type = (t['type'] ?? '').toString().trim().toLowerCase();
      final amt = (t['amount'] is num)
          ? (t['amount'] as num).toDouble()
          : double.tryParse('${t['amount'] ?? 0}'.replaceAll(',', '')) ?? 0;
      if (type == 'income') {
        income += amt;
      } else if (type == 'expense') {
        expense += amt;
      }
    }
    return initial + income - expense;
  }
}
