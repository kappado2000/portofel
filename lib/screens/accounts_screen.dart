import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/account.dart';
import '../providers/money_provider.dart';
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
            ...personal.map((a) => _accountTile(context, provider, a)),
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
            ...family.map((a) => _accountTile(context, provider, a)),
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

  List<DropdownMenuItem<AccountGroup>> _groupItems() => const [
        DropdownMenuItem(
          value: AccountGroup.personal,
          child: Row(
            children: [
              Icon(Icons.person_outline, size: 18),
              SizedBox(width: 8),
              Text('Personal'),
            ],
          ),
        ),
        DropdownMenuItem(
          value: AccountGroup.family,
          child: Row(
            children: [
              Icon(Icons.family_restroom, size: 18),
              SizedBox(width: 8),
              Text('Familie'),
            ],
          ),
        ),
      ];

  Widget _accountTile(BuildContext context, MoneyProvider provider, Account account) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey(account.id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) => _confirmDelete(context, provider, account),
        background: Container(
          color: Colors.red,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        child: AccountCard(
          account: account,
          onTap: () => _editAccount(context, provider, account),
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, MoneyProvider provider, Account account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Șterge contul?'),
        content: Text('Vrei să ștergi contul "${account.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anulează')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Șterge')),
        ],
      ),
    );
    if (confirmed != true) return false;
    try {
      await provider.deleteAccount(account.id);
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
      return false;
    }
  }

  Future<void> _editAccount(BuildContext context, MoneyProvider provider, Account account) async {
    final controller = TextEditingController(text: account.name);
    AccountGroup group = account.group;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Editează contul'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nume cont'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AccountGroup>(
                initialValue: group,
                decoration: const InputDecoration(labelText: 'Grup'),
                items: _groupItems(),
                onChanged: (v) => setState(() => group = v ?? AccountGroup.personal),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anulează')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvează'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final newName = controller.text.trim();
      if (newName.isNotEmpty) {
        await provider.renameAccount(account.id, newName);
      }
      await provider.setAccountGroup(account.id, group);
    }
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
                  items: _groupItems(),
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
