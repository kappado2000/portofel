import 'package:flutter_test/flutter_test.dart';
import 'package:portofel/models/account.dart';
import 'package:portofel/models/money_transaction.dart';

void main() {
  test('Account round-trips through map serialization', () {
    final account = Account(
      id: 'a1',
      name: 'Cash Euro',
      currency: AccountCurrency.eur,
      kind: AccountKind.cash,
      balance: 123.45,
    );
    final restored = Account.fromMap(account.toMap());
    expect(restored.id, account.id);
    expect(restored.name, account.name);
    expect(restored.currency, account.currency);
    expect(restored.kind, account.kind);
    expect(restored.balance, account.balance);
  });

  test('MoneyTransaction round-trips through map serialization', () {
    final tx = MoneyTransaction(
      id: 't1',
      type: TxType.transfer,
      date: DateTime(2026, 1, 1),
      fromAccountId: 'a1',
      toAccountId: 'a2',
      amount: 100,
      convertedAmount: 500,
      exchangeRate: 5,
      category: 'Transfer',
      note: 'test',
    );
    final restored = MoneyTransaction.fromMap(tx.toMap());
    expect(restored.type, TxType.transfer);
    expect(restored.convertedAmount, 500);
    expect(restored.exchangeRate, 5);
  });
}
