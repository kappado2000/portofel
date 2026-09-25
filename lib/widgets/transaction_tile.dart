import 'package:flutter/material.dart';
import '../models/money_transaction.dart';
import '../providers/money_provider.dart';
import '../screens/add_transaction_screen.dart';
import '../utils/formatters.dart';

class TransactionTile extends StatelessWidget {
  final MoneyTransaction tx;
  final MoneyProvider provider;
  final int index;

  const TransactionTile({
    super.key,
    required this.tx,
    required this.provider,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final from = provider.accountById(tx.fromAccountId);
    final to = tx.toAccountId != null ? provider.accountById(tx.toAccountId!) : null;

    Color color;
    String title;
    String subtitle;
    String amountText;

    switch (tx.type) {
      case TxType.income:
        color = Colors.green;
        title = tx.note.isNotEmpty ? tx.note : (tx.category.isEmpty ? 'Venit' : tx.category);
        subtitle = '${dateTimeFormat.format(tx.date)}${tx.category.isNotEmpty ? ' · ${tx.category}' : ''}';
        amountText = '+${from != null ? formatAmount(tx.amount, from.currency) : tx.amount}';
        break;
      case TxType.expense:
        color = Colors.red;
        title = tx.note.isNotEmpty ? tx.note : (tx.category.isEmpty ? 'Plată' : tx.category);
        subtitle = '${dateTimeFormat.format(tx.date)}${tx.category.isNotEmpty ? ' · ${tx.category}' : ''}';
        amountText = '-${from != null ? formatAmount(tx.amount, from.currency) : tx.amount}';
        break;
      case TxType.transfer:
        color = Colors.blueGrey;
        title = tx.note.isNotEmpty ? tx.note : '${from?.name ?? '?'} → ${to?.name ?? '?'}';
        subtitle = '${dateTimeFormat.format(tx.date)} · ${from?.name ?? '?'} → ${to?.name ?? '?'}';
        amountText = from != null ? formatAmount(tx.amount, from.currency) : '${tx.amount}';
        break;
    }

    return Dismissible(
      key: ValueKey(tx.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => provider.deleteTransaction(tx.id),
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AddTransactionScreen(editing: tx)),
        ),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text(
            '$index',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Text(
          amountText,
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
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
    return confirmed ?? false;
  }
}
