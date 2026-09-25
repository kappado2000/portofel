import 'package:flutter/material.dart';
import '../models/account.dart';
import '../utils/formatters.dart';
import 'amount_text.dart';

class AccountCard extends StatelessWidget {
  final Account account;
  final VoidCallback? onTap;

  const AccountCard({super.key, required this.account, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isBank = account.kind == AccountKind.bank;
    final isEur = account.currency == AccountCurrency.eur;
    final color = isBank
        ? Colors.indigo
        : (isEur ? Colors.teal : Colors.orange);

    return Card(
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
            ],
          ),
        ),
      ),
    );
  }
}
