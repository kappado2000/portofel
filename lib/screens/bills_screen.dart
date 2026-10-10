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
  /// Pagina cu nume propriu afișată (`null` = pagina principală).
  final String? pageId;

  const BillsScreen({super.key, this.pageId});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  String? get _page => widget.pageId;

  @override
  void initState() {
    super.initState();
    // Actualizare automată la deschiderea paginii.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _page == null &&
          context.read<BillsProvider>().hasAnyAccount) {
        _refresh();
      }
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
          '${provider.paidCount(_page)} facturi bifate, în total '
          '${_lei(provider.paidTotal(page: _page))}, vor fi mutate în istoricul '
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
    await provider.archivePaid(_page);
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
    MaterialPageRoute(builder: (_) => BillsHistoryScreen(pageId: _page)),
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
        for (final loc in provider.locationsFor(p))
          if (provider.pageOfLocation(BillsProvider.locationKey(p, loc.$1)) ==
              null)
            (p, loc.$1, loc.$2),
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

  Future<String?> _askPageName({String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(initial.isEmpty ? 'Pagină nouă' : 'Redenumește pagina'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nume (ex. Facturi Tata)',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Renunță'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Salvează'),
          ),
        ],
      ),
    );
  }

  Future<void> _addPage() async {
    final provider = context.read<BillsProvider>();
    final name = await _askPageName();
    if (name == null || name.trim().isEmpty || !mounted) return;
    final page = await provider.addPage(name);
    if (!mounted) return;
    await _choosePageAddresses(page.id);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BillsScreen(pageId: page.id)),
    );
  }

  Future<void> _renamePage() async {
    final provider = context.read<BillsProvider>();
    final page = provider.pageById(_page);
    if (page == null) return;
    final name = await _askPageName(initial: page.name);
    if (name == null || name.trim().isEmpty) return;
    await provider.renamePage(page.id, name);
  }

  Future<void> _deletePage() async {
    final provider = context.read<BillsProvider>();
    final page = provider.pageById(_page);
    if (page == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ștergi pagina „${page.name}”?'),
        content: const Text(
          'Facturile și istoricul nu se șterg: adresele paginii revin pe '
          'pagina principală.',
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
    if (ok != true || !mounted) return;
    Navigator.pop(context);
    await provider.deletePage(page.id);
  }

  /// Alegerea adreselor unei pagini, din toate conturile.
  Future<void> _choosePageAddresses(String pageId) async {
    final provider = context.read<BillsProvider>();
    final all = [
      for (final p in BillProvider.values)
        for (final loc in provider.locationsFor(p)) (p, loc.$1, loc.$2),
    ];
    final chosen = Set.of(provider.pageById(pageId)?.locations ?? <String>{});

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Adresele paginii „${provider.pageById(pageId)?.name}”'),
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
                      for (final l in all)
                        Builder(
                          builder: (_) {
                            final key = BillsProvider.locationKey(l.$1, l.$2);
                            final other = provider.pageOfLocation(key);
                            final elsewhere =
                                other != null && other.id != pageId;
                            return CheckboxListTile(
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(l.$3.isEmpty ? 'Cod ${l.$2}' : l.$3),
                              subtitle: Text(
                                elsewhere && !chosen.contains(key)
                                    ? '${billProviderLabel(l.$1)} · acum pe '
                                          'pagina „${other.name}”'
                                    : billProviderLabel(l.$1),
                              ),
                              value: chosen.contains(key),
                              onChanged: (v) => setLocal(() {
                                v == true
                                    ? chosen.add(key)
                                    : chosen.remove(key);
                              }),
                            );
                          },
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
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await provider.setPageLocations(pageId, chosen);
    // Adresele care erau ascunse nu au fost interogate până acum.
    if (mounted) await _refresh();
  }

  Future<void> _removePaid() async {
    final provider = context.read<BillsProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Șterge facturile bifate?'),
        content: Text(
          '${provider.paidCount(_page)} facturi bifate, în total '
          '${_lei(provider.paidTotal(page: _page))}, vor fi scoase din listă.',
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
    if (ok == true) await provider.removePaid(_page);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BillsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(provider.pageById(_page)?.name ?? 'Facturi'),
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
                case 'pageAddresses':
                  _choosePageAddresses(_page!);
                case 'pageRename':
                  _renamePage();
                case 'pageDelete':
                  _deletePage();
                case 'clear':
                  _removePaid();
              }
            },
            itemBuilder: (_) => [
              if (_page == null) ...const [
                PopupMenuItem(
                  value: 'accounts',
                  child: Text('Conturi furnizori'),
                ),
                PopupMenuItem(
                  value: 'start',
                  child: Text('Facturi începând cu…'),
                ),
                PopupMenuItem(
                  value: 'addresses',
                  child: Text('Adrese afișate'),
                ),
              ] else ...const [
                PopupMenuItem(
                  value: 'pageAddresses',
                  child: Text('Adresele paginii'),
                ),
                PopupMenuItem(
                  value: 'pageRename',
                  child: Text('Redenumește pagina'),
                ),
                PopupMenuItem(
                  value: 'pageDelete',
                  child: Text('Șterge pagina'),
                ),
              ],
              PopupMenuItem(
                value: 'clear',
                enabled: provider.paidCount(_page) > 0,
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
              unpaid: provider.unpaidTotal(page: _page),
              paid: provider.paidTotal(page: _page),
              onSave: provider.paidCount(_page) > 0 ? _saveToHistory : null,
            ),
            if (provider.overdueBills(_page).isNotEmpty) ...[
              const SizedBox(height: 12),
              _OverdueBanner(bills: provider.overdueBills(_page)),
            ],
            if (_page == null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final g in provider.pages)
                    ActionChip(
                      avatar: const Icon(Icons.folder_outlined, size: 18),
                      label: Text(
                        '${g.name} · ${_lei(provider.unpaidTotal(page: g.id))}',
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BillsScreen(pageId: g.id),
                        ),
                      ),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('Pagină nouă'),
                    onPressed: _addPage,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            for (final p in BillProvider.values)
              if (_page != null
                  ? provider.visibleLocationsFor(p, _page).isNotEmpty
                  : !provider.hasAnyAccount || provider.isConnected(p))
                _ProviderSection(
                  pageId: _page,
                  billProvider: p,
                  onConnect: () => _editAccount(p),
                ),
            if (_page != null &&
                (provider.pageById(_page)?.locations.isEmpty ?? true))
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text(
                      'Pagina nu are încă nicio adresă.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _choosePageAddresses(_page!),
                      icon: const Icon(Icons.place_outlined),
                      label: const Text('Alege adresele'),
                    ),
                  ],
                ),
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
  final String? pageId;

  const _ProviderSection({
    required this.billProvider,
    required this.onConnect,
    this.pageId,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BillsProvider>();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final name = billProviderLabel(billProvider);
    final bills = provider.billsFor(billProvider, pageId);
    final connected = provider.isConnected(billProvider);
    final errors = provider.errorsFor(billProvider);
    final accountCount = provider.accountsFor(billProvider).length;
    final updated = provider.lastUpdated(billProvider);
    final locations = provider.visibleLocationsFor(billProvider, pageId);

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
                          pageId,
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
                        _lei(
                          provider.unpaidTotal(p: billProvider, page: pageId),
                        ),
                        style: textTheme.titleLarge?.copyWith(
                          color: tint.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'bifate ${_lei(provider.paidTotal(p: billProvider, page: pageId))}',
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
    final provider = context.read<BillsProvider>();

    return InkWell(
      onTap: () => provider.setPaid(bill, !bill.paid),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 16, 10),
        child: Row(
          children: [
            Checkbox(
              value: bill.paid,
              onChanged: (v) => provider.setPaid(bill, v ?? false),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _lei(bill.amount),
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      decoration: bill.paid ? TextDecoration.lineThrough : null,
                      color: bill.paid
                          ? scheme.onSurfaceVariant
                          : scheme.onSurface,
                    ),
                  ),
                  Text(
                    billDatesLine(bill),
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  InkWell(
                    onTap: () => openBillPdf(context, bill),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
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
                            'Deschide',
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  BillStatusText(bill: bill),
                ],
              ),
            ),
            const SizedBox(width: 12),
            BillIndexBadge(bill: bill),
          ],
        ),
      ),
    );
  }
}
