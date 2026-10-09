import 'package:flutter_test/flutter_test.dart';
import 'package:portofel/models/bill.dart';
import 'package:portofel/services/bill_http.dart';

void main() {
  test('Bill round-trips through map serialization', () {
    final bill = Bill(
      id: Bill.buildId(BillProvider.eon, '100200', 'F123'),
      provider: BillProvider.eon,
      contractCode: '100200',
      address: 'Strada Mare 1, Iași',
      invoiceNumber: 'F123',
      amount: 250.5,
      balance: 100.25,
      issueDate: DateTime(2026, 9, 1),
      dueDate: DateTime(2026, 10, 1),
      paid: true,
      paidAt: DateTime(2026, 9, 20, 10, 30),
      fetchedAt: DateTime(2026, 9, 19),
      openAtProvider: false,
    );
    final restored = Bill.fromMap(bill.toMap());
    expect(restored.id, 'eon|100200|F123');
    expect(restored.provider, BillProvider.eon);
    expect(restored.address, bill.address);
    expect(restored.amount, 250.5);
    expect(restored.balance, 100.25);
    expect(restored.dueDate, bill.dueDate);
    expect(restored.paid, isTrue);
    expect(restored.paidAt, bill.paidAt);
    expect(restored.openAtProvider, isFalse);
  });

  test('isOverdue ignores paid bills and bills without due date', () {
    Bill make({DateTime? due, bool paid = false}) => Bill(
      id: 'x',
      provider: BillProvider.hidroelectrica,
      contractCode: '1',
      amount: 10,
      balance: 10,
      dueDate: due,
      paid: paid,
      fetchedAt: DateTime.now(),
    );
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    expect(make(due: yesterday).isOverdue, isTrue);
    expect(make(due: yesterday, paid: true).isOverdue, isFalse);
    expect(make().isOverdue, isFalse);
    expect(
      make(due: DateTime.now().add(const Duration(days: 3))).isOverdue,
      isFalse,
    );
  });

  test('parseAmount handles Romanian and standard formats', () {
    expect(parseAmount('1.234,56'), 1234.56);
    expect(parseAmount('234,5'), 234.5);
    expect(parseAmount('1234.56'), 1234.56);
    expect(parseAmount('1.234'), 1234);
    expect(parseAmount('123.45 lei'), 123.45);
    expect(parseAmount(87.3), 87.3);
    expect(parseAmount(12), 12);
    expect(parseAmount('-15,20'), -15.2);
    expect(parseAmount(null), 0);
    expect(parseAmount(''), 0);
  });

  test('parseBillDate handles provider date formats', () {
    expect(parseBillDate('20260316'), DateTime(2026, 3, 16));
    expect(parseBillDate('16/03/2026'), DateTime(2026, 3, 16));
    expect(parseBillDate('16.03.2026'), DateTime(2026, 3, 16));
    expect(parseBillDate('2026-03-16T00:00:00'), DateTime(2026, 3, 16));
    expect(parseBillDate(''), isNull);
    expect(parseBillDate(null), isNull);
    expect(parseBillDate('abc'), isNull);
  });
}
