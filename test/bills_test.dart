import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:portofel/models/bill.dart';
import 'package:portofel/services/bill_http.dart';
import 'package:portofel/utils/formatters.dart';

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
      archived: true,
      indexFrom: 1200,
      indexTo: 1350,
      readingType: 'Autocitire',
      indexPeriod: '01.08.2026 – 31.08.2026',
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
    expect(restored.archived, isTrue);
    expect(
      billDatesLine(restored),
      'Factura din data de 01.09.2026 scadentă la 01.10.2026',
    );
    expect(restored.indexFrom, 1200);
    expect(restored.indexTo, 1350);
    expect(restored.readingType, 'Autocitire');
    expect(
      billIndexLine(restored),
      'Index 1.200 → 1.350 (autocitire, 01.08.2026 – 31.08.2026)',
    );
    expect(Bill.fromMap(bill.toMap()..remove('archived')).archived, isFalse);
  });

  test('isOverdue follows the provider payment, not the tick', () {
    Bill make({DateTime? due, bool paid = false, bool open = true}) => Bill(
      id: 'x',
      provider: BillProvider.hidroelectrica,
      contractCode: '1',
      amount: 10,
      balance: 10,
      dueDate: due,
      paid: paid,
      openAtProvider: open,
      fetchedAt: DateTime.now(),
    );
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    expect(make(due: yesterday).isOverdue, isTrue);
    expect(make(due: yesterday, paid: true).isOverdue, isTrue);
    expect(make(due: yesterday, open: false).isOverdue, isFalse);
    expect(make().isOverdue, isFalse);
    expect(
      make(due: DateTime.now().add(const Duration(days: 3))).isOverdue,
      isFalse,
    );
    expect(
      billProviderStatus(make(due: yesterday)),
      startsWith('Restantă la furnizor'),
    );
    expect(billProviderStatus(make(open: false)), 'Plătită la furnizor');
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

  test('findPdf locates a PDF as raw bytes or nested base64', () {
    final pdf = Uint8List.fromList(utf8.encode('%PDF-1.7 ${'x' * 200}'));
    expect(findPdf(JsonResponse(200, null, pdf)), pdf);

    final nested = {
      'result': {
        'Data': [
          {'name': 'factura.pdf', 'content': base64Encode(pdf)},
        ],
      },
    };
    expect(findPdf(JsonResponse(200, nested, Uint8List(0))), pdf);
    expect(
      findPdf(
        JsonResponse(200, {
          'file': 'data:application/pdf;base64,${base64Encode(pdf)}',
        }, Uint8List(0)),
      ),
      pdf,
    );
    expect(
      findPdf(JsonResponse(200, {'rembalance': '12,50'}, Uint8List(0))),
      isNull,
    );
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
