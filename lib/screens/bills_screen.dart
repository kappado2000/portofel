import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../models/bill.dart';
import '../providers/bills_provider.dart';
import '../services/eon_api.dart';
import '../utils/card_styles.dart';
import '../utils/formatters.dart';
import '../widgets/bill_index_badge.dart';
import 'bill_pdf_screen.dart';
import 'bills_history_screen.dart';

String _lei(double v) => formatAmount(v, AccountCurrency.ron);

class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  @override
  void initState() {
    super.initState();
    // Actualizare automată la deschiderea paginii.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.read<BillsProvider>().hasAnyAccount) _refresh();
    });
  }

  Future<void> _refresh() =>
      context.read<BillsProvider>().refresh(askMfaCode: _askMfaCode);

  Future<String?> _askMfaCode(EonMfaRequired challenge, String username) async {
    if (!mounted) return null;
    return askEonMfaCode(context, challenge, username);
  }

  /// Formularul unui cont: cu [account] îl modifică pe acela, fără el
  /// adaugă un cont nou la furnizorul [p].
  Future<void> _editAccount(BillProvider p, {BillAccount? account}) async {
    final provider = context.read<BillsProvider>();
    final userCtrl = TextEditingController(text: account?.username ?? '');
    final passCtrl = TextEditingController(
      text: account == null ? '' : await provider.passwordFor(account.id) ?? '',
    );
    if (!mounted) return;
    final connected = account != null;
    var obscure = true;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(
            account == null
                ? 'Cont nou ${billProviderLabel(p)}'
                : 'Cont ${billProviderLabel(p)}',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: userCtrl,
                autocorrect: false,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: switch (p) {
                    BillProvider.hidroelectrica => 'Utilizator iHidro',
                    BillProvider.eon => 'Email Myline',
                    BillProvider.electrica => 'Email MyElectrica',
                  },
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: obscure,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Parolă',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setLocal(() => obscure = !obscure),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Datele se salvează automat și rămân până la '
                'deconectare, doar pe acest dispozitiv, în stocarea '
                'securizată a sistemului. Sunt trimise numai '
                'furnizorului.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            if (connected)
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'remove'),
                child: const Text('Deconectează'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Renunță'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('Salvează'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'remove') {
      await provider.removeAccount(account!.id);
      return;
    }
    if (userCtrl.text.trim().isEmpty || passCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completează utilizatorul și parola.')),
      );
      return;
    }
    await provider.saveAccount(
      id: account?.id,
      provider: p,
      username: userCtrl.text,
      password: passCtrl.text,
    );
    if (mounted) await _refresh();
  }

  /// Lista conturilor conectate, cu adăugare și modificare.
  Future<void> _manageAccounts() async {
    final choice = await showDialog<(BillProvider, BillAccount?)>(
      context: context,
      builder: (ctx) {
        final provider = ctx.watch<BillsProvider>();
        return AlertDialog(
          title: const Text('Conturi furnizori'),
          contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final p in BillProvider.values) ...[
                  for (final a in provider.accountsFor(p))
                    ListTile(
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: billProviderScheme(
                          ctx,
                          p,
                        ).primaryContainer,
                        foregroundColor: billProviderScheme(
                          ctx,
                          p,
                        ).onPrimaryContainer,
                        child: Text(billProviderLabel(p)[0]),
                      ),
                      title: Text(a.username),
                      subtitle: Text(billProviderLabel(p)),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => Navigator.pop(ctx, (p, a)),
                    ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: Text('Adaugă cont ${billProviderLabel(p)}'),
                    onTap: () => Navigator.pop(ctx, (p, null)),
                  ),
                  if (p != BillProvider.values.last) const Divider(height: 1),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Închide'),
            ),
          ],
        );
      },
    );
    if (choice == null || !mounted) return;
    await _editAccount(choice.$1, account: choice.$2);
  }

  Future<void> _saveToHistory() async {
    final provider = context.read<BillsProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Salvează în istoric'),
        content: Text(
          '${provider.paidCount} facturi bifate, în total '
          '${_lei(provider.paidTotal())}, vor fi mutate în istoricul '
          'facturilor achitate, cu data achitării '
          '${dateFormat.format(DateTime.now())}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Renunță'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvează'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await provider.archivePaid();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Facturile au fost salvate în istoric.'),
        action: SnackBarAction(label: 'Vezi', onPressed: _openHistory),
      ),
    );
  }

  void _openHistory() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const BillsHistoryScreen()),
  );

  Future<void> _chooseStartDate() async {
    final provider = context.read<BillsProvider>();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: provider.startDate,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      helpText: 'Afișează facturile emise începând cu',
    );
    if (picked == null || !mounted) return;
    await provider.setStartDate(picked);
    if (mounted) await _refresh();
  }

  Future<void> _chooseAddresses() async {
    final provider = context.read<BillsProvider>();
    final all = [
      for (final p in BillProvider.values)
        for (final loc in provider.locationsFor(p)) (p, loc.$1, loc.$2),
    ];
    final hidden = provider.hiddenLocations;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final shown = all
              .where(
                (l) => !hidden.contains(BillsProvider.locationKey(l.$1, l.$2)),
              )
              .length;
          return AlertDialog(
            title: const Text('Adrese afișate'),
            contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
            content: SizedBox(
              width: 420,
              child: all.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
                      child: Text(
                        'Nu se cunosc încă adresele. Conectează un cont și '
                        'actualizează facturile, apoi revino aici.',
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        CheckboxListTile(
                          tristate: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('Toate adresele'),
                          value: shown == all.length
                              ? true
                              : (shown == 0 ? false : null),
                          onChanged: (_) => setLocal(() {
                            if (shown == all.length) {
                              hidden.addAll(
                                all.map(
                                  (l) => BillsProvider.locationKey(l.$1, l.$2),
                                ),
                              );
                            } else {
                              hidden.clear();
                            }
                          }),
                        ),
                        const Divider(height: 1),
                        for (final l in all)
                          CheckboxListTile(
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(l.$3.isEmpty ? 'Cod ${l.$2}' : l.$3),
                            subtitle: Text(
                              '${billProviderLabel(l.$1)} · cod ${l.$2}',
                            ),
                            value: !hidden.contains(
                              BillsProvider.locationKey(l.$1, l.$2),
                            ),
                            onChanged: (v) => setLocal(() {
                              final key = BillsProvider.locationKey(l.$1, l.$2);
                              v == true ? hidden.remove(key) : hidden.add(key);
                            }),
                          ),
                      ],
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Renunță'),
              ),
              if (all.isNotEmpty)
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Aplică'),
                ),
            ],
          );
        },
      ),
    );
    if (ok != true || !mounted) return;
    await provider.setHiddenLocations(hidden);
    // Adresele reafișate nu au fost interogate cât au stat ascunse.
    if (mounted) await _refresh();
  }

  Future<void> _removePaid() async {
    final provider = context.read<BillsProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Șterge facturile bifate?'),
        content: Text(
          '${provider.paidCount} facturi bifate, în total '
          '${_lei(provider.paidTotal())}, vor fi scoase din listă.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Renunță'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Șterge'),
          ),
        ],
      ),
    );
    if (ok == true) await provider.removePaid();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BillsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Facturi'),
        actions: [
          if (provider.refreshing)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizează',
              onPressed: provider.hasAnyAccount ? _refresh : null,
            ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Istoric facturi achitate',
            onPressed: _openHistory,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'accounts':
                  _manageAccounts();
                case 'start':
                  _chooseStartDate();
                case 'addresses':
                  _chooseAddresses();
                case 'clear':
                  _removePaid();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'accounts',
                child: Text('Conturi furnizori'),
              ),
              const PopupMenuItem(
                value: 'start',
                child: Text('Facturi începând cu…'),
              ),
              const PopupMenuItem(
                value: 'addresses',
                child: Text('Adrese afișate'),
              ),
              PopupMenuItem(
                value: 'clear',
                enabled: provider.paidCount > 0,
                child: const Text('Șterge facturile bifate'),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _TotalsCard(
              unpaid: provider.unpaidTotal(),
              paid: provider.paidTotal(),
              onSave: provider.paidCount > 0 ? _saveToHistory : null,
            ),
            if (provider.overdueBills.isNotEmpty) ...[
              const SizedBox(height: 12),
              _OverdueBanner(bills: provider.overdueBills),
            ],
            const SizedBox(height: 16),
            for (final p in BillProvider.values)
              if (!provider.hasAnyAccount || provider.isConnected(p))
                _ProviderSection(
                  billProvider: p,
                  onConnect: () => _editAccount(p),
                ),
          ],
        ),
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  final double unpaid;
  final double paid;

  /// `null` când nu e nicio factură bifată: butonul apare dezactivat.
  final VoidCallback? onSave;

  const _TotalsCard({
    required this.unpaid,
    required this.paid,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, double value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _lei(value),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: heroCardDecoration(),
      child: Row(
        children: [
          cell('Nebifate', unpaid),
          const SizedBox(width: 20),
          cell('Total bifate', paid),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: onSave,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.white24,
              disabledForegroundColor: Colors.white60,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Salvează\nîn istoric',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// Avertizare: facturi pe care banca nu le-a plătit până la scadență.
class _OverdueBanner extends StatelessWidget {
  final List<Bill> bills;

  const _OverdueBanner({required this.bills});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = bills.fold<double>(0, (s, b) => s + b.balance);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: DefaultTextStyle.merge(
              style: TextStyle(color: scheme.onErrorContainer),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bills.length == 1
                        ? 'O factură restantă la furnizor: ${_lei(total)}'
                        : '${bills.length} facturi restante la furnizor: '
                              '${_lei(total)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  for (final b in bills)
                    Text(
                      '${billProviderLabel(b.provider)} · '
                      '${b.address.isEmpty ? 'cod ${b.contractCode}' : b.address}'
                      ' · ${_lei(b.balance)} · scadentă la '
                      '${dateFormat.format(b.dueDate!)}'
                      '${b.archived ? ' (în istoric)' : ''}',
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderSection extends StatelessWidget {
  final BillProvider billProvider;
  final VoidCallback onConnect;

  const _ProviderSection({required this.billProvider, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BillsProvider>();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final name = billProviderLabel(billProvider);
    final bills = provider.billsFor(billProvider);
    final connected = provider.isConnected(billProvider);
    final errors = provider.errorsFor(billProvider);
    final accountCount = provider.accountsFor(billProvider).length;
    final updated = provider.lastUpdated(billProvider);
    final locations = provider.visibleLocationsFor(billProvider);

    final paidCount = bills.where((b) => b.paid).length;
    final tint = billProviderScheme(context, billProvider);
    final bool? sectionValue = bills.isEmpty || paidCount == 0
        ? false
        : (paidCount == bills.length ? true : null);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: tint.primary.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: tint.primaryContainer,
            padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
            child: Row(
              children: [
                Checkbox(
                  tristate: true,
                  activeColor: tint.primary,
                  checkColor: tint.onPrimary,
                  value: sectionValue,
                  onChanged: bills.isEmpty
                      ? null
                      : (_) => provider.setSectionPaid(
                          billProvider,
                          sectionValue != true,
                        ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: textTheme.titleMedium?.copyWith(
                          color: tint.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        [
                          if (accountCount > 1) '$accountCount conturi',
                          !connected
                              ? 'Neconectat'
                              : updated == null
                              ? 'Încă neactualizat'
                              : 'Actualizat ${dateTimeFormat.format(updated)}',
                        ].join(' · '),
                        style: textTheme.bodySmall?.copyWith(
                          color: tint.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                if (bills.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _lei(provider.unpaidTotal(billProvider)),
                        style: textTheme.titleLarge?.copyWith(
                          color: tint.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'bifate ${_lei(provider.paidTotal(billProvider))}',
                        style: textTheme.bodySmall?.copyWith(
                          color: tint.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          for (final error in errors)
            Container(
              color: scheme.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                error,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          if (!connected)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: OutlinedButton.icon(
                onPressed: onConnect,
                icon: const Icon(Icons.login),
                label: Text('Conectează contul $name'),
              ),
            )
          else if (locations.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(
                updated == null
                    ? 'Trage în jos sau apasă pe actualizare ca să preiei '
                          'facturile.'
                    : 'Nicio adresă aleasă pentru afișare.',
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final location in locations) ...[
              const Divider(height: 1),
              Container(
                color: tint.primaryContainer.withValues(alpha: 0.35),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.place_outlined, size: 18, color: tint.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        location.$2.isEmpty
                            ? 'Cod ${location.$1}'
                            : location.$2,
                        style: textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
              ),
              if (!bills.any((b) => b.contractCode == location.$1))
                Padding(
                  padding: const EdgeInsets.fromLTRB(42, 10, 16, 12),
                  child: Text(
                    'Nicio factură de afișat.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                for (final bill in bills.where(
                  (b) => b.contractCode == location.$1,
                ))
                  _BillTile(bill: bill),
            ],
        ],
      ),
    );
  }
}

class _BillTile extends StatelessWidget {
  final Bill bill;

  const _BillTile({required this.bill});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return CheckboxListTile(
      value: bill.paid,
      controlAffinity: ListTileControlAffinity.leading,
      secondary: BillIndexBadge.hasIndex(bill)
          ? BillIndexBadge(bill: bill)
          : null,
      onChanged: (v) => context.read<BillsProvider>().setPaid(bill, v ?? false),
      title: Text(
        _lei(bill.amount),
        style: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
          decoration: bill.paid ? TextDecoration.lineThrough : null,
          color: bill.paid ? scheme.onSurfaceVariant : scheme.onSurface,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(billDatesLine(bill)),
          InkWell(
            onTap: () => openBillPdf(context, bill),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Deschide',
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          BillStatusText(bill: bill),
        ],
      ),
    );
  }
}
