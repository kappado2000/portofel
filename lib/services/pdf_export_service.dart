import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show Rect;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/money_transaction.dart';
import '../providers/money_provider.dart';
import '../utils/formatters.dart';

class PdfExportService {
  static Future<pw.Document> _buildDocument({
    required List<MoneyTransaction> transactions,
    required MoneyProvider provider,
    String title = 'Portofel - Istoric tranzacții',
  }) async {
    final fontData = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final ttf = pw.Font.ttf(fontData);
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: ttf, bold: ttf));

    final sorted = List<MoneyTransaction>.from(transactions)
      ..sort((a, b) => b.date.compareTo(a.date));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text(
              'Generat la: ${dateTimeFormat.format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 12),
          ],
        ),
        build: (ctx) => [
          _accountsSummary(provider),
          pw.SizedBox(height: 16),
          pw.Text('Tranzacții (${sorted.length})',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          _transactionsTable(sorted, provider),
        ],
      ),
    );

    return doc;
  }

  /// Deschide fluxul nativ de imprimare (alegere imprimantă / AirPrint).
  static Future<void> printTransactions({
    required List<MoneyTransaction> transactions,
    required MoneyProvider provider,
  }) async {
    final doc = await _buildDocument(transactions: transactions, provider: provider);
    await Printing.layoutPdf(onLayout: (_) => doc.save());
  }

  /// Partajează/salvează fișierul PDF (meniul de share al sistemului).
  static Future<void> sharePdf({
    required List<MoneyTransaction> transactions,
    required MoneyProvider provider,
    Rect? sharePositionOrigin,
  }) async {
    final doc = await _buildDocument(transactions: transactions, provider: provider);
    final bytes = await doc.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'portofel_export_${DateTime.now().millisecondsSinceEpoch}.pdf',
      bounds: sharePositionOrigin,
    );
  }

  static pw.Widget _accountsSummary(MoneyProvider provider) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _cell('Cont', bold: true),
            _cell('Valută', bold: true),
            _cell('Sold', bold: true),
          ],
        ),
        ...provider.accounts.map(
          (a) => pw.TableRow(children: [
            _cell(a.name),
            _cell(currencyLabel(a.currency)),
            _cell(formatAmount(a.balance, a.currency)),
          ]),
        ),
      ],
    );
  }

  static pw.Widget _transactionsTable(List<MoneyTransaction> txs, MoneyProvider provider) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(1.4),
        2: pw.FlexColumnWidth(2.6),
        3: pw.FlexColumnWidth(1.8),
        4: pw.FlexColumnWidth(1.6),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _cell('Data', bold: true),
            _cell('Tip', bold: true),
            _cell('Denumire', bold: true),
            _cell('Cont', bold: true),
            _cell('Sumă', bold: true),
          ],
        ),
        ...txs.map((tx) => _txRow(tx, provider)),
      ],
    );
  }

  static pw.TableRow _txRow(MoneyTransaction tx, MoneyProvider provider) {
    final from = provider.accountById(tx.fromAccountId);
    final to = tx.toAccountId != null ? provider.accountById(tx.toAccountId!) : null;

    String typeLabel;
    String accountLabel;
    String amountLabel;

    switch (tx.type) {
      case TxType.income:
        typeLabel = 'Venit';
        accountLabel = from?.name ?? '?';
        amountLabel = '+${from != null ? formatAmount(tx.amount, from.currency) : tx.amount}';
        break;
      case TxType.expense:
        typeLabel = 'Plată';
        accountLabel = from?.name ?? '?';
        amountLabel = '-${from != null ? formatAmount(tx.amount, from.currency) : tx.amount}';
        break;
      case TxType.transfer:
        typeLabel = 'Transfer';
        accountLabel = '${from?.name ?? '?'} → ${to?.name ?? '?'}';
        amountLabel = from != null ? formatAmount(tx.amount, from.currency) : '${tx.amount}';
        break;
    }

    final name = tx.note.isNotEmpty ? tx.note : (tx.category.isEmpty ? typeLabel : tx.category);

    return pw.TableRow(children: [
      _cell(dateTimeFormat.format(tx.date)),
      _cell(typeLabel),
      _cell(name),
      _cell(accountLabel),
      _cell(amountLabel),
    ]);
  }

  static pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(
          text,
          style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
        ),
      );
}
