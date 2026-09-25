import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/account.dart';
import '../providers/money_provider.dart';
import '../utils/account_actions.dart';
import '../utils/formatters.dart';
import '../widgets/account_card.dart';
import '../widgets/amount_text.dart';
import '../widgets/transaction_tile.dart';
import 'account_detail_screen.dart';

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
                        AmountText(
                          '${formatNumber(provider.totalInEur(group: AccountGroup.family))} €',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '≈ ${formatNumber(provider.totalInRon(group: AccountGroup.family))} lei',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _reorderableFamilyList(context, provider, accounts),
                const SizedBox(height: 24),
                Text('Tranzacții recente', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (recentTx.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Nicio tranzacție încă'),
                  )
                else
                  ...recentTx.indexed.map(
                    (e) => TransactionTile(tx: e.$2, provider: provider, index: e.$1 + 1),
                  ),
              ],
            ),
    );
  }

  Widget _reorderableFamilyList(
    BuildContext context,
    MoneyProvider provider,
    List<Account> accounts,
  ) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: accounts.length,
      onReorder: (oldIndex, newIndex) =>
          provider.reorderAccounts(AccountGroup.family, oldIndex, newIndex),
      itemBuilder: (context, index) {
        final account = accounts[index];
        return Padding(
          key: ValueKey(account.id),
          padding: const EdgeInsets.only(bottom: 8),
          child: Dismissible(
            key: ValueKey('dismiss_${account.id}'),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) => confirmDeleteAccount(context, provider, account),
            background: Container(
              color: Colors.red,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            child: AccountCard(
              account: account,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AccountDetailScreen(accountId: account.id),
                ),
              ),
              onEdit: () => editAccountDialog(context, provider, account),
              trailingHandle: ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.drag_handle),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
