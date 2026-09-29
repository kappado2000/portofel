import 'package:flutter/material.dart';

import '../models/money_transaction.dart';
import '../providers/money_provider.dart';
import '../screens/add_transaction_screen.dart';
import '../utils/categories.dart';
import '../utils/formatters.dart';
import 'amount_text.dart';

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
    final to = tx.toAccountId != null
        ? provider.accountById(tx.toAccountId!)
        : null;

    Color color;
    // Same dark shade the Venit/Plată buttons use for their own text, so the
    // amount in this list reads with the exact same color as those buttons.
    Color amountColor;
    // Transferurile primesc o tentă de fundal mai închisă decât venituri/plăți,
    // ca să se distingă clar drept o categorie separată, neutră.
    double backgroundAlpha = 0.14;
    String title;
    // Restul subtitlului, afișat după data/ora tranzacției și iconița
    // sugestivă (categorie, sau ruta de transfer).
    String subtitleRest;
    IconData subtitleIcon;
    String amountText;

    switch (tx.type) {
      case TxType.income:
        color = Colors.green.shade700;
        amountColor = Colors.green.shade900;
        title = tx.note.isNotEmpty
            ? tx.note
            : (tx.category.isEmpty ? 'Venit' : tx.category);
        subtitleRest = tx.category;
        subtitleIcon = categoryIcon(
          tx.category,
          fallback: Icons.savings_outlined,
        );
        amountText =
            '+${from != null ? formatAmount(tx.amount, from.currency) : tx.amount}';
        break;
      case TxType.expense:
        color = Colors.red.shade700;
        amountColor = Colors.red.shade900;
        title = tx.note.isNotEmpty
            ? tx.note
            : (tx.category.isEmpty ? 'Plată' : tx.category);
        subtitleRest = tx.category;
        subtitleIcon = categoryIcon(
          tx.category,
          fallback: Icons.payments_outlined,
        );
        amountText =
            '-${from != null ? formatAmount(tx.amount, from.currency) : tx.amount}';
        break;
      case TxType.transfer:
        color = Colors.blueGrey.shade800;
        amountColor = Colors.blueGrey.shade900;
        backgroundAlpha = 0.24;
        title = tx.note.isNotEmpty
            ? tx.note
            : '${from?.name ?? '?'} → ${to?.name ?? '?'}';
        subtitleRest = '${from?.name ?? '?'} → ${to?.name ?? '?'}';
        subtitleIcon = Icons.swap_horiz;
        amountText = from != null
            ? formatAmount(tx.amount, from.currency)
            : '${tx.amount}';
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
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: backgroundAlpha),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          dense: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddTransactionScreen(editing: tx),
            ),
          ),
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.2),
            child: Text(
              '$index',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(title, style: const TextStyle(fontSize: 13)),
          subtitle: Row(
            children: [
              Text(
                dateTimeFormat.format(tx.date),
                style: const TextStyle(fontSize: 11),
              ),
              const SizedBox(width: 5),
              Icon(subtitleIcon, size: 13, color: color),
              if (subtitleRest.isNotEmpty) ...[
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    subtitleRest,
                    style: const TextStyle(fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          trailing: AmountText(
            amountText,
            style: TextStyle(
              color: amountColor,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Anulează'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Șterge'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }
}
