import 'package:flutter/material.dart';
import '../models/money_transaction.dart';
import '../providers/money_provider.dart';
import '../utils/formatters.dart';

class TransactionTile extends StatelessWidget {
  final MoneyTransaction tx;
  final MoneyProvider provider;
  final VoidCallback? onDelete;

  const TransactionTile({
    super.key,
    required this.tx,
    required this.provider,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final from = provider.accountById(tx.fromAccountId);
    final to = tx.toAccountId != null ? provider.accountById(tx.toAccountId!) : null;

    IconData icon;
    Color color;
    String title;
    String subtitle;
    String amountText;

    switch (tx.type) {
      case TxType.income:
        icon = Icons.arrow_downward;
        color = Colors.green;
        title = tx.note.isNotEmpty ? tx.note : (tx.category.isEmpty ? 'Venit' : tx.category);
        subtitle = '${dateTimeFormat.format(tx.date)}${tx.category.isNotEmpty ? ' · ${tx.category}' : ''}';
        amountText = '+${from != null ? formatAmount(tx.amount, from.currency) : tx.amount}';
        break;
      case TxType.expense:
        icon = Icons.arrow_upward;
        color = Colors.red;
        title = tx.note.isNotEmpty ? tx.note : (tx.category.isEmpty ? 'Cheltuială' : tx.category);
        subtitle = '${dateTimeFormat.format(tx.date)}${tx.category.isNotEmpty ? ' · ${tx.category}' : ''}';
        amountText = '-${from != null ? formatAmount(tx.amount, from.currency) : tx.amount}';
        break;
      case TxType.transfer:
        icon = Icons.swap_horiz;
        color = Colors.blueGrey;
        title = tx.note.isNotEmpty ? tx.note : '${from?.name ?? '?'} → ${to?.name ?? '?'}';
        subtitle = '${dateTimeFormat.format(tx.date)} · ${from?.name ?? '?'} → ${to?.name ?? '?'}';
        amountText = from != null ? formatAmount(tx.amount, from.currency) : '${tx.amount}';
        break;
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, color: color),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            amountText,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
          if (onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}
