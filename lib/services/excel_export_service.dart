import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/widgets.dart' show Rect;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/money_transaction.dart';
import '../providers/money_provider.dart';
import '../utils/formatters.dart';

class ExcelExportService {
  static Future<void> exportTransactions({
    required List<MoneyTransaction> transactions,
    required MoneyProvider provider,
    Rect? sharePositionOrigin,
  }) async {
    final sorted = List<MoneyTransaction>.from(transactions)
      ..sort((a, b) => b.date.compareTo(a.date));

    final workbook = Excel.createExcel();
    final defaultSheetName = workbook.getDefaultSheet();

    final accountsSheet = workbook['Conturi'];
    accountsSheet.appendRow([
      TextCellValue('Nume'),
      TextCellValue('Valută'),
      TextCellValue('Tip'),
      TextCellValue('Sold'),
    ]);
    for (final a in provider.accounts) {
      accountsSheet.appendRow([
        TextCellValue(a.name),
        TextCellValue(currencyLabel(a.currency)),
        TextCellValue(a.kind.name),
        DoubleCellValue(a.balance),
      ]);
    }

    final txSheet = workbook['Tranzacții'];
    txSheet.appendRow([
      TextCellValue('Data'),
      TextCellValue('Tip'),
      TextCellValue('Denumire'),
      TextCellValue('Categorie'),
      TextCellValue('Cont sursă'),
      TextCellValue('Cont destinație'),
      TextCellValue('Sumă'),
      TextCellValue('Sumă convertită'),
      TextCellValue('Curs schimb'),
    ]);
    for (final tx in sorted) {
      final from = provider.accountById(tx.fromAccountId);
      final to = tx.toAccountId != null ? provider.accountById(tx.toAccountId!) : null;
      txSheet.appendRow([
        TextCellValue(dateTimeFormat.format(tx.date)),
        TextCellValue(_typeLabel(tx.type)),
        TextCellValue(tx.note),
        TextCellValue(tx.category),
        TextCellValue(from?.name ?? ''),
        TextCellValue(to?.name ?? ''),
        DoubleCellValue(tx.amount),
        if (tx.convertedAmount != null) DoubleCellValue(tx.convertedAmount!) else TextCellValue(''),
        if (tx.exchangeRate != null) DoubleCellValue(tx.exchangeRate!) else TextCellValue(''),
      ]);
    }

    if (defaultSheetName != null &&
        defaultSheetName != 'Conturi' &&
        defaultSheetName != 'Tranzacții') {
      workbook.delete(defaultSheetName);
    }

    final bytes = workbook.encode();
    if (bytes == null) return;

    final dir = await getTemporaryDirectory();
    final fileName = 'portofel_export_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [
        XFile(
          file.path,
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ],
      subject: 'Export Portofel (Excel)',
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  static String _typeLabel(TxType type) => switch (type) {
        TxType.income => 'Venit',
        TxType.expense => 'Plată',
        TxType.transfer => 'Transfer',
      };
}
