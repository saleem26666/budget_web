import 'dart:convert';

import 'package:flutter/foundation.dart' hide Category;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/currency_service.dart';
import '../utils/tx_image_helper.dart';
import 'budget_pro_import.dart';

/// One wallet profile (mirrors Budget Pro profiles on phone).
class WalletProfile {
  String id;
  String name;
  String? currencyCode;
  List<Account> accounts;
  List<Category> categories;
  List<Transaction> transactions;
  List<String> members;

  WalletProfile({
    required this.id,
    required this.name,
    this.currencyCode,
    List<Account>? accounts,
    List<Category>? categories,
    List<Transaction>? transactions,
    List<String>? members,
  })  : accounts = accounts ?? [],
        categories = categories ?? [],
        transactions = transactions ?? [],
        members = members ?? [];

  Map<String, dynamic> toJson() => {
        'profile_id': id,
        'profile_name': name,
        if (currencyCode != null && currencyCode!.isNotEmpty)
          'currency_code': currencyCode,
        'accounts': accounts.map((e) => e.toJson()).toList(),
        'categories': categories.map((e) => e.toJson()).toList(),
        'transactions': transactions.map((e) => e.toJson()).toList(),
        'members': members,
      };

  factory WalletProfile.fromJson(Map<String, dynamic> j) {
    final id = (j['profile_id'] ?? j['id'] ?? '').toString();
    final name = (j['profile_name'] ?? j['name'] ?? 'Personal').toString();
    return WalletProfile(
      id: id.isEmpty ? LocalStore.newId() : id,
      name: name.isEmpty ? 'Personal' : name,
      currencyCode: j['currency_code']?.toString(),
      accounts: (j['accounts'] as List? ?? [])
          .map((e) => Account.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      categories: (j['categories'] as List? ?? [])
          .map((e) => Category.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      transactions: (j['transactions'] as List? ?? [])
          .map((e) =>
              Transaction.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      members: (j['members'] as List? ?? [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList(),
    );
  }
}

class LocalStore extends ChangeNotifier {
  static const _key = 'budget_web_wallet_v1';
  static const _uuid = Uuid();

  final List<WalletProfile> profiles = [];
  String activeProfileId = '';
  bool loaded = false;

  WalletProfile get active {
    if (profiles.isEmpty) {
      profiles.add(_makeDefaultProfile());
      activeProfileId = profiles.first.id;
    }
    final i = profiles.indexWhere((p) => p.id == activeProfileId);
    if (i >= 0) return profiles[i];
    activeProfileId = profiles.first.id;
    return profiles.first;
  }

  String get activeProfileName => active.name;

  /// Active profile wallet fields (UI + logic use these).
  List<Account> get accounts => active.accounts;
  set accounts(List<Account> v) => active.accounts = v;

  List<Category> get categories => active.categories;
  set categories(List<Category> v) => active.categories = v;

  List<Transaction> get transactions => active.transactions;
  set transactions(List<Transaction> v) => active.transactions = v;

  List<String> get members => active.members;
  set members(List<String> v) => active.members = v;

  WalletProfile _makeDefaultProfile() {
    final p = WalletProfile(
      id: 'web_main',
      name: 'Personal',
      currencyCode: CurrencyService.instance.code,
    );
    p.accounts = [
      Account(id: _uuid.v4(), name: 'Cash', initialBalance: 0),
      Account(id: _uuid.v4(), name: 'Bank', initialBalance: 0),
    ];
    p.categories = [
      Category(id: _uuid.v4(), name: 'General'),
      Category(id: _uuid.v4(), name: 'Food'),
      Category(id: _uuid.v4(), name: 'Transport'),
      Category(id: _uuid.v4(), name: 'Salary'),
    ];
    return p;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    profiles.clear();
    if (raw == null || raw.isEmpty) {
      profiles.add(_makeDefaultProfile());
      activeProfileId = profiles.first.id;
    } else {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        if (map['profiles'] is List && (map['profiles'] as List).isNotEmpty) {
          for (final e in map['profiles'] as List) {
            if (e is! Map) continue;
            profiles.add(
                WalletProfile.fromJson(Map<String, dynamic>.from(e)));
          }
          activeProfileId =
              (map['active_profile_id'] ?? map['last_used_profile_id'] ?? '')
                  .toString();
        } else {
          // Legacy single-wallet blob → one profile
          final p = WalletProfile(
            id: 'web_main',
            name: 'Personal',
            currencyCode: map['currency_code']?.toString() ??
                CurrencyService.instance.code,
            accounts: (map['accounts'] as List? ?? [])
                .map((e) =>
                    Account.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList(),
            categories: (map['categories'] as List? ?? [])
                .map((e) =>
                    Category.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList(),
            transactions: (map['transactions'] as List? ?? [])
                .map((e) => Transaction.fromJson(
                    Map<String, dynamic>.from(e as Map)))
                .toList(),
            members: (map['members'] as List? ?? [])
                .map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList(),
          );
          profiles.add(p);
          activeProfileId = p.id;
        }
        if (profiles.isEmpty) {
          profiles.add(_makeDefaultProfile());
          activeProfileId = profiles.first.id;
        }
        if (!profiles.any((p) => p.id == activeProfileId)) {
          activeProfileId = profiles.first.id;
        }
        if (active.accounts.isEmpty) {
          active.accounts = [
            Account(id: _uuid.v4(), name: 'Cash', initialBalance: 0),
          ];
        }
      } catch (_) {
        profiles.clear();
        profiles.add(_makeDefaultProfile());
        activeProfileId = profiles.first.id;
      }
    }
    _syncMembersFromTx();
    loaded = true;
    notifyListeners();
  }

  void _seedDefaults() {
    profiles.clear();
    profiles.add(_makeDefaultProfile());
    activeProfileId = profiles.first.id;
  }

  void _syncMembersFromTx() {
    final set = {...members};
    for (final t in transactions) {
      final m = t.memberName.trim();
      if (m.isNotEmpty) set.add(m);
    }
    members = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    final map = {
      'app': 'budget_web',
      'version': 2,
      'backup_scope': 'all_profiles',
      'saved_at': DateTime.now().toIso8601String(),
      'active_profile_id': activeProfileId,
      'last_used_profile_id': activeProfileId,
      'profiles': profiles.map((p) => p.toJson()).toList(),
    };
    await prefs.setString(_key, jsonEncode(map));
    notifyListeners();
  }

  /// Export all profiles (shared format with Budget Pro phone backups).
  String exportJson() {
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'budget_web',
      'backup_scope': 'all_profiles',
      'version': 2,
      'exported_at': DateTime.now().toIso8601String(),
      'active_profile_id': activeProfileId,
      'last_used_profile_id': activeProfileId,
      'currency_code': CurrencyService.instance.code,
      'profiles': profiles.map((p) {
        final j = p.toJson();
        j['currency_code'] =
            p.currencyCode ?? CurrencyService.instance.code;
        return j;
      }).toList(),
    });
  }

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    final s = v.toString().trim().replaceAll(',', '');
    return double.tryParse(s) ?? 0;
  }

  static String _normType(dynamic raw) {
    final t = (raw ?? 'Expense').toString().trim().toLowerCase();
    if (t == 'income') return 'Income';
    if (t == 'transfer') return 'Transfer';
    return 'Expense';
  }

  (List<Account>, List<Category>, List<Transaction>, List<String>)
      _mapsToWallet({
    required List<Map<String, dynamic>> accountsIn,
    required List<Map<String, dynamic>> categoriesIn,
    required List<Map<String, dynamic>> transactionsIn,
  }) {
    var accs = accountsIn.map((e) {
      final id = (e['id'] ?? '').toString();
      return Account(
        id: id.isEmpty ? _uuid.v4() : id,
        name: (e['name'] ?? 'Account').toString().trim(),
        initialBalance: _num(e['initial_balance'] ?? e['initialBalance']),
      );
    }).where((a) => a.name.isNotEmpty).toList();

    // Same as Android map: duplicate names → last opening wins.
    final seen = <String, Account>{};
    for (final a in accs) {
      seen[a.name] = a;
    }
    accs = seen.values.toList();
    if (accs.isEmpty) {
      accs = [Account(id: _uuid.v4(), name: 'Cash', initialBalance: 0)];
    }

    var cats = categoriesIn.map((e) {
      final parsed = Category.fromJson(e);
      return Category(
        id: parsed.id.isEmpty ? _uuid.v4() : parsed.id,
        name: parsed.name.trim(),
        budget: parsed.budget,
        subCategories: parsed.subCategories,
      );
    }).where((c) => c.name.isNotEmpty).toList();
    if (cats.isEmpty) {
      cats = [Category(id: _uuid.v4(), name: 'General')];
    }

    final fallbackAccount = accs.first.name;
    final txs = transactionsIn.map((e) {
      final id = e['id']?.toString() ?? '';
      final account = (e['account'] ?? fallbackAccount).toString().trim();
      return Transaction(
        id: id.isEmpty ? _uuid.v4() : id,
        title: (e['title'] ?? '').toString(),
        desc: (e['desc'] ?? e['description'] ?? '').toString(),
        amount: _num(e['amount']),
        type: _normType(e['type']),
        account: account.isEmpty ? fallbackAccount : account,
        toAccount: (e['toAccount'] ?? '').toString().trim(),
        category: (e['category'] ?? '').toString().trim(),
        subCategory: (e['sub_category'] ?? '').toString().trim(),
        date: (e['date'] ?? DateTime.now().toIso8601String()).toString(),
        memberName: (e['member_name'] ?? '').toString().trim(),
        images: TxImageHelper.parseFromBackup(e),
      );
    }).toList();

    final mem = <String>{};
    for (final t in txs) {
      final m = t.memberName.trim();
      if (m.isNotEmpty) mem.add(m);
    }

    return (
      accs,
      cats,
      txs,
      mem.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
    );
  }

  /// Replace only the active profile's wallet data.
  Future<void> replaceFromWalletMaps({
    required List<Map<String, dynamic>> accountsIn,
    required List<Map<String, dynamic>> categoriesIn,
    required List<Map<String, dynamic>> transactionsIn,
  }) async {
    final built = _mapsToWallet(
      accountsIn: accountsIn,
      categoriesIn: categoriesIn,
      transactionsIn: transactionsIn,
    );
    accounts = built.$1;
    categories = built.$2;
    transactions = built.$3;
    members = built.$4;
    await persist();
  }

  /// Replace ALL profiles from a phone / shared backup (full sync).
  Future<void> replaceAllProfiles({
    required List<ImportedProfile> imported,
    String? preferredProfileId,
  }) async {
    if (imported.isEmpty) throw 'No profiles to import';
    profiles.clear();
    for (final ip in imported) {
      final built = _mapsToWallet(
        accountsIn: ip.accounts,
        categoriesIn: ip.categories,
        transactionsIn: ip.transactions,
      );
      profiles.add(WalletProfile(
        id: ip.id.isEmpty ? _uuid.v4() : ip.id,
        name: ip.name.isEmpty ? 'Profile' : ip.name,
        currencyCode: ip.currencyCode,
        accounts: built.$1,
        categories: built.$2,
        transactions: built.$3,
        members: built.$4,
      ));
    }
    final prefer = preferredProfileId;
    if (prefer != null &&
        prefer.isNotEmpty &&
        profiles.any((p) => p.id == prefer)) {
      activeProfileId = prefer;
    } else {
      activeProfileId = profiles.first.id;
    }
    final code = active.currencyCode;
    if (code != null && code.isNotEmpty) {
      await CurrencyService.instance.setCurrency(code);
    }
    await persist();
  }

  Future<void> switchProfile(String id) async {
    if (!profiles.any((p) => p.id == id)) return;
    activeProfileId = id;
    final code = active.currencyCode;
    if (code != null && code.isNotEmpty) {
      await CurrencyService.instance.setCurrency(code);
    }
    await persist();
  }

  Future<void> renameProfile(String id, String newName) async {
    final n = newName.trim();
    if (n.isEmpty) return;
    final i = profiles.indexWhere((p) => p.id == id);
    if (i < 0) return;
    profiles[i].name = n;
    await persist();
  }

  Future<void> addEmptyProfile(String name) async {
    final n = name.trim().isEmpty ? 'New profile' : name.trim();
    final p = _makeDefaultProfile();
    p.id = 'p${DateTime.now().millisecondsSinceEpoch}';
    p.name = n;
    profiles.add(p);
    activeProfileId = p.id;
    await persist();
  }

  /// New month profile: copy accounts (and optional categories) with openings
  /// = closing balances of [sourceId] as of end of [asOf].
  Future<void> addProfileFromSource({
    required String name,
    required String sourceId,
    required DateTime asOf,
    bool copyCategories = true,
  }) async {
    final src = profiles.where((p) => p.id == sourceId).firstOrNull;
    if (src == null) {
      await addEmptyProfile(name);
      return;
    }
    final n = name.trim().isEmpty ? 'New profile' : name.trim();
    final prevId = activeProfileId;
    activeProfileId = src.id;
    final snap = snapshotForDay(asOf);
    activeProfileId = prevId;

    double balanceForName(String name) {
      final n = name.trim();
      if (n.isEmpty) return 0;
      if (snap.accounts.containsKey(n)) return snap.accounts[n]!;
      final lower = n.toLowerCase();
      for (final e in snap.accounts.entries) {
        if (e.key.toLowerCase() == lower) return e.value;
      }
      return 0;
    }

    final accountNames = <String>[];
    final seenLower = <String>{};
    void addAccountName(String raw) {
      final name = raw.trim();
      if (name.isEmpty) return;
      final lower = name.toLowerCase();
      if (seenLower.contains(lower)) return;
      seenLower.add(lower);
      accountNames.add(name);
    }

    for (final a in src.accounts) {
      addAccountName(a.name);
    }
    for (final k in snap.accounts.keys) {
      addAccountName(k);
    }

    final p = WalletProfile(
      id: 'p${DateTime.now().millisecondsSinceEpoch}',
      name: n,
      currencyCode: src.currencyCode,
      accounts: [
        for (final name in accountNames)
          Account(
            id: _uuid.v4(),
            name: name,
            initialBalance: balanceForName(name),
          ),
      ],
      categories: copyCategories
          ? src.categories
              .map((c) => Category(
                    id: _uuid.v4(),
                    name: c.name,
                    budget: c.budget,
                    subCategories: List<String>.from(c.subCategories),
                  ))
              .toList()
          : [Category(id: _uuid.v4(), name: 'General')],
      transactions: [],
      members: [],
    );
    if (p.accounts.isEmpty) {
      p.accounts = [Account(id: _uuid.v4(), name: 'Cash', initialBalance: 0)];
    }
    profiles.add(p);
    activeProfileId = p.id;
    await persist();
  }

  Future<void> deleteProfile(String id) async {
    if (profiles.length <= 1) throw 'Keep at least one profile';
    profiles.removeWhere((p) => p.id == id);
    if (!profiles.any((p) => p.id == activeProfileId)) {
      activeProfileId = profiles.first.id;
    }
    await persist();
  }

  Future<void> clearAll() async {
    _seedDefaults();
    await persist();
  }

  // ── Accounts ──
  Future<void> addAccount(String name, double opening) async {
    accounts.add(
        Account(id: _uuid.v4(), name: name.trim(), initialBalance: opening));
    await persist();
  }

  Future<void> updateAccount(Account a, {String? oldName}) async {
    final i = accounts.indexWhere((e) => e.id == a.id);
    if (i < 0) return;
    final prev = oldName ?? accounts[i].name;
    accounts[i] = a;
    if (prev != a.name) {
      for (final t in transactions) {
        if (t.account == prev) t.account = a.name;
        if (t.toAccount == prev) t.toAccount = a.name;
      }
    }
    await persist();
  }

  Future<void> deleteAccount(String id) async {
    final name =
        accounts.where((e) => e.id == id).map((e) => e.name).firstOrNull;
    accounts.removeWhere((e) => e.id == id);
    if (name != null) {
      transactions
          .removeWhere((t) => t.account == name || t.toAccount == name);
    }
    await persist();
  }

  // ── Categories ──
  Future<void> addCategory(String name,
      {double? budget, List<String>? subs}) async {
    categories.add(Category(
      id: _uuid.v4(),
      name: name.trim(),
      budget: budget,
      subCategories: subs ?? const [],
    ));
    await persist();
  }

  Future<void> updateCategory(Category c) async {
    final i = categories.indexWhere((e) => e.id == c.id);
    if (i < 0) return;
    final prev = categories[i].name;
    categories[i] = c;
    if (prev != c.name) {
      for (final t in transactions) {
        if (t.category == prev) t.category = c.name;
      }
    }
    await persist();
  }

  Future<void> deleteCategory(String id) async {
    categories.removeWhere((e) => e.id == id);
    await persist();
  }

  /// Month expense total for a category (as of end of [day]).
  double categorySpentInMonth(String categoryName, DateTime day) {
    final y = day.year;
    final m = day.month;
    double sum = 0;
    for (final t in transactions) {
      if (t.type != 'Expense' || t.category != categoryName) continue;
      final d = DateTime.tryParse(t.dayKey);
      if (d == null || d.year != y || d.month != m) continue;
      if (t.dayKey.compareTo(dayKey(day)) > 0) continue;
      sum += t.amount;
    }
    return sum;
  }

  // ── Transactions ──
  Future<void> upsertTransaction(Transaction t, {bool isNew = false}) async {
    if (isNew) {
      transactions.insert(0, t);
    } else {
      final i = transactions.indexWhere((e) => e.id == t.id);
      if (i >= 0) {
        transactions[i] = t;
      } else {
        transactions.insert(0, t);
      }
    }
    _syncMembersFromTx();
    await persist();
  }

  Future<void> deleteTransaction(String id) async {
    transactions.removeWhere((e) => e.id == id);
    await persist();
  }

  Future<void> addMember(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    if (!members.contains(n)) {
      members.add(n);
      members.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      await persist();
    }
  }

  static String newId() => _uuid.v4();

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Wallet totals — same rules as Budget Pro `_walletSnapshotForDay`:
  /// only transactions on or before [day] (never include future dates).
  WalletSnapshot snapshotForDay(DateTime day) {
    final asOf = dayKey(day);

    final bals = <String, double>{};
    for (final a in accounts) {
      final name = a.name.trim();
      if (name.isEmpty) continue;
      bals[name] = a.initialBalance;
    }
    for (final t in transactions) {
      final acc = t.account.trim();
      final toAcc = t.toAccount.trim();
      if (acc.isNotEmpty && !bals.containsKey(acc)) bals[acc] = 0;
      if (toAcc.isNotEmpty && !bals.containsKey(toAcc)) bals[toAcc] = 0;
    }

    double dayIn = 0, dayOut = 0;
    double income = 0, expense = 0;

    for (final t in transactions) {
      final dk = t.dayKey;
      // Match Android: skip empty dates and anything after selected day.
      if (dk.isEmpty || dk.compareTo(asOf) > 0) continue;

      final amt = t.amount;
      final acc = t.account.trim();
      final toAcc = t.toAccount.trim();

      final type = t.type.trim().toLowerCase();
      if (type == 'income') {
        income += amt;
        if (bals.containsKey(acc)) bals[acc] = bals[acc]! + amt;
        if (dk == asOf) dayIn += amt;
      } else if (type == 'expense') {
        expense += amt;
        if (bals.containsKey(acc)) bals[acc] = bals[acc]! - amt;
        if (dk == asOf) dayOut += amt;
      } else if (type == 'transfer') {
        if (bals.containsKey(acc)) bals[acc] = bals[acc]! - amt;
        if (toAcc.isNotEmpty && bals.containsKey(toAcc)) {
          bals[toAcc] = bals[toAcc]! + amt;
        }
      }
    }

    // Android wallet card uses sum of account bals (same as initial+in−out
    // when transfers net correctly). Prefer sum so chips + total stay aligned.
    final sumBals = bals.values.fold<double>(0, (s, v) => s + v);
    final initialTotal =
        accounts.fold<double>(0, (s, a) => s + a.initialBalance);
    final byFormula = initialTotal + income - expense;
    // If they diverge, formula matches Android `_calculateTotals`.
    final total = (sumBals - byFormula).abs() < 0.02 ? sumBals : byFormula;

    return WalletSnapshot(
      balance: total,
      dayIncome: dayIn,
      dayExpense: dayOut,
      accounts: bals,
    );
  }

  List<Transaction> filteredForDay({
    required DateTime day,
    String? memberFilter,
    String query = '',
  }) {
    final q = query.trim().toLowerCase();
    final prefix = q.isEmpty ? dayKey(day) : null;
    final out = <Transaction>[];
    for (final t in transactions) {
      if (memberFilter != null && t.memberName.trim() != memberFilter) {
        continue;
      }
      if (prefix != null) {
        if (t.dayKey != prefix) continue;
        out.add(t);
        continue;
      }
      final hay =
          '${t.title} ${t.desc} ${t.account} ${t.toAccount} ${t.category} ${t.memberName} ${t.amount}'
              .toLowerCase();
      if (hay.contains(q)) out.add(t);
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  /// Running balances for statement (oldest first applied).
  List<Map<String, dynamic>> statementRows(String accountName) {
    final opening = accounts
            .where((a) => a.name == accountName)
            .map((a) => a.initialBalance)
            .firstOrNull ??
        0.0;
    final list = transactions.where((t) {
      if (t.type == 'Transfer') {
        return t.account == accountName || t.toAccount == accountName;
      }
      return t.account == accountName;
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    double bal = opening;
    double totalIn = 0, totalOut = 0;
    final rows = <Map<String, dynamic>>[];
    for (final t in list) {
      double delta = 0;
      if (t.type == 'Income' && t.account == accountName) {
        delta = t.amount;
        totalIn += t.amount;
      } else if (t.type == 'Expense' && t.account == accountName) {
        delta = -t.amount;
        totalOut += t.amount;
      } else if (t.type == 'Transfer') {
        if (t.toAccount == accountName) {
          delta = t.amount;
          totalIn += t.amount;
        } else if (t.account == accountName) {
          delta = -t.amount;
          totalOut += t.amount;
        }
      }
      bal += delta;
      rows.add({
        ...t.toJson(),
        'running_balance': bal,
        'signed': delta,
      });
    }
    return [
      {
        '_meta': true,
        'opening': opening,
        'totalIn': totalIn,
        'totalOut': totalOut,
        'closing': bal,
      },
      ...rows.reversed,
    ];
  }

  /// Account statement for [accountName] between [from] and [to] inclusive.
  Map<String, dynamic> reportForAccount({
    required String accountName,
    required DateTime from,
    required DateTime to,
  }) {
    final fromKey = dayKey(from);
    final toKey = dayKey(to);
    final startOpening = accounts
            .where((a) => a.name == accountName)
            .map((a) => a.initialBalance)
            .firstOrNull ??
        0.0;

    final all = transactions.where((t) {
      if (t.type == 'Transfer') {
        return t.account == accountName || t.toAccount == accountName;
      }
      return t.account == accountName;
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    double bal = startOpening;
    double periodIn = 0, periodOut = 0;
    final periodRows = <Map<String, dynamic>>[];

    for (final t in all) {
      final dk = t.dayKey;
      if (dk.isEmpty) continue;

      double delta = 0;
      if (t.type == 'Income' && t.account == accountName) {
        delta = t.amount;
      } else if (t.type == 'Expense' && t.account == accountName) {
        delta = -t.amount;
      } else if (t.type == 'Transfer') {
        if (t.toAccount == accountName) {
          delta = t.amount;
        } else if (t.account == accountName) {
          delta = -t.amount;
        }
      }

      if (dk.compareTo(fromKey) < 0) {
        bal += delta;
        continue;
      }
      if (dk.compareTo(toKey) > 0) continue;

      bal += delta;
      if (delta > 0) {
        periodIn += delta;
      } else if (delta < 0) {
        periodOut += -delta;
      }
      periodRows.add({
        ...t.toJson(),
        'signed': delta,
        'running_balance': bal,
      });
    }

    final opening = bal -
        periodRows.fold<double>(
            0, (s, r) => s + ((r['signed'] as num?)?.toDouble() ?? 0));

    return {
      'account': accountName,
      'from': fromKey,
      'to': toKey,
      'opening': opening,
      'totalIn': periodIn,
      'totalOut': periodOut,
      'closing': bal,
      'rows': periodRows.reversed.toList(),
    };
  }

  List<Map<String, dynamic>> reportAllAccounts({
    required DateTime from,
    required DateTime to,
  }) {
    return accounts
        .map((a) => reportForAccount(
              accountName: a.name,
              from: from,
              to: to,
            ))
        .toList();
  }
}
