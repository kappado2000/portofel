import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/account.dart';
import '../providers/money_provider.dart';
import '../widgets/account_card.dart';
import '../widgets/transaction_tile.dart';

class FamilyAccountsScreen extends StatelessWidget {
  const FamilyAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MoneyProvider>();
    final accounts = provider.familyAccounts;
    final accountIds = accounts.map((a) => a.id).toSet();
    final recentTx = provider.transactions
        .where((t) => accountIds.contains(t.fromAccountId) || accountIds.contains(t.toAccountId))
        .take(10)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.family_restroom),
            SizedBox(width: 8),
            Text('Conturi Familie'),
          ],
        ),
      ),
      body: accounts.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Niciun cont în grupul Familie.',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Poți muta un cont existent în acest grup din ecranul Conturi, '
                    'editând contul și alegând grupul "Familie".',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total familie', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 6),
                        Text(
                          '${provider.totalInRon(group: AccountGroup.family).toStringAsFixed(2)} lei  ≈  '
                          '${provider.totalInEur(group: AccountGroup.family).toStringAsFixed(2)} €',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ...accounts.map((a) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AccountCard(account: a),
                    )),
                const SizedBox(height: 24),
                Text('Tranzacții recente', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (recentTx.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Nicio tranzacție încă'),
                  )
                else
                  ...recentTx.map((tx) => TransactionTile(tx: tx, provider: provider)),
              ],
            ),
    );
  }
}
