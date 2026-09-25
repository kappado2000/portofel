import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/account.dart';
import '../models/money_transaction.dart';
import '../providers/money_provider.dart';
import '../utils/formatters.dart';
import '../widgets/account_card.dart';
import '../widgets/amount_text.dart';
import '../widgets/transaction_tile.dart';
import 'accounts_screen.dart';
import 'add_transaction_screen.dart';
import 'family_accounts_screen.dart';
import 'history_screen.dart';
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
    final recentTx = provider.transactions.where((t) {
      switch (_txFilter) {
        case _TxFilter.all:
          return true;
        case _TxFilter.income:
          return t.type == TxType.income;
        case _TxFilter.expense:
          return t.type == TxType.expense;
      }
    }).take(5).toList();

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

    final filterSubtotal = visibleAccounts.fold<double>(0, (sum, a) => sum + a.balance);

    final totalCardScheme = Theme.of(context).colorScheme;

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
              MaterialPageRoute(builder: (_) => const AddTransactionScreen(initialTab: 2)),
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
      body: RefreshIndicator(
        onRefresh: () async {},
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: totalCardScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total estimat',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: totalCardScheme.onPrimaryContainer),
                    ),
                    const SizedBox(height: 6),
                    AmountText(
                      '${formatNumber(provider.totalInEur())} €',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: totalCardScheme.onPrimaryContainer,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '≈ ${formatNumber(provider.totalInRon())} lei',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: totalCardScheme.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Conturi', style: Theme.of(context).textTheme.titleMedium),
                SegmentedButton<_CurrencyFilter>(
                  segments: const [
                    ButtonSegment(value: _CurrencyFilter.all, label: Text('Toate')),
                    ButtonSegment(value: _CurrencyFilter.ron, label: Text('Lei')),
                    ButtonSegment(value: _CurrencyFilter.eur, label: Text('Euro')),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (s) => setState(() => _filter = s.first),
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
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            if (visibleAccounts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Niciun cont în această valută'),
              )
            else
              ...visibleAccounts.map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AccountCard(account: a),
                  )),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.green.withValues(alpha: 0.15),
                      foregroundColor: Colors.green.shade800,
                      side: BorderSide(color: Colors.green.shade400),
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AddTransactionScreen(initialTab: 0)),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Venit'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.red.withValues(alpha: 0.15),
                      foregroundColor: Colors.red.shade800,
                      side: BorderSide(color: Colors.red.shade400),
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AddTransactionScreen(initialTab: 1)),
                    ),
                    icon: const Icon(Icons.remove),
                    label: const Text('Plată'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Tranzacții recente', style: Theme.of(context).textTheme.titleMedium),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HistoryScreen()),
                  ),
                  child: const Text('Vezi tot'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SegmentedButton<_TxFilter>(
              segments: const [
                ButtonSegment(value: _TxFilter.all, label: Text('Toate')),
                ButtonSegment(value: _TxFilter.income, label: Text('Venituri')),
                ButtonSegment(value: _TxFilter.expense, label: Text('Plăți')),
              ],
              selected: {_txFilter},
              onSelectionChanged: (s) => setState(() => _txFilter = s.first),
            ),
            const SizedBox(height: 8),
            if (recentTx.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Nicio tranzacție încă')),
              )
            else
              ...recentTx.indexed.map(
                (e) => TransactionTile(tx: e.$2, provider: provider, index: e.$1 + 1),
              ),
          ],
        ),
      ),
    );
  }
}
