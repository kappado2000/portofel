import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/money_provider.dart';
import '../services/biometric_service.dart';
import '../utils/formatters.dart';

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
    _rateController = TextEditingController(text: provider.defaultExchangeRate.toStringAsFixed(4));
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

    return Scaffold(
      appBar: AppBar(title: const Text('Setări')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Curs de schimb implicit', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
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
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '1 EUR = ? RON'),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () {
                  final rate = double.tryParse(_rateController.text.replaceAll(',', '.'));
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
          const Divider(height: 40),
          Text('Totaluri estimate', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('Total echivalent în RON: ${formatNumber(provider.totalInRon())} lei'),
          const SizedBox(height: 4),
          Text('Total echivalent în EUR: ${formatNumber(provider.totalInEur())} €'),
          const Divider(height: 40),
          Text('Aspect', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('Luminos')),
              ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('Dark')),
              ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('Automat')),
            ],
            selected: {provider.themeMode},
            onSelectionChanged: (s) => provider.setThemeMode(s.first),
          ),
          const Divider(height: 40),
          Text('Securitate', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Parola de acces protejează deschiderea aplicației pe acest dispozitiv.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.password),
                  label: const Text('Schimbă parola'),
                  onPressed: () => _changePin(context, provider),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Dezactivează'),
                  onPressed: () => _removePin(context, provider),
                ),
              ),
            ],
          ),
          if (provider.hasPin && _biometricAvailable)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Amprentă / Face ID'),
              subtitle: const Text('Deblochează rapid, fără să introduci parola'),
              secondary: const Icon(Icons.fingerprint),
              value: provider.biometricEnabled,
              onChanged: (v) => provider.setBiometricEnabled(v),
            ),
          if (provider.hasPin) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.help_outline),
              label: Text(provider.hasSecurityAnswer
                  ? 'Schimbă întrebarea de securitate'
                  : 'Setează întrebarea de securitate'),
              onPressed: () => _setSecurityAnswer(context, provider),
            ),
            const SizedBox(height: 4),
            Text(
              'Folosită pentru a recupera accesul dacă uiți parola.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _changePin(BuildContext context, MoneyProvider provider) async {
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
              if (provider.hasPin)
                _pinField(oldController, 'Parola actuală'),
              _pinField(newController, 'Parola nouă'),
              _pinField(confirmController, 'Confirmă parola nouă'),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anulează')),
            FilledButton(
              onPressed: () async {
                if (provider.hasPin && !provider.verifyPin(oldController.text)) {
                  setState(() => error = 'Parola actuală este greșită');
                  return;
                }
                if (newController.text.length < 4) {
                  setState(() => error = 'Parola nouă trebuie să aibă minim 4 cifre');
                  return;
                }
                if (newController.text != confirmController.text) {
                  setState(() => error = 'Parolele nu coincid');
                  return;
                }
                await provider.setPin(newController.text);
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('Salvează'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Parolă salvată')));
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

  Future<void> _removePin(BuildContext context, MoneyProvider provider) async {
    if (!provider.hasPin) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Nu există o parolă setată')));
      return;
    }
    final controller = TextEditingController();
    String? error;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Dezactivează parola'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _pinField(controller, 'Introdu parola actuală'),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anulează')),
            FilledButton(
              onPressed: () {
                if (!provider.verifyPin(controller.text)) {
                  setState(() => error = 'Parolă incorectă');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Dezactivează'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await provider.removePin();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Parola a fost dezactivată')));
      }
    }
  }

  Future<void> _setSecurityAnswer(BuildContext context, MoneyProvider provider) async {
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
                MoneyProvider.securityQuestion,
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
                  child: Text(error!, style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anulează')),
            FilledButton(
              onPressed: () async {
                if (!provider.verifyPin(pinController.text)) {
                  setState(() => error = 'Parola actuală este greșită');
                  return;
                }
                if (answerController.text.trim().isEmpty) {
                  setState(() => error = 'Introdu un răspuns');
                  return;
                }
                await provider.setSecurityAnswer(answerController.text);
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
          .showSnackBar(const SnackBar(content: Text('Întrebare de securitate salvată')));
    }
  }
}
