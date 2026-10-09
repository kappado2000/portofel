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

  Future<String?> _askMfaCode(EonMfaRequired challenge) async {
    if (!mounted) return null;
    return askEonMfaCode(context, challenge);
  }

  Future<void> _editAccount(BillProvider p) async {
    final provider = context.read<BillsProvider>();
    final userCtrl = TextEditingController(text: provider.usernameFor(p) ?? '');
    final passCtrl = TextEditingController(
      text: await provider.passwordFor(p) ?? '',
    );
    if (!mounted) return;
    final connected = provider.isConnected(p);
    var obscure = true;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Cont ${billProviderLabel(p)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: userCtrl,
                autocorrect: false,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: p == BillProvider.eon
                      ? 'Email Myline'
                      : 'Utilizator iHidro',
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
      await provider.removeAccount(p);
      return;
    }
    if (userCtrl.text.trim().isEmpty || passCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completează utilizatorul și parola.')),
      );
      return;
    }
    await provider.saveAccount(p, userCtrl.text, passCtrl.text);
    if (mounted) await _refresh();
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
                case 'hidro':
                  _editAccount(BillProvider.hidroelectrica);
                case 'eon':
                  _editAccount(BillProvider.eon);
                case 'addresses':
                  _chooseAddresses();
                case 'clear':
                  _removePaid();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'hidro',
                child: Text('Cont Hidroelectrica'),
              ),
              const PopupMenuItem(value: 'eon', child: Text('Cont E.ON')),
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
            const SizedBox(height: 16),
            for (final p in BillProvider.values)
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
                fontSize: 22,
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
          cell('De plată', unpaid),
          const SizedBox(width: 12),
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
    final error = provider.errorFor(billProvider);
    final updated = provider.lastUpdated(billProvider);

    final paidCount = bills.where((b) => b.paid).length;
    final bool? sectionValue = bills.isEmpty || paidCount == 0
        ? false
        : (paidCount == bills.length ? true : null);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
            child: Row(
              children: [
                Checkbox(
                  tristate: true,
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
                      Text(name, style: textTheme.titleMedium),
                      Text(
                        !connected
                            ? 'Neconectat'
                            : updated == null
                            ? 'Încă neactualizat'
                            : 'Actualizat ${dateTimeFormat.format(updated)}',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
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
                        style: textTheme.titleMedium,
                      ),
                      Text(
                        'bifate ${_lei(provider.paidTotal(billProvider))}',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (error != null)
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
          else if (bills.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(
                updated == null
                    ? 'Trage în jos sau apasă pe actualizare ca să preiei '
                          'facturile.'
                    : 'Nicio factură de plată.',
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final bill in bills) ...[
              const Divider(height: 1),
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
    final place = bill.address.isNotEmpty
        ? bill.address
        : 'Cod ${bill.contractCode}';

    final String? status = !bill.openAtProvider
        ? 'Achitată la furnizor'
        : bill.isOverdue
        ? 'Scadență depășită'
        : null;

    return CheckboxListTile(
      value: bill.paid,
      controlAffinity: ListTileControlAffinity.leading,
      secondary: BillIndexBadge.hasIndex(bill)
          ? BillIndexBadge(bill: bill)
          : null,
      onChanged: (v) => context.read<BillsProvider>().setPaid(bill, v ?? false),
      title: Text(
        _lei(bill.balance),
        style: TextStyle(
          fontWeight: FontWeight.w600,
          decoration: bill.paid ? TextDecoration.lineThrough : null,
          color: bill.paid ? scheme.onSurfaceVariant : null,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(place),
          Text(billDatesLine(bill)),
          if (bill.invoiceNumber.isNotEmpty) Text('Nr. ${bill.invoiceNumber}'),
          InkWell(
            onTap: () => openBillPdf(context, bill),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.picture_as_pdf_outlined,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Deschide factura',
                    style: TextStyle(color: scheme.primary),
                  ),
                ],
              ),
            ),
          ),
          if (status != null)
            Text(
              status,
              style: TextStyle(
                color: bill.isOverdue ? scheme.error : scheme.primary,
              ),
            ),
        ],
      ),
    );
  }
}
