class Account {
  final String id;
  String name;
  double initialBalance;

  Account({
    required this.id,
    required this.name,
    this.initialBalance = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'initial_balance': initialBalance,
      };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: (j['id'] ?? j['name'] ?? '').toString(),
        name: (j['name'] ?? 'Account').toString(),
        initialBalance: (j['initial_balance'] as num?)?.toDouble() ?? 0,
      );
}

class Category {
  final String id;
  String name;
  double? budget;
  List<String> subCategories;

  Category({
    required this.id,
    required this.name,
    this.budget,
    this.subCategories = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'budget': budget,
        'sub_categories': subCategories,
      };

  factory Category.fromJson(Map<String, dynamic> j) {
    List<String> subs = [];
    final raw = j['sub_categories'];
    if (raw is List) {
      subs = raw.map((e) => e.toString()).toList();
    } else if (raw is String && raw.trim().isNotEmpty && raw != '[]') {
      try {
        // may be JSON string from Budget Pro
        final cleaned = raw
            .replaceAll('[', '')
            .replaceAll(']', '')
            .replaceAll('"', '')
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        subs = cleaned;
      } catch (_) {}
    }
    return Category(
      id: (j['id'] ?? j['name'] ?? '').toString(),
      name: (j['name'] ?? 'General').toString(),
      budget: (j['budget'] as num?)?.toDouble(),
      subCategories: subs,
    );
  }
}

class Transaction {
  final String id;
  String title;
  String desc;
  double amount;
  String type; // Income | Expense | Transfer
  String account;
  String toAccount;
  String category;
  String subCategory;
  String date; // yyyy-MM-dd HH:mm or ISO
  String memberName;
  /// Up to 5 data-URL images (`data:image/...;base64,...`).
  List<String> images;

  Transaction({
    required this.id,
    required this.title,
    this.desc = '',
    required this.amount,
    required this.type,
    required this.account,
    this.toAccount = '',
    this.category = '',
    this.subCategory = '',
    required this.date,
    this.memberName = '',
    List<String>? images,
  }) : images = List<String>.from(images ?? const []);

  String get dayKey {
    final s = date;
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'desc': desc,
        'amount': amount,
        'type': type,
        'account': account,
        'toAccount': toAccount,
        'category': category,
        'sub_category': subCategory,
        'date': date,
        'member_name': memberName,
        'imgs': images,
      };

  factory Transaction.fromJson(Map<String, dynamic> j) {
    List<String> imgs = [];
    final raw = j['imgs'] ?? j['images'];
    if (raw is List) {
      imgs = raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    return Transaction(
      id: (j['id'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      desc: (j['desc'] ?? j['description'] ?? '').toString(),
      amount: (j['amount'] as num?)?.toDouble() ?? 0,
      type: (j['type'] ?? 'Expense').toString(),
      account: (j['account'] ?? '').toString(),
      toAccount: (j['toAccount'] ?? '').toString(),
      category: (j['category'] ?? '').toString(),
      subCategory: (j['sub_category'] ?? '').toString(),
      date: (j['date'] ?? DateTime.now().toIso8601String()).toString(),
      memberName: (j['member_name'] ?? '').toString(),
      images: imgs.take(5).toList(),
    );
  }
}

class WalletSnapshot {
  final double balance;
  final double dayIncome;
  final double dayExpense;
  final Map<String, double> accounts;

  const WalletSnapshot({
    required this.balance,
    required this.dayIncome,
    required this.dayExpense,
    required this.accounts,
  });
}
