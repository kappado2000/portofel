import 'package:flutter/material.dart';
import '../models/account.dart';
import '../providers/money_provider.dart';

/// Dialogul de editare a unui cont (nume + grup), reutilizat din ecranul
/// Conturi și din Conturi Familie.
Future<void> editAccountDialog(
  BuildContext context,
  MoneyProvider provider,
  Account account,
) async {
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
              items: groupDropdownItems(),
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
