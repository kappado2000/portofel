import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../models/bill.dart';
import '../providers/bills_provider.dart';
import '../utils/formatters.dart';

const _months = [
  'Ianuarie',
  'Februarie',
  'Martie',
  'Aprilie',
  'Mai',
  'Iunie',
  'Iulie',
  'August',
  'Septembrie',
  'Octombrie',
  'Noiembrie',
  'Decembrie',
];

String _lei(double v) => formatAmount(v, AccountCurrency.ron);

/// Istoricul facturilor achitate, grupat pe luna achitării.
class BillsHistoryScreen extends StatelessWidget {
  const BillsHistoryScreen({super.key});

  Future<void> _confirmDelete(BuildContext context, Bill bill) async {
    final provider = context.read<BillsProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ștergi factura din istoric?'),
        content: Text(
          '${billProviderLabel(bill.provider)}, ${_lei(bill.balance)}. '
          'Ștergerea nu poate fi anulată.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Renunță'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Șterge'),
          ),
        ],
      ),
    );
    if (ok == true) await provider.deleteFromHistory(bill);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BillsProvider>();
    final bills = provider.archivedBills;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Grupare pe lună, păstrând ordinea (cele mai recente primele).
    final months = <DateTime, List<Bill>>{};
    for (final b in bills) {
      final d = b.paidAt ?? b.fetchedAt;
      months.putIfAbsent(DateTime(d.year, d.month), () => []).add(b);
    }
    final total = bills.fold<double>(0, (s, b) => s + b.balance);

    return Scaffold(
      appBar: AppBar(title: const Text('Istoric facturi achitate')),
      body: bills.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Nicio factură salvată încă. Bifează facturile achitate și '
                  'apasă „Salvează în istoric”.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Text(
                  '${bills.length} facturi achitate · ${_lei(total)}',
                  style: textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                for (final entry in months.entries)
                  Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${_months[entry.key.month - 1]} ${entry.key.year}',
                                  style: textTheme.titleMedium,
                                ),
                              ),
                              Text(
                                _lei(
                                  entry.value.fold<double>(
                                    0,
                                    (s, b) => s + b.balance,
                                  ),
                                ),
                                style: textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                        for (final bill in entry.value) ...[
                          const Divider(height: 1),
                          _HistoryTile(
                            bill: bill,
                            onRestore: () => provider.restoreFromHistory(bill),
                            onDelete: () => _confirmDelete(context, bill),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final Bill bill;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _HistoryTile({
    required this.bill,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final paidAt = bill.paidAt;
    final place = bill.address.isNotEmpty
        ? bill.address
        : 'Cod ${bill.contractCode}';
    final details = [
      if (paidAt != null) 'Achitată ${dateFormat.format(paidAt)}',
      if (bill.invoiceNumber.isNotEmpty) 'Factura ${bill.invoiceNumber}',
    ].join(' · ');

    return ListTile(
      title: Text(
        '${billProviderLabel(bill.provider)} · ${_lei(bill.balance)}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(details.isEmpty ? place : '$details\n$place'),
      isThreeLine: details.isNotEmpty,
      trailing: PopupMenuButton<String>(
        onSelected: (v) => v == 'restore' ? onRestore() : onDelete(),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'restore', child: Text('Readu în listă')),
          PopupMenuItem(value: 'delete', child: Text('Șterge')),
        ],
      ),
    );
  }
}
