import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/account.dart';
import '../models/money_transaction.dart';
import '../providers/money_provider.dart';
import '../services/excel_export_service.dart';
import '../services/pdf_export_service.dart';
import '../utils/formatters.dart';
import '../widgets/amount_text.dart';
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
  final _exportButtonKey = GlobalKey();

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
            key: _exportButtonKey,
            icon: const Icon(Icons.ios_share),
            tooltip: 'Exportă documente',
            onPressed: () => _showExportMenu(context, provider, txs),
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
                      DropdownMenuItem(value: TxType.expense, child: Text('Plăți')),
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
                      return TransactionTile(tx: tx, provider: provider, index: index + 1);
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

  Rect? _exportButtonRect() {
    final box = _exportButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _showExportMenu(
    BuildContext context,
    MoneyProvider provider,
    List<MoneyTransaction> txs,
  ) async {
    if (txs.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Nu există tranzacții de exportat')));
      return;
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('Imprimare'),
              onTap: () => Navigator.pop(ctx, 'print'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Exportă PDF'),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.grid_on_outlined),
              title: const Text('Exportă Excel'),
              onTap: () => Navigator.pop(ctx, 'excel'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    try {
      switch (choice) {
        case 'print':
          await PdfExportService.printTransactions(transactions: txs, provider: provider);
          break;
        case 'pdf':
          await PdfExportService.sharePdf(
            transactions: txs,
            provider: provider,
            sharePositionOrigin: _exportButtonRect(),
          );
          break;
        case 'excel':
          await ExcelExportService.exportTransactions(
            transactions: txs,
            provider: provider,
            sharePositionOrigin: _exportButtonRect(),
          );
          break;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export eșuat: $e')));
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
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
          ),
          if (entries.isEmpty)
            AmountText(
              formatAmount(0, AccountCurrency.ron),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            )
          else
            ...entries.map(
              (e) => AmountText(
                formatAmount(e.value, e.key),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}
