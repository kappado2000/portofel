import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../providers/bills_provider.dart';
import '../utils/card_styles.dart';
import '../utils/formatters.dart';
import 'bills_screen.dart';
import 'home_screen.dart';

/// Primul ecran după deblocare: alegerea între cele două părți ale
/// aplicației, Cont (banii) și Facturi.
class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  void _open(BuildContext context, Widget screen, {String? name}) =>
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => screen,
          settings: RouteSettings(name: name),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final bills = context.watch<BillsProvider>();
    final overdue = bills.overdueBills();
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Ce deschizi?',
                    textAlign: TextAlign.center,
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _ChoiceCard(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Cont',
                    subtitle: 'Cash, cont bancar și tranzacții',
                    gradient: heroCardGradient,
                    onTap: () =>
                        _open(context, const HomeScreen(), name: homeRouteName),
                  ),
                  const SizedBox(height: 16),
                  _ChoiceCard(
                    icon: Icons.receipt_long_outlined,
                    title: 'Facturi',
                    subtitle: bills.hasAnyAccount
                        ? 'Nebifate: ${formatAmount(bills.unpaidTotal(), AccountCurrency.ron)}'
                        : 'Utilități: Hidroelectrica, E.ON, Electrica',
                    warning: overdue.isEmpty
                        ? null
                        : overdue.length == 1
                        ? 'O factură restantă'
                        : '${overdue.length} facturi restante',
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.amber.shade600,
                        Colors.deepOrange.shade400,
                      ],
                    ),
                    onTap: () => _open(context, const BillsScreen()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? warning;
  final Gradient gradient;
  final VoidCallback onTap;

  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
    this.warning,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 20, 28),
            child: Row(
              children: [
                Icon(icon, size: 48, color: Colors.white),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                      ),
                      if (warning != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade700,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            warning!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white, size: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
