import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/account.dart';
import '../providers/money_provider.dart';
import '../utils/account_actions.dart';
import '../widgets/account_card.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MoneyProvider>();
    final personal = provider.personalAccounts;
    final family = provider.familyAccounts;

    return Scaffold(
      appBar: AppBar(title: const Text('Conturi')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline),
              const SizedBox(width: 8),
              Text('Personal', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          if (personal.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Niciun cont personal'),
            )
          else
            _reorderableGroup(context, provider, personal, AccountGroup.personal),
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(Icons.family_restroom),
              const SizedBox(width: 8),
              Text('Familie', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Conturile din acest grup apar separat, pe pagina "Conturi Familie".',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (family.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Niciun cont de familie'),
            )
          else
            _reorderableGroup(context, provider, family, AccountGroup.family),
          const SizedBox(height: 80),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addAccount(context, provider),
        icon: const Icon(Icons.add),
        label: const Text('Cont nou'),
      ),
    );
  }

  Widget _reorderableGroup(
    BuildContext context,
    MoneyProvider provider,
    List<Account> accounts,
    AccountGroup group,
  ) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: accounts.length,
      onReorderItem: (oldIndex, newIndex) => provider.reorderAccounts(group, oldIndex, newIndex),
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
              onTap: () => editAccountDialog(context, provider, account),
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

  Future<void> _addAccount(BuildContext context, MoneyProvider provider) async {
    final nameController = TextEditingController();
    final balanceController = TextEditingController(text: '0');
    AccountCurrency currency = AccountCurrency.eur;
    AccountKind kind = AccountKind.cash;
    AccountGroup group = AccountGroup.personal;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Cont nou'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nume cont'),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AccountCurrency>(
                  initialValue: currency,
                  decoration: const InputDecoration(labelText: 'Valută'),
                  items: const [
                    DropdownMenuItem(value: AccountCurrency.ron, child: Text('RON')),
                    DropdownMenuItem(value: AccountCurrency.eur, child: Text('EUR')),
                  ],
                  onChanged: (v) => setState(() => currency = v ?? AccountCurrency.ron),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AccountKind>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Tip'),
                  items: const [
                    DropdownMenuItem(value: AccountKind.cash, child: Text('Numerar (cash)')),
                    DropdownMenuItem(value: AccountKind.bank, child: Text('Cont bancar')),
                  ],
                  onChanged: (v) => setState(() => kind = v ?? AccountKind.cash),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AccountGroup>(
                  initialValue: group,
                  decoration: const InputDecoration(labelText: 'Grup'),
                  items: groupDropdownItems(),
                  onChanged: (v) => setState(() => group = v ?? AccountGroup.personal),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: balanceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Sold inițial'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anulează')),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                final balance = double.tryParse(balanceController.text.replaceAll(',', '.')) ?? 0;
                await provider.addAccount(
                  name: name,
                  currency: currency,
                  kind: kind,
                  initialBalance: balance,
                  group: group,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Adaugă'),
            ),
          ],
        ),
      ),
    );
  }
}
