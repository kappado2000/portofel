import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/money_provider.dart';
import '../providers/profile_provider.dart';
import '../services/biometric_service.dart';
import '../utils/formatters.dart';

const _securityQuestion = 'Care este numele animalului tău preferat?';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _rateController;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    final provider = context.read<MoneyProvider>();
    _rateController = TextEditingController(
      text: provider.defaultExchangeRate.toStringAsFixed(4),
    );
    BiometricService.isAvailable().then((available) {
      if (mounted) setState(() => _biometricAvailable = available);
    });
  }

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MoneyProvider>();
    final profileProvider = context.watch<ProfileProvider>();
    final profileId = profileProvider.activeProfileId;
    final profile = profileId != null ? profileProvider.byId(profileId) : null;

    if (profileId == null || profile == null) {
      // Profilul a fost delogat cât timp acest ecran era deschis deasupra
      // stivei de navigare — se închide fără să mai construiască UI-ul.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) Navigator.pop(context);
      });
      return const SizedBox.shrink();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Setări')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionCard(
            context: context,
            icon: Icons.person,
            color: Colors.indigo,
            title: 'Profil',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.badge_outlined),
                title: Text(profile.name),
                subtitle: const Text('Apasă pentru a redenumi'),
                onTap: () => _renameProfile(
                  context,
                  profileProvider,
                  profileId,
                  profile.name,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Delogarea te duce la ecranul de selectare a profilului, de unde poți '
                'reveni la acest profil sau crea unul nou.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Delogare'),
                onPressed: () {
                  // Golește orice ecran deschis deasupra (Setări, Istoric etc.)
                  // înainte de delogare, altfel ar rămâne pe stivă și s-ar
                  // reconstrui cu un profil inexistent.
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  profileProvider.logout();
                },
              ),
            ],
          ),
          _sectionCard(
            context: context,
            icon: Icons.currency_exchange,
            color: Colors.teal,
            title: 'Curs de schimb implicit',
            children: [
              Text(
                'Folosit pentru calculul totalurilor și ca valoare implicită la '
                'transferurile între RON și EUR (poate fi suprascris manual la fiecare transfer).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _rateController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: '1 EUR = ? RON',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      final rate = double.tryParse(
                        _rateController.text.replaceAll(',', '.'),
                      );
                      if (rate != null && rate > 0) {
                        provider.defaultExchangeRate = rate;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Curs salvat')),
                        );
                      }
                    },
                    child: const Text('Salvează'),
                  ),
                ],
              ),
            ],
          ),
          _sectionCard(
            context: context,
            icon: Icons.account_balance_wallet,
            color: Colors.orange,
            title: 'Totaluri estimate',
            children: [
              Text(
                'Total echivalent în RON: ${formatNumber(provider.totalInRon())} lei',
              ),
              const SizedBox(height: 4),
              Text(
                'Total echivalent în EUR: ${formatNumber(provider.totalInEur())} €',
              ),
            ],
          ),
          _sectionCard(
            context: context,
            icon: Icons.palette,
            color: Colors.purple,
            title: 'Aspect',
            children: [
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode),
                    label: Text('Luminos'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode),
                    label: Text('Dark'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto),
                    label: Text('Automat'),
                  ),
                ],
                selected: {profileProvider.themeMode},
                onSelectionChanged: (s) =>
                    profileProvider.setThemeMode(s.first),
              ),
            ],
          ),
          _sectionCard(
            context: context,
            icon: Icons.security,
            color: Colors.red,
            title: 'Securitate',
            children: [
              Text(
                'Parola de acces protejează deschiderea profilului tău pe acest dispozitiv.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.password),
                label: const Text('Schimbă parola'),
                onPressed: () =>
                    _changePin(context, profileProvider, profileId),
              ),
              if (_biometricAvailable)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Amprentă / Face ID'),
                  subtitle: const Text(
                    'Deblochează rapid, fără să introduci parola',
                  ),
                  secondary: const Icon(Icons.fingerprint),
                  value: profile.biometricEnabled,
                  onChanged: (v) =>
                      profileProvider.setBiometricEnabled(profileId, v),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.help_outline),
                label: Text(
                  profileProvider.hasSecurityAnswer(profileId)
                      ? 'Schimbă întrebarea de securitate'
                      : 'Setează întrebarea de securitate',
                ),
                onPressed: () =>
                    _setSecurityAnswer(context, profileProvider, profileId),
              ),
              const SizedBox(height: 4),
              Text(
                'Folosită pentru a recupera accesul dacă uiți parola.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Card colorat pentru o secțiune de setări — fiecare zonă (Profil, Curs de
  /// schimb, Totaluri, Aspect, Securitate) are propria culoare de identificare,
  /// ca ecranul să nu mai fie un bloc uniform separat doar prin Divider-e.
  Widget _sectionCard({
    required BuildContext context,
    required IconData icon,
    required Color color,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: color.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: color, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Future<void> _renameProfile(
    BuildContext context,
    ProfileProvider provider,
    String profileId,
    String currentName,
  ) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Redenumește profilul'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anulează'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Salvează'),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty) {
      await provider.renameProfile(profileId, newName);
    }
  }

  Future<void> _changePin(
    BuildContext context,
    ProfileProvider provider,
    String profileId,
  ) async {
    final oldController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Schimbă parola'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _pinField(oldController, 'Parola actuală'),
              _pinField(newController, 'Parola nouă'),
              _pinField(confirmController, 'Confirmă parola nouă'),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Anulează'),
            ),
            FilledButton(
              onPressed: () async {
                if (!provider.verifyPin(profileId, oldController.text)) {
                  setState(() => error = 'Parola actuală este greșită');
                  return;
                }
                if (newController.text.length < 4) {
                  setState(
                    () => error = 'Parola nouă trebuie să aibă minim 4 cifre',
                  );
                  return;
                }
                if (newController.text != confirmController.text) {
                  setState(() => error = 'Parolele nu coincid');
                  return;
                }
                await provider.setPin(profileId, newController.text);
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('Salvează'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Parolă salvată')));
    }
  }

  Widget _pinField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: controller,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: 6,
        decoration: InputDecoration(labelText: label, counterText: ''),
      ),
    );
  }

  Future<void> _setSecurityAnswer(
    BuildContext context,
    ProfileProvider provider,
    String profileId,
  ) async {
    final pinController = TextEditingController();
    final answerController = TextEditingController();
    String? error;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Întrebare de securitate'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _pinField(pinController, 'Parola actuală'),
              const SizedBox(height: 12),
              Text(
                _securityQuestion,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: answerController,
                decoration: const InputDecoration(labelText: 'Răspuns'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Anulează'),
            ),
            FilledButton(
              onPressed: () async {
                if (!provider.verifyPin(profileId, pinController.text)) {
                  setState(() => error = 'Parola actuală este greșită');
                  return;
                }
                if (answerController.text.trim().isEmpty) {
                  setState(() => error = 'Introdu un răspuns');
                  return;
                }
                await provider.setSecurityAnswer(
                  profileId,
                  answerController.text,
                );
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('Salvează'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Întrebare de securitate salvată')),
      );
    }
  }
}
