import 'package:flutter/material.dart';
import '../models/account.dart';
import '../utils/card_styles.dart';
import '../utils/formatters.dart';
import 'amount_text.dart';

class AccountCard extends StatelessWidget {
  final Account account;
  final VoidCallback? onTap;

  /// Când e setat, apare un buton de editare separat — folosit pe ecrane
  /// unde tap-ul pe card face altceva (ex. deschide detaliul contului),
  /// ca editarea (nume/grup) să rămână accesibilă separat.
  final VoidCallback? onEdit;

  const AccountCard({
    super.key,
    required this.account,
    this.onTap,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isBank = account.kind == AccountKind.bank;

    return Container(
      decoration: BoxDecoration(
        gradient: accountCardGradient(account),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.white.withValues(alpha: 0.9),
                  child: Icon(
                    isBank ? Icons.account_balance : Icons.payments,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.name,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        isBank ? 'Cont bancar · non-cash' : 'Numerar',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                      ),
                    ],
                  ),
                ),
                AmountText(
                  formatAmount(account.balance, account.currency),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                if (onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.white),
                    visualDensity: VisualDensity.compact,
                    onPressed: onEdit,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
