import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../models/bill.dart';
import '../models/meter_reading.dart';
import '../providers/bills_provider.dart';
import '../services/eon_api.dart';
import '../utils/card_styles.dart';
import '../utils/formatters.dart';
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
    final controller = TextEditingController();
    final via = challenge.type == 'SMS' ? 'SMS' : 'email';
    final to = challenge.recipient.isEmpty ? '' : ' la ${challenge.recipient}';
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Cod de verificare E.ON'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('E.ON a trimis un cod prin $via$to. Introdu-l mai jos.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Cod',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Renunță'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Continuă'),
          ),
        ],
      ),
    );
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
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: provider.paidCount > 0 ? _saveToHistory : null,
              icon: const Icon(Icons.archive_outlined),
              label: Text(
                provider.paidCount > 0
                    ? 'Salvează în istoric (${provider.paidCount})'
                    : 'Salvează în istoric',
              ),
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

  const _TotalsCard({required this.unpaid, required this.paid});

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
          const SizedBox(width: 16),
          cell('Total bifate', paid),
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
    final meters = provider.metersFor(billProvider);

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
          if (connected)
            for (final meter in meters) ...[
              const Divider(height: 1),
              _MeterTile(meter: meter),
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
          if (billIndexLine(bill) case final line?) Text(line),
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

class _MeterTile extends StatelessWidget {
  final MeterReading meter;

  const _MeterTile({required this.meter});

  @override
  Widget build(BuildContext context) {
    final date = meter.date;
    final value = meter.value == meter.value.roundToDouble()
        ? indexFormat.format(meter.value)
        : formatNumber(meter.value);
    final details = [
      if (meter.meterNumber.isNotEmpty) 'Contor ${meter.meterNumber}',
      if (date != null) 'citit ${dateFormat.format(date)}',
    ].join(' · ');
    final place = meter.address.isNotEmpty
        ? meter.address
        : 'Cod ${meter.contractCode}';

    return ListTile(
      leading: const Icon(Icons.speed_outlined),
      title: Text(
        meter.label.isEmpty
            ? 'Ultimul index: $value'
            : 'Ultimul index: $value (${meter.label})',
      ),
      subtitle: Text(details.isEmpty ? place : '$place\n$details'),
      isThreeLine: details.isNotEmpty,
    );
  }
}
