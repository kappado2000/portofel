import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/money_provider.dart';
import '../utils/formatters.dart';
import '../widgets/amount_text.dart';
import '../widgets/transaction_tile.dart';
import 'add_transaction_screen.dart';

/// Ecranul unui cont individual — funcționează ca un cont "adevărat":
/// venituri, plăți, transfer și istoricul propriu al acelui cont.
class AccountDetailScreen extends StatelessWidget {
  final String accountId;

  const AccountDetailScreen({super.key, required this.accountId});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MoneyProvider>();
    final account = provider.accountById(accountId);

    if (account == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cont')),
        body: const Center(child: Text('Acest cont nu mai există.')),
      );
    }

    final history = provider.transactions
        .where((t) => t.fromAccountId == account.id || t.toAccountId == account.id)
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(account.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sold curent', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  AmountText(
                    formatAmount(account.balance, account.currency),
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
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.green.withValues(alpha: 0.15),
                    foregroundColor: Colors.green.shade800,
                    side: BorderSide(color: Colors.green.shade400),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddTransactionScreen(initialTab: 0, initialAccountId: account.id),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Venit'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.red.withValues(alpha: 0.15),
                    foregroundColor: Colors.red.shade800,
                    side: BorderSide(color: Colors.red.shade400),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddTransactionScreen(initialTab: 1, initialAccountId: account.id),
                    ),
                  ),
                  icon: const Icon(Icons.remove),
                  label: const Text('Plată'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddTransactionScreen(initialTab: 2, initialAccountId: account.id),
                ),
              ),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Transfer / Schimb valutar'),
            ),
          ),
          const SizedBox(height: 24),
          Text('Istoric', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (history.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Nicio tranzacție pentru acest cont încă'),
            )
          else
            ...history.indexed.map(
              (e) => TransactionTile(tx: e.$2, provider: provider, index: e.$1 + 1),
            ),
        ],
      ),
    );
  }
}
