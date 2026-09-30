import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../models/money_transaction.dart';
import '../providers/money_provider.dart';
import '../utils/card_styles.dart';
import '../utils/formatters.dart';
import '../widgets/account_card.dart';
import '../widgets/amount_text.dart';
import '../widgets/transaction_tile.dart';
import 'accounts_screen.dart';
import 'add_transaction_screen.dart';
import 'family_accounts_screen.dart';
import 'settings_screen.dart';

enum _CurrencyFilter { all, ron, eur }

enum _TxFilter { all, income, expense }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _CurrencyFilter _filter = _CurrencyFilter.all;
  _TxFilter _txFilter = _TxFilter.all;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MoneyProvider>();
    final recentTx = provider.transactions
        .where((t) {
          switch (_txFilter) {
            case _TxFilter.all:
              return true;
            case _TxFilter.income:
              return t.type == TxType.income;
            case _TxFilter.expense:
              return t.type == TxType.expense;
          }
        })
        .take(5)
        .toList();

    final visibleAccounts = provider.personalAccounts.where((a) {
      switch (_filter) {
        case _CurrencyFilter.all:
          return true;
        case _CurrencyFilter.ron:
          return a.currency == AccountCurrency.ron;
        case _CurrencyFilter.eur:
          return a.currency == AccountCurrency.eur;
      }
    }).toList();

    final filterSubtotal = visibleAccounts.fold<double>(
      0,
      (sum, a) => sum + a.balance,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_outline),
            SizedBox(width: 8),
            Text('Portofel'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.family_restroom),
            tooltip: 'Conturi Familie',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FamilyAccountsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            tooltip: 'Conturi',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AccountsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Transfer / Schimb valutar',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AddTransactionScreen(initialTab: 2),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Setări',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      // Banerul Venit/Plată nu mai e bottomNavigationBar + extendBody: pe iOS
      // (Impeller), acea combinație producea un bug de randare în care fundalul
      // semi-transparent al banerului se întindea peste tot ecranul. Suprapus
      // direct peste listă printr-un Stack, banerul e doar un widget obișnuit
      // poziționat deasupra, fără nicio interacțiune specială de compunere.
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                decoration: heroCardDecoration(),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total estimat',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: AmountText(
                          '${formatNumber(provider.totalInEur())} €',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '≈ ${formatNumber(provider.totalInRon())} lei',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Conturi',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  SegmentedButton<_CurrencyFilter>(
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: Theme.of(context).textTheme.labelSmall,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    segments: const [
                      ButtonSegment(
                        value: _CurrencyFilter.all,
                        label: Text('Toate'),
                      ),
                      ButtonSegment(
                        value: _CurrencyFilter.ron,
                        label: Text('Lei'),
                      ),
                      ButtonSegment(
                        value: _CurrencyFilter.eur,
                        label: Text('Euro'),
                      ),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (s) =>
                        setState(() => _filter = s.first),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_filter != _CurrencyFilter.all)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Subtotal ${_filter == _CurrencyFilter.ron ? "Lei" : "Euro"}: '
                    '${formatAmount(filterSubtotal, _filter == _CurrencyFilter.ron ? AccountCurrency.ron : AccountCurrency.eur)}',
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              if (visibleAccounts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Niciun cont în această valută'),
                )
              else if (_filter == _CurrencyFilter.all)
                // Reordonabilă doar când se văd toate conturile — indicii din
                // listă corespund atunci exact cu ordinea reală (sortOrder);
                // pe un subset filtrat (doar Lei/doar Euro) indicii nu s-ar
                // mai potrivi cu poziția reală din grup.
                _reorderablePersonalAccounts(context, provider, visibleAccounts)
              else
                ...visibleAccounts.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AccountCard(account: a),
                  ),
                ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Tranzacții',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  SegmentedButton<_TxFilter>(
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: Theme.of(context).textTheme.labelSmall,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    segments: const [
                      ButtonSegment(value: _TxFilter.all, label: Text('Toate')),
                      ButtonSegment(
                        value: _TxFilter.income,
                        label: Text('Venituri'),
                      ),
                      ButtonSegment(
                        value: _TxFilter.expense,
                        label: Text('Plăți'),
                      ),
                    ],
                    selected: {_txFilter},
                    onSelectionChanged: (s) =>
                        setState(() => _txFilter = s.first),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (recentTx.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('Nicio tranzacție încă')),
                )
              else
                ...recentTx.indexed.map(
                  (e) => TransactionTile(
                    tx: e.$2,
                    provider: provider,
                    index: e.$1 + 1,
                  ),
                ),
              // Spațiu ca ultimele elemente să nu rămână ascunse sub
              // banerul plutitor Venit/Plată, suprapus peste listă.
              SizedBox(height: MediaQuery.paddingOf(context).bottom + 80),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _venitPlataBar(context),
          ),
        ],
      ),
    );
  }

  /// Baner semi-transparent, în stil frosted-glass, plutitor în partea de
  /// jos a ecranului — împărțit în două jumătăți (Venit/Plată), la fel ca
  /// bara de navigare de jos din Calorii Fit.
  Widget _venitPlataBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillTop = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : Colors.white.withValues(alpha: 0.78);
    final fillBottom = isDark
        ? Colors.white.withValues(alpha: 0.32)
        : Colors.white.withValues(alpha: 0.68);
    final edge = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.85);
    const radius = 32.0;

    // Blurul e sigur acum: banerul nu mai e bottomNavigationBar + extendBody
    // (combinația care cauza bug-ul de randare pe iOS), ci un widget obișnuit
    // suprapus peste listă printr-un Stack.
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [fillTop, fillBottom],
                ),
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: edge, width: 1),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _GlassBarButton(
                      icon: Icons.add,
                      label: 'Venit',
                      color: Colors.green.shade800,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(radius),
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const AddTransactionScreen(initialTab: 0),
                        ),
                      ),
                    ),
                  ),
                  VerticalDivider(width: 1, thickness: 1, color: edge),
                  Expanded(
                    child: _GlassBarButton(
                      icon: Icons.remove,
                      label: 'Plată',
                      color: Colors.red.shade800,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(radius),
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const AddTransactionScreen(initialTab: 1),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _reorderablePersonalAccounts(
    BuildContext context,
    MoneyProvider provider,
    List<Account> accounts,
  ) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: accounts.length,
      onReorderItem: (oldIndex, newIndex) =>
          provider.reorderAccounts(AccountGroup.personal, oldIndex, newIndex),
      itemBuilder: (context, index) {
        final account = accounts[index];
        // Apăsare lungă oriunde pe card pornește drag-ul de reordonare.
        return ReorderableDelayedDragStartListener(
          key: ValueKey(account.id),
          index: index,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AccountCard(account: account),
          ),
        );
      },
    );
  }
}

/// O jumătate a banerului Venit/Plată — icon + etichetă colorate, pe fond
/// transparent (culoarea vine din textul/iconul propriu, nu dintr-un
/// fundal plin, ca să se vadă efectul de sticlă al banerului din spate).
class _GlassBarButton extends StatelessWidget {
  const _GlassBarButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.borderRadius,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final BorderRadius borderRadius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: borderRadius,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
