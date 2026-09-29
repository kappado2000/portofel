import 'package:flutter/material.dart';

import '../models/account.dart';
import '../providers/money_provider.dart';

/// Dialogul de editare a unui cont — toate datele acestuia (nume, valută,
/// tip, grup, sold), reutilizat din ecranul Conturi și din Conturi Familie.
Future<void> editAccountDialog(
  BuildContext context,
  MoneyProvider provider,
  Account account,
) async {
  final nameController = TextEditingController(text: account.name);
  final balanceController = TextEditingController(
    text: account.balance.toStringAsFixed(2),
  );
  AccountCurrency currency = account.currency;
  AccountKind kind = account.kind;
  AccountGroup group = account.group;

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Editează contul'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nume cont'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AccountCurrency>(
                initialValue: currency,
                decoration: const InputDecoration(labelText: 'Valută'),
                items: const [
                  DropdownMenuItem(
                    value: AccountCurrency.ron,
                    child: Text('RON'),
                  ),
                  DropdownMenuItem(
                    value: AccountCurrency.eur,
                    child: Text('EUR'),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => currency = v ?? AccountCurrency.ron),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AccountKind>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Tip'),
                items: const [
                  DropdownMenuItem(
                    value: AccountKind.cash,
                    child: Text('Numerar (cash)'),
                  ),
                  DropdownMenuItem(
                    value: AccountKind.bank,
                    child: Text('Cont bancar'),
                  ),
                ],
                onChanged: (v) => setState(() => kind = v ?? AccountKind.cash),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AccountGroup>(
                initialValue: group,
                decoration: const InputDecoration(labelText: 'Grup'),
                items: groupDropdownItems(),
                onChanged: (v) =>
                    setState(() => group = v ?? AccountGroup.personal),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: balanceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Sold'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Anulează'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvează'),
          ),
        ],
      ),
    ),
  );

  if (result == true) {
    final newName = nameController.text.trim();
    final newBalance =
        double.tryParse(balanceController.text.replaceAll(',', '.')) ??
        account.balance;
    await provider.updateAccount(
      account.id,
      name: newName.isNotEmpty ? newName : account.name,
      group: group,
      currency: currency,
      kind: kind,
      balance: newBalance,
    );
  }
}

/// Confirmă și execută ștergerea unui cont; întoarce true dacă a fost șters
/// (util ca `confirmDismiss` pentru un `Dismissible`).
Future<bool> confirmDeleteAccount(
  BuildContext context,
  MoneyProvider provider,
  Account account,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Șterge contul?'),
      content: Text('Vrei să ștergi contul "${account.name}"?'),
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

List<DropdownMenuItem<AccountGroup>> groupDropdownItems() => const [
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
