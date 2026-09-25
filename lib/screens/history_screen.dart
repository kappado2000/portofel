import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/account.dart';
import '../models/money_transaction.dart';
import '../providers/money_provider.dart';
import '../services/pdf_export_service.dart';
import '../services/xml_export_service.dart';
import '../utils/formatters.dart';
import '../widgets/transaction_tile.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  TxType? _filterType;
  String? _filterAccountId;
  DateTimeRange? _dateRange;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MoneyProvider>();
    var txs = provider.transactions;

    if (_filterType != null) {
      txs = txs.where((t) => t.type == _filterType).toList();
    }
    if (_filterAccountId != null) {
      txs = txs
          .where((t) => t.fromAccountId == _filterAccountId || t.toAccountId == _filterAccountId)
          .toList();
    }
    if (_dateRange != null) {
      final start = DateTime(_dateRange!.start.year, _dateRange!.start.month, _dateRange!.start.day);
      final end = DateTime(_dateRange!.end.year, _dateRange!.end.month, _dateRange!.end.day, 23, 59, 59);
      txs = txs.where((t) => !t.date.isBefore(start) && !t.date.isAfter(end)).toList();
    }

    final incomeByCurrency = <AccountCurrency, double>{};
    final expenseByCurrency = <AccountCurrency, double>{};
    for (final t in txs) {
      final account = provider.accountById(t.fromAccountId);
      if (account == null) continue;
      if (t.type == TxType.income) {
        incomeByCurrency[account.currency] = (incomeByCurrency[account.currency] ?? 0) + t.amount;
      } else if (t.type == TxType.expense) {
        expenseByCurrency[account.currency] = (expenseByCurrency[account.currency] ?? 0) + t.amount;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Istoric tranzacții'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Exportă PDF',
            onPressed: txs.isEmpty ? null : () => _exportPdf(context, provider, txs),
          ),
          IconButton(
            icon: const Icon(Icons.code_outlined),
            tooltip: 'Exportă XML',
            onPressed: txs.isEmpty ? null : () => _exportXml(context, provider, txs),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<TxType?>(
                    initialValue: _filterType,
                    decoration: const InputDecoration(labelText: 'Tip', isDense: true),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Toate')),
                      DropdownMenuItem(value: TxType.income, child: Text('Venituri')),
                      DropdownMenuItem(value: TxType.expense, child: Text('Cheltuieli')),
                      DropdownMenuItem(value: TxType.transfer, child: Text('Transferuri')),
                    ],
                    onChanged: (v) => setState(() => _filterType = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _filterAccountId,
                    decoration: const InputDecoration(labelText: 'Cont', isDense: true),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Toate')),
                      ...provider.accounts.map(
                        (a) => DropdownMenuItem(value: a.id, child: Text(a.name)),
                      ),
                    ],
                    onChanged: (v) => setState(() => _filterAccountId = v),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.date_range, size: 18),
                    label: Text(
                      _dateRange == null
                          ? 'Orice perioadă'
                          : '${dateFormat.format(_dateRange!.start)} - ${dateFormat.format(_dateRange!.end)}',
                    ),
                    onPressed: _pickDateRange,
                  ),
                ),
                if (_dateRange != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Șterge perioada',
                    onPressed: () => setState(() => _dateRange = null),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: _TotalChip(
                    label: 'Total venituri',
                    byCurrency: incomeByCurrency,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TotalChip(
                    label: 'Total cheltuieli',
                    byCurrency: expenseByCurrency,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: txs.isEmpty
                ? const Center(child: Text('Nicio tranzacție găsită'))
                : ListView.builder(
                    itemCount: txs.length,
                    itemBuilder: (context, index) {
                      final tx = txs[index];
                      return TransactionTile(
                        tx: tx,
                        provider: provider,
                        onDelete: () => _confirmDelete(context, provider, tx.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _dateRange,
    );
    if (picked != null) setState(() => _dateRange = picked);
  }

  Future<void> _confirmDelete(BuildContext context, MoneyProvider provider, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Șterge tranzacția?'),
        content: const Text('Soldul contului va fi actualizat corespunzător.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anulează')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Șterge')),
        ],
      ),
    );
    if (confirmed == true) {
      await provider.deleteTransaction(id);
    }
  }

  Future<void> _exportPdf(
    BuildContext context,
    MoneyProvider provider,
    List<MoneyTransaction> txs,
  ) async {
    try {
      await PdfExportService.exportTransactions(transactions: txs, provider: provider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export PDF eșuat: $e')));
      }
    }
  }

  Future<void> _exportXml(
    BuildContext context,
    MoneyProvider provider,
    List<MoneyTransaction> txs,
  ) async {
    try {
      await XmlExportService.exportTransactions(transactions: txs, provider: provider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export XML eșuat: $e')));
      }
    }
  }
}

class _TotalChip extends StatelessWidget {
  final String label;
  final Map<AccountCurrency, double> byCurrency;
  final Color color;

  const _TotalChip({required this.label, required this.byCurrency, required this.color});

  @override
  Widget build(BuildContext context) {
    final entries = byCurrency.entries.where((e) => e.value != 0).toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          if (entries.isEmpty)
            Text(
              formatAmount(0, AccountCurrency.ron),
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            )
          else
            ...entries.map(
              (e) => Text(
                formatAmount(e.value, e.key),
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}
