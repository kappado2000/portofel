import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/account.dart';
import '../models/money_transaction.dart';

const _accountsBoxName = 'accounts';
const _transactionsBoxName = 'transactions';
const _settingsBoxName = 'settings';

class MoneyProvider extends ChangeNotifier {
  late Box _accountsBox;
  late Box _transactionsBox;
  late Box _settingsBox;

  final _uuid = const Uuid();

  List<Account> _accounts = [];
  List<MoneyTransaction> _transactions = [];

  List<Account> get accounts => List.unmodifiable(_accounts);

  List<Account> get personalAccounts =>
      List.unmodifiable(_accounts.where((a) => a.group == AccountGroup.personal));

  List<Account> get familyAccounts =>
      List.unmodifiable(_accounts.where((a) => a.group == AccountGroup.family));

  List<MoneyTransaction> get transactions {
    final list = List<MoneyTransaction>.from(_transactions);
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  double get defaultExchangeRate =>
      (_settingsBox.get('eurRonRate') as num?)?.toDouble() ?? 5.0;

  set defaultExchangeRate(double rate) {
    _settingsBox.put('eurRonRate', rate);
    notifyListeners();
  }

  // ---- Parolă de acces (PIN) ----

  bool get hasPin => _settingsBox.get('pinHash') != null;

  String _hashPin(String pin) => sha256.convert(utf8.encode('portofel_salt::$pin')).toString();

  Future<void> setPin(String pin) async {
    await _settingsBox.put('pinHash', _hashPin(pin));
    notifyListeners();
  }

  bool verifyPin(String pin) {
    final stored = _settingsBox.get('pinHash') as String?;
    if (stored == null) return true;
    return stored == _hashPin(pin);
  }

  Future<void> removePin() async {
    await _settingsBox.delete('pinHash');
    await _settingsBox.delete('securityAnswerHash');
    await _settingsBox.put('biometricEnabled', false);
    notifyListeners();
  }

  // ---- Întrebare de securitate (recuperare parolă) ----

  static const securityQuestion = 'Care este numele animalului tău preferat?';

  bool get hasSecurityAnswer => _settingsBox.get('securityAnswerHash') != null;

  String _hashAnswer(String answer) =>
      sha256.convert(utf8.encode('portofel_salt::${answer.trim().toLowerCase()}')).toString();

  Future<void> setSecurityAnswer(String answer) async {
    await _settingsBox.put('securityAnswerHash', _hashAnswer(answer));
    notifyListeners();
  }

  bool verifySecurityAnswer(String answer) {
    final stored = _settingsBox.get('securityAnswerHash') as String?;
    if (stored == null) return false;
    return stored == _hashAnswer(answer);
  }

  bool get biometricEnabled => (_settingsBox.get('biometricEnabled') as bool?) ?? false;

  Future<void> setBiometricEnabled(bool enabled) async {
    await _settingsBox.put('biometricEnabled', enabled);
    notifyListeners();
  }

  // ---- Temă ----

  ThemeMode get themeMode {
    final stored = _settingsBox.get('themeMode') as String?;
    return switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _settingsBox.put('themeMode', mode.name);
    notifyListeners();
  }

  Account? accountById(String id) {
    try {
      return _accounts.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> init() async {
    await Hive.initFlutter();
    _accountsBox = await Hive.openBox(_accountsBoxName);
    _transactionsBox = await Hive.openBox(_transactionsBoxName);
    _settingsBox = await Hive.openBox(_settingsBoxName);

    if (_accountsBox.isEmpty) {
      _seedDefaultAccounts();
    }

    _loadFromBoxes();
  }

  void _seedDefaultAccounts() {
    final defaults = [
      Account(id: _uuid.v4(), name: 'Cash Lei', currency: AccountCurrency.ron, kind: AccountKind.cash),
      Account(id: _uuid.v4(), name: 'Cash Euro', currency: AccountCurrency.eur, kind: AccountKind.cash),
      Account(id: _uuid.v4(), name: 'Cont', currency: AccountCurrency.ron, kind: AccountKind.bank),
    ];
    for (final a in defaults) {
      _accountsBox.put(a.id, a.toMap());
    }
  }

  void _loadFromBoxes() {
    _accounts = _accountsBox.values.map((m) => Account.fromMap(Map.from(m))).toList();
    _transactions = _transactionsBox.values
        .map((m) => MoneyTransaction.fromMap(Map.from(m)))
        .toList();
    notifyListeners();
  }

  void _persistAccount(Account a) {
    _accountsBox.put(a.id, a.toMap());
  }

  // ---- Conturi ----

  Future<void> addAccount({
    required String name,
    required AccountCurrency currency,
    required AccountKind kind,
    double initialBalance = 0,
    AccountGroup group = AccountGroup.personal,
  }) async {
    final account = Account(
      id: _uuid.v4(),
      name: name,
      currency: currency,
      kind: kind,
      balance: initialBalance,
      group: group,
    );
    _accounts.add(account);
    _persistAccount(account);
    notifyListeners();
  }

  Future<void> renameAccount(String id, String newName) async {
    final account = accountById(id);
    if (account == null) return;
    account.name = newName;
    _persistAccount(account);
    notifyListeners();
  }

  Future<void> setAccountGroup(String id, AccountGroup group) async {
    final account = accountById(id);
    if (account == null) return;
    account.group = group;
    _persistAccount(account);
    notifyListeners();
  }

  Future<void> deleteAccount(String id) async {
    final hasTx = _transactions.any((t) => t.fromAccountId == id || t.toAccountId == id);
    if (hasTx) {
      throw Exception('Nu poți șterge un cont care are tranzacții. Șterge întâi tranzacțiile.');
    }
    _accounts.removeWhere((a) => a.id == id);
    _accountsBox.delete(id);
    notifyListeners();
  }

  // ---- Tranzacții ----

  Future<void> addIncome({
    required String accountId,
    required double amount,
    required String category,
    String note = '',
    DateTime? date,
  }) async {
    final account = accountById(accountId);
    if (account == null) return;
    account.balance += amount;
    _persistAccount(account);

    final tx = MoneyTransaction(
      id: _uuid.v4(),
      type: TxType.income,
      date: date ?? DateTime.now(),
      fromAccountId: accountId,
      amount: amount,
      category: category,
      note: note,
    );
    _transactions.add(tx);
    _transactionsBox.put(tx.id, tx.toMap());
    notifyListeners();
  }

  Future<void> addExpense({
    required String accountId,
    required double amount,
    required String category,
    String note = '',
    DateTime? date,
  }) async {
    final account = accountById(accountId);
    if (account == null) return;
    account.balance -= amount;
    _persistAccount(account);

    final tx = MoneyTransaction(
      id: _uuid.v4(),
      type: TxType.expense,
      date: date ?? DateTime.now(),
      fromAccountId: accountId,
      amount: amount,
      category: category,
      note: note,
    );
    _transactions.add(tx);
    _transactionsBox.put(tx.id, tx.toMap());
    notifyListeners();
  }

  /// Transfer / schimb valutar / retragere din cont: scade `amount` din
  /// contul sursă și adaugă `convertedAmount` (sau `amount` dacă aceeași
  /// valută) în contul destinație.
  Future<void> addTransfer({
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    double? exchangeRate,
    String note = '',
    DateTime? date,
  }) async {
    final from = accountById(fromAccountId);
    final to = accountById(toAccountId);
    if (from == null || to == null) return;

    double converted = amount;
    double? usedRate;
    if (from.currency != to.currency) {
      usedRate = exchangeRate ?? defaultExchangeRate;
      if (from.currency == AccountCurrency.eur && to.currency == AccountCurrency.ron) {
        converted = amount * usedRate;
      } else if (from.currency == AccountCurrency.ron && to.currency == AccountCurrency.eur) {
        converted = amount / usedRate;
      }
    }

    from.balance -= amount;
    to.balance += converted;
    _persistAccount(from);
    _persistAccount(to);

    final tx = MoneyTransaction(
      id: _uuid.v4(),
      type: TxType.transfer,
      date: date ?? DateTime.now(),
      fromAccountId: fromAccountId,
      toAccountId: toAccountId,
      amount: amount,
      convertedAmount: converted,
      exchangeRate: usedRate,
      category: 'Transfer',
      note: note,
    );
    _transactions.add(tx);
    _transactionsBox.put(tx.id, tx.toMap());
    notifyListeners();
  }

  Future<void> deleteTransaction(String id) async {
    final tx = _transactions.firstWhere((t) => t.id == id);
    final from = accountById(tx.fromAccountId);

    switch (tx.type) {
      case TxType.income:
        from?.balance -= tx.amount;
        break;
      case TxType.expense:
        from?.balance += tx.amount;
        break;
      case TxType.transfer:
        final to = tx.toAccountId != null ? accountById(tx.toAccountId!) : null;
        from?.balance += tx.amount;
        to?.balance -= (tx.convertedAmount ?? tx.amount);
        if (to != null) _persistAccount(to);
        break;
    }
    if (from != null) _persistAccount(from);

    _transactions.removeWhere((t) => t.id == id);
    _transactionsBox.delete(id);
    notifyListeners();
  }

  // ---- Totaluri ----
  //
  // Totalurile includ doar conturile din grupul Personal; conturile din
  // grupul Familie sunt ținute separat, pe pagina "Conturi Familie".

  double totalInRon({AccountGroup? group}) {
    double total = 0;
    for (final a in _accounts.where((a) => a.group == (group ?? AccountGroup.personal))) {
      total += a.currency == AccountCurrency.ron ? a.balance : a.balance * defaultExchangeRate;
    }
    return total;
  }

  double totalInEur({AccountGroup? group}) {
    double total = 0;
    for (final a in _accounts.where((a) => a.group == (group ?? AccountGroup.personal))) {
      total += a.currency == AccountCurrency.eur ? a.balance : a.balance / defaultExchangeRate;
    }
    return total;
  }
}
