import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppCurrency {
  final String code;
  final String symbol;
  final String name;
  final int decimalDigits;

  const AppCurrency({
    required this.code,
    required this.symbol,
    required this.name,
    this.decimalDigits = 0,
  });

  String get label => '$name ($code)';
}

/// Home currency for Budget Web (browser-local).
class CurrencyService extends ChangeNotifier {
  CurrencyService._();
  static final CurrencyService instance = CurrencyService._();

  static const _prefKey = 'budget_web_currency_code';
  static const String defaultCode = 'PKR';

  static const List<AppCurrency> currencies = [
    AppCurrency(code: 'PKR', symbol: 'Rs', name: 'Pakistani Rupee'),
    AppCurrency(code: 'USD', symbol: r'$', name: 'US Dollar', decimalDigits: 2),
    AppCurrency(code: 'EUR', symbol: '€', name: 'Euro', decimalDigits: 2),
    AppCurrency(code: 'GBP', symbol: '£', name: 'British Pound', decimalDigits: 2),
    AppCurrency(code: 'AED', symbol: 'AED', name: 'UAE Dirham'),
    AppCurrency(code: 'SAR', symbol: 'SAR', name: 'Saudi Riyal'),
    AppCurrency(code: 'INR', symbol: '₹', name: 'Indian Rupee'),
    AppCurrency(code: 'BDT', symbol: '৳', name: 'Bangladeshi Taka'),
    AppCurrency(code: 'CAD', symbol: r'C$', name: 'Canadian Dollar', decimalDigits: 2),
    AppCurrency(code: 'AUD', symbol: r'A$', name: 'Australian Dollar', decimalDigits: 2),
    AppCurrency(code: 'CNY', symbol: '¥', name: 'Chinese Yuan'),
    AppCurrency(code: 'TRY', symbol: '₺', name: 'Turkish Lira'),
    AppCurrency(code: 'QAR', symbol: 'QAR', name: 'Qatari Riyal'),
    AppCurrency(code: 'KWD', symbol: 'KWD', name: 'Kuwaiti Dinar', decimalDigits: 3),
    AppCurrency(code: 'OMR', symbol: 'OMR', name: 'Omani Rial', decimalDigits: 3),
  ];

  String _code = defaultCode;
  bool loaded = false;

  String get code => _code;

  AppCurrency get current =>
      currencies.firstWhere((c) => c.code == _code, orElse: () => currencies.first);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    _code = _isValid(saved) ? saved! : defaultCode;
    loaded = true;
    notifyListeners();
  }

  Future<void> setCurrency(String code) async {
    if (!_isValid(code)) return;
    _code = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, code);
    notifyListeners();
  }

  bool _isValid(String? code) =>
      code != null && currencies.any((c) => c.code == code);

  String _pattern() {
    final d = current.decimalDigits;
    return d > 0 ? '#,##0.${'0' * d}' : '#,##0';
  }

  String format(num amount, {bool compact = true}) {
    final n = NumberFormat(_pattern()).format(amount);
    if (compact) return '${current.symbol}$n';
    return '${current.code} $n';
  }

  String amountLabel() => 'Amount (${current.code})';

  static String fmt(num amount) => instance.format(amount);
}
