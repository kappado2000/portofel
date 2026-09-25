import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/account.dart';
import '../models/money_transaction.dart';

/// Datele financiare (conturi, tranzacții) ale profilului activ. Fiecare
/// profil are propriile cutii Hive, complet separate de celelalte profiluri
/// — vezi [loadProfile].
class MoneyProvider extends ChangeNotifier {
  Box? _accountsBox;
  Box? _transactionsBox;
  Box? _settingsBox;
  String? _loadedProfileId;

  final _uuid = const Uuid();

  List<Account> _accounts = [];
  List<MoneyTransaction> _transactions = [];

  String? get loadedProfileId => _loadedProfileId;

  List<Account> get accounts => List.unmodifiable(_accounts);

  List<Account> _sortedByGroup(AccountGroup group) {
    final list = _accounts.where((a) => a.group == group).toList();
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return List.unmodifiable(list);
  }

  List<Account> get personalAccounts => _sortedByGroup(AccountGroup.personal);

  List<Account> get familyAccounts => _sortedByGroup(AccountGroup.family);

  /// Contul preselectat implicit în formulare: Cash Euro, dacă există,
  /// altfel primul cont disponibil.
  Account? get defaultAccount {
    if (_accounts.isEmpty) return null;
    for (final a in _accounts) {
      if (a.currency == AccountCurrency.eur && a.kind == AccountKind.cash) return a;
    }
    return _accounts.first;
  }

  List<MoneyTransaction> get transactions {
    final list = List<MoneyTransaction>.from(_transactions);
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  double get defaultExchangeRate =>
      (_settingsBox?.get('eurRonRate') as num?)?.toDouble() ?? 5.0;

  set defaultExchangeRate(double rate) {
    _settingsBox?.put('eurRonRate', rate);
    notifyListeners();
  }

  Account? accountById(String id) {
    try {
      return _accounts.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Încarcă (sau comută la) datele financiare ale profilului dat. Poate fi
  /// apelat de mai multe ori în viața aplicației, la fiecare schimbare de
  /// profil — închide cutiile profilului anterior înainte de a deschide
  /// cutiile noului profil.
  Future<void> loadProfile(String profileId) async {
    if (_loadedProfileId == profileId) return;

    await _accountsBox?.close();
    await _transactionsBox?.close();
    await _settingsBox?.close();

    _accountsBox = await Hive.openBox('accounts_$profileId');
    _transactionsBox = await Hive.openBox('transactions_$profileId');
    _settingsBox = await Hive.openBox('settings_$profileId');
    _loadedProfileId = profileId;

    if (_accountsBox!.isEmpty) {
      _seedDefaultAccounts();
    }

    _loadFromBoxes();
  }

  void _seedDefaultAccounts() {
    final defaults = [
      Account(id: _uuid.v4(), name: 'Cash Lei', currency: AccountCurrency.ron, kind: AccountKind.cash, sortOrder: 0),
      Account(id: _uuid.v4(), name: 'Cash Euro', currency: AccountCurrency.eur, kind: AccountKind.cash, sortOrder: 1),
      Account(id: _uuid.v4(), name: 'Cont', currency: AccountCurrency.ron, kind: AccountKind.bank, sortOrder: 2),
    ];
    for (final a in defaults) {
      _accountsBox!.put(a.id, a.toMap());
    }
  }

  void _loadFromBoxes() {
    _accounts = _accountsBox!.values.map((m) => Account.fromMap(Map.from(m))).toList();
    _transactions = _transactionsBox!.values
        .map((m) => MoneyTransaction.fromMap(Map.from(m)))
        .toList();
    notifyListeners();
  }

  void _persistAccount(Account a) {
    _accountsBox?.put(a.id, a.toMap());
  }

  // ---- Conturi ----

  Future<void> addAccount({
    required String name,
    required AccountCurrency currency,
    required AccountKind kind,
    double initialBalance = 0,
    AccountGroup group = AccountGroup.personal,
  }) async {
    final maxOrder = _accounts
        .where((a) => a.group == group)
        .fold(-1, (max, a) => a.sortOrder > max ? a.sortOrder : max);
    final account = Account(
      id: _uuid.v4(),
      name: name,
      currency: currency,
      kind: kind,
      balance: initialBalance,
      group: group,
      sortOrder: maxOrder + 1,
    );
    _accounts.add(account);
    _persistAccount(account);
    notifyListeners();
  }

  /// Reordonează conturile din [group], după un drag-and-drop într-un
  /// ReorderableListView — [oldIndex]/[newIndex] sunt indicii primiți direct
  /// din callback-ul `onReorderItem`, care are deja newIndex ajustat pentru
  /// elementul scos de la oldIndex (spre deosebire de vechiul `onReorder`,
  /// deprecated în Flutter 3.47).
  Future<void> reorderAccounts(AccountGroup group, int oldIndex, int newIndex) async {
    final list = _sortedByGroup(group).toList();
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    for (var i = 0; i < list.length; i++) {
      list[i].sortOrder = i;
      _persistAccount(list[i]);
    }
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
    _accountsBox?.delete(id);
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
    _transactionsBox?.put(tx.id, tx.toMap());
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
    _transactionsBox?.put(tx.id, tx.toMap());
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
    _transactionsBox?.put(tx.id, tx.toMap());
    notifyListeners();
  }

  void _reverseEffect(MoneyTransaction tx) {
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
  }

  Future<void> deleteTransaction(String id) async {
    final tx = _transactions.firstWhere((t) => t.id == id);
    _reverseEffect(tx);
    _transactions.removeWhere((t) => t.id == id);
    _transactionsBox?.delete(id);
    notifyListeners();
  }

  Future<void> updateIncome({
    required String transactionId,
    required String accountId,
    required double amount,
    required String category,
    String note = '',
    DateTime? date,
  }) async {
    final old = _transactions.firstWhere((t) => t.id == transactionId);
    _reverseEffect(old);

    final account = accountById(accountId);
    if (account == null) return;
    account.balance += amount;
    _persistAccount(account);

    final updated = MoneyTransaction(
      id: old.id,
      type: TxType.income,
      date: date ?? old.date,
      fromAccountId: accountId,
      amount: amount,
      category: category,
      note: note,
    );
    _replaceTransaction(updated);
  }

  Future<void> updateExpense({
    required String transactionId,
    required String accountId,
    required double amount,
    required String category,
    String note = '',
    DateTime? date,
  }) async {
    final old = _transactions.firstWhere((t) => t.id == transactionId);
    _reverseEffect(old);

    final account = accountById(accountId);
    if (account == null) return;
    account.balance -= amount;
    _persistAccount(account);

    final updated = MoneyTransaction(
      id: old.id,
      type: TxType.expense,
      date: date ?? old.date,
      fromAccountId: accountId,
      amount: amount,
      category: category,
      note: note,
    );
    _replaceTransaction(updated);
  }

  Future<void> updateTransfer({
    required String transactionId,
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    double? exchangeRate,
    String note = '',
    DateTime? date,
  }) async {
    final old = _transactions.firstWhere((t) => t.id == transactionId);
    _reverseEffect(old);

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

    final updated = MoneyTransaction(
      id: old.id,
      type: TxType.transfer,
      date: date ?? old.date,
      fromAccountId: fromAccountId,
      toAccountId: toAccountId,
      amount: amount,
      convertedAmount: converted,
      exchangeRate: usedRate,
      category: 'Transfer',
      note: note,
    );
    _replaceTransaction(updated);
  }

  void _replaceTransaction(MoneyTransaction updated) {
    final idx = _transactions.indexWhere((t) => t.id == updated.id);
    if (idx == -1) return;
    _transactions[idx] = updated;
    _transactionsBox?.put(updated.id, updated.toMap());
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
