import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../models/bill.dart';
import '../providers/bills_provider.dart';
import '../services/bill_http.dart';
import '../services/eon_api.dart';
import '../utils/formatters.dart';

/// Cere codul de verificare trimis de E.ON. Întoarce `null` la renunțare.
Future<String?> askEonMfaCode(
  BuildContext context,
  EonMfaRequired challenge,
  String username,
) {
  final controller = TextEditingController();
  final via = challenge.type == 'SMS' ? 'SMS' : 'email';
  final to = challenge.recipient.isEmpty ? '' : ' la ${challenge.recipient}';
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Cod de verificare E.ON'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pentru contul $username, E.ON a trimis un cod prin $via$to. '
            'Introdu-l mai jos.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Cod',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Renunță'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Continuă'),
        ),
      ],
    ),
  );
}

/// Descarcă PDF-ul facturii de la furnizor și îl deschide în aplicație.
Future<void> openBillPdf(BuildContext context, Bill bill) async {
  final provider = context.read<BillsProvider>();
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  Uint8List? pdf;
  String? error;
  try {
    pdf = await provider.fetchPdf(
      bill,
      askMfaCode: (challenge, username) => context.mounted
          ? askEonMfaCode(context, challenge, username)
          : Future.value(),
    );
  } on BillFetchException catch (e) {
    error = e.message;
  } catch (_) {
    error = 'Factura nu a putut fi descărcată.';
  }
  navigator.pop();

  if (pdf == null) {
    messenger.showSnackBar(SnackBar(content: Text(error ?? '')));
    return;
  }
  final bytes = pdf;
  await navigator.push(
    MaterialPageRoute(
      builder: (_) => BillPdfScreen(bill: bill, pdf: bytes),
    ),
  );
}

class BillPdfScreen extends StatelessWidget {
  final Bill bill;
  final Uint8List pdf;

  const BillPdfScreen({super.key, required this.bill, required this.pdf});

  @override
  Widget build(BuildContext context) {
    final name = billProviderLabel(bill.provider);
    final number = bill.invoiceNumber.isEmpty ? 'factura' : bill.invoiceNumber;
    return Scaffold(
      appBar: AppBar(title: Text('$name · ${billDatesLine(bill)}')),
      body: PdfPreview(
        build: (_) async => pdf,
        pdfFileName: '${name}_$number.pdf',
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
      ),
    );
  }
}
