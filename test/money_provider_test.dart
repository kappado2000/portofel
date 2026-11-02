import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:portofel/models/account.dart';
import 'package:portofel/models/money_transaction.dart';
import 'package:portofel/providers/money_provider.dart';

void main() {
  late Directory dir;
  late MoneyProvider money;
  var profileCounter = 0;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('portofel_test');
    Hive.init(dir.path);
    money = MoneyProvider();
    await money.loadProfile('p${profileCounter++}');
  });

  tearDown(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  Account named(String name) =>
      money.accounts.firstWhere((a) => a.name == name);

  test('a new profile starts with Cash Lei, Cash Euro and Cont, all at 0', () {
    expect(money.accounts.map((a) => a.name), [
      'Cash Lei',
      'Cash Euro',
      'Cont',
    ]);
    expect(money.accounts.every((a) => a.balance == 0), isTrue);
    expect(money.defaultAccount!.name, 'Cash Lei');
    expect(money.defaultExchangeRate, 5.0);
  });

  test('income and expense move the balance of their account only', () async {
    final lei = named('Cash Lei');
    await money.addIncome(accountId: lei.id, amount: 1000, category: 'Salariu');
    await money.addExpense(
      accountId: lei.id,
      amount: 250.5,
      category: 'Mâncare',
    );

    expect(named('Cash Lei').balance, closeTo(749.5, 1e-9));
    expect(named('Cont').balance, 0);
    expect(money.transactions, hasLength(2));
  });

  test('transfer EUR → RON converts at the given rate', () async {
    final eur = named('Cash Euro');
    final ron = named('Cash Lei');
    await money.addIncome(accountId: eur.id, amount: 100, category: 'x');

    await money.addTransfer(
      fromAccountId: eur.id,
      toAccountId: ron.id,
      amount: 40,
      exchangeRate: 4.97,
    );

    expect(named('Cash Euro').balance, closeTo(60, 1e-9));
    expect(named('Cash Lei').balance, closeTo(198.8, 1e-9));
    final tx = money.transactions.firstWhere((t) => t.type == TxType.transfer);
    expect(tx.convertedAmount, closeTo(198.8, 1e-9));
    expect(tx.exchangeRate, 4.97);
  });

  test(
    'transfer RON → EUR divides by the default rate when none is given',
    () async {
      final ron = named('Cash Lei');
      final eur = named('Cash Euro');
      money.defaultExchangeRate = 5.0;

      await money.addTransfer(
        fromAccountId: ron.id,
        toAccountId: eur.id,
        amount: 500,
      );

      expect(named('Cash Lei').balance, closeTo(-500, 1e-9));
      expect(named('Cash Euro').balance, closeTo(100, 1e-9));
    },
  );

  test(
    'same-currency transfer moves the amount unchanged, without a rate',
    () async {
      final lei = named('Cash Lei');
      final cont = named('Cont');
      await money.addTransfer(
        fromAccountId: cont.id,
        toAccountId: lei.id,
        amount: 300,
      );

      expect(named('Cont').balance, -300);
      expect(named('Cash Lei').balance, 300);
      expect(money.transactions.single.exchangeRate, isNull);
    },
  );

  test('deleting any transaction restores the balances exactly', () async {
    final lei = named('Cash Lei');
    final eur = named('Cash Euro');
    await money.addIncome(accountId: lei.id, amount: 1000, category: 'x');
    await money.addExpense(accountId: lei.id, amount: 120, category: 'x');
    await money.addTransfer(
      fromAccountId: lei.id,
      toAccountId: eur.id,
      amount: 497,
      exchangeRate: 4.97,
    );

    for (final tx in money.transactions.toList()) {
      await money.deleteTransaction(tx.id);
    }

    expect(money.transactions, isEmpty);
    expect(named('Cash Lei').balance, closeTo(0, 1e-9));
    expect(named('Cash Euro').balance, closeTo(0, 1e-9));
  });

  test(
    'editing an expense to another account and amount moves the money',
    () async {
      final lei = named('Cash Lei');
      final cont = named('Cont');
      await money.addExpense(accountId: lei.id, amount: 100, category: 'x');
      final id = money.transactions.single.id;

      await money.updateExpense(
        transactionId: id,
        accountId: cont.id,
        amount: 80,
        category: 'y',
      );

      expect(named('Cash Lei').balance, 0);
      expect(named('Cont').balance, -80);
      expect(money.transactions.single.fromAccountId, cont.id);
      expect(money.transactions.single.category, 'y');
    },
  );

  test(
    'editing a transfer reverses the old conversion and applies the new one',
    () async {
      final eur = named('Cash Euro');
      final ron = named('Cash Lei');
      await money.addTransfer(
        fromAccountId: eur.id,
        toAccountId: ron.id,
        amount: 10,
        exchangeRate: 5,
      );
      final id = money.transactions.single.id;

      await money.updateTransfer(
        transactionId: id,
        fromAccountId: eur.id,
        toAccountId: ron.id,
        amount: 20,
        exchangeRate: 4.9,
      );

      expect(named('Cash Euro').balance, closeTo(-20, 1e-9));
      expect(named('Cash Lei').balance, closeTo(98, 1e-9));
      expect(money.transactions, hasLength(1));
    },
  );

  test('an account with transactions cannot be deleted', () async {
    final lei = named('Cash Lei');
    await money.addIncome(accountId: lei.id, amount: 1, category: 'x');

    expect(() => money.deleteAccount(lei.id), throwsException);
    await money.deleteAccount(named('Cont').id);
    expect(money.accounts.map((a) => a.name), ['Cash Lei', 'Cash Euro']);
  });

  test(
    'totals count only personal accounts, converted at the default rate',
    () async {
      money.defaultExchangeRate = 5.0;
      await money.addIncome(
        accountId: named('Cash Lei').id,
        amount: 500,
        category: 'x',
      );
      await money.addIncome(
        accountId: named('Cash Euro').id,
        amount: 100,
        category: 'x',
      );
      await money.addAccount(
        name: 'Familie',
        currency: AccountCurrency.ron,
        kind: AccountKind.bank,
        initialBalance: 10000,
        group: AccountGroup.family,
      );

      expect(money.totalInRon(), closeTo(1000, 1e-9));
      expect(money.totalInEur(), closeTo(200, 1e-9));
      expect(
        money.totalInRon(group: AccountGroup.family),
        closeTo(10000, 1e-9),
      );
    },
  );

  test(
    'reordering a group renumbers it and changes the default account',
    () async {
      await money.reorderAccounts(AccountGroup.personal, 2, 0);

      expect(money.personalAccounts.map((a) => a.name), [
        'Cont',
        'Cash Lei',
        'Cash Euro',
      ]);
      expect(money.defaultAccount!.name, 'Cont');
    },
  );

  test('data is saved per profile and survives reopening', () async {
    final profile = money.loadedProfileId!;
    await money.addIncome(
      accountId: named('Cash Lei').id,
      amount: 42,
      category: 'x',
    );

    await money.loadProfile('other');
    expect(money.accounts.every((a) => a.balance == 0), isTrue);
    expect(money.transactions, isEmpty);

    final reopened = MoneyProvider();
    await reopened.loadProfile(profile);
    expect(
      reopened.accounts.firstWhere((a) => a.name == 'Cash Lei').balance,
      42,
    );
    expect(reopened.transactions.single.amount, 42);
  });
}
