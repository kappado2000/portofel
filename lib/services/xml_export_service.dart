import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:xml/xml.dart';
import '../models/money_transaction.dart';
import '../providers/money_provider.dart';
import '../utils/formatters.dart';

class XmlExportService {
  static Future<void> exportTransactions({
    required List<MoneyTransaction> transactions,
    required MoneyProvider provider,
  }) async {
    final sorted = List<MoneyTransaction>.from(transactions)
      ..sort((a, b) => b.date.compareTo(a.date));

    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element('portofel', nest: () {
      builder.attribute('generatLa', DateTime.now().toIso8601String());

      builder.element('conturi', nest: () {
        for (final a in provider.accounts) {
          builder.element('cont', nest: () {
            builder.attribute('id', a.id);
            builder.attribute('nume', a.name);
            builder.attribute('valuta', currencyLabel(a.currency));
            builder.attribute('tip', a.kind.name);
            builder.attribute('sold', a.balance.toStringAsFixed(2));
          });
        }
      });

      builder.element('tranzactii', nest: () {
        for (final tx in sorted) {
          final from = provider.accountById(tx.fromAccountId);
          final to = tx.toAccountId != null ? provider.accountById(tx.toAccountId!) : null;
          builder.element('tranzactie', nest: () {
            builder.attribute('id', tx.id);
            builder.attribute('tip', tx.type.name);
            builder.attribute('data', tx.date.toIso8601String());
            builder.attribute('denumire', tx.note);
            builder.attribute('categorie', tx.category);
            builder.attribute('contSursa', from?.name ?? '');
            if (to != null) builder.attribute('contDestinatie', to.name);
            builder.attribute('suma', tx.amount.toStringAsFixed(2));
            if (tx.convertedAmount != null) {
              builder.attribute('sumaConvertita', tx.convertedAmount!.toStringAsFixed(2));
            }
            if (tx.exchangeRate != null) {
              builder.attribute('cursSchimb', tx.exchangeRate!.toStringAsFixed(4));
            }
          });
        }
      });
    });

    final xmlString = builder.buildDocument().toXmlString(pretty: true, indent: '  ');

    final dir = await getTemporaryDirectory();
    final fileName = 'portofel_export_${DateTime.now().millisecondsSinceEpoch}.xml';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(xmlString);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/xml')],
      subject: 'Export Portofel (XML)',
    );
  }
}
