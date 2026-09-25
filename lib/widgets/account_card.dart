import 'package:flutter/material.dart';
import '../models/account.dart';
import '../utils/formatters.dart';
import 'amount_text.dart';

class AccountCard extends StatelessWidget {
  final Account account;
  final VoidCallback? onTap;

  /// Mâner opțional de drag pentru reordonare (ex. un
  /// `ReorderableDragStartListener`), afișat la finalul rândului.
  final Widget? trailingHandle;

  /// Când e setat, apare un buton de editare separat — folosit pe ecrane
  /// unde tap-ul pe card face altceva (ex. deschide detaliul contului),
  /// ca editarea (nume/grup) să rămână accesibilă separat.
  final VoidCallback? onEdit;

  const AccountCard({
    super.key,
    required this.account,
    this.onTap,
    this.trailingHandle,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isBank = account.kind == AccountKind.bank;
    final isEur = account.currency == AccountCurrency.eur;
    final color = isBank
        ? Colors.indigo
        : (isEur ? Colors.teal : Colors.brown.shade400);

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(
                  isBank ? Icons.account_balance : Icons.payments,
                  color: color,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(account.name, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      isBank ? 'Cont bancar · non-cash' : 'Numerar',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              AmountText(
                formatAmount(account.balance, account.currency),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold, color: color),
              ),
              if (onEdit != null)
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: onEdit,
                ),
              ?trailingHandle,
            ],
          ),
        ),
      ),
    );
  }
}
