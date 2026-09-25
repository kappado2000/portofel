import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/money_provider.dart';
import '../services/biometric_service.dart';

enum _Stage { login, setupPin, confirmPin, setupSecurity, forgotAnswer }

class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  final _answerController = TextEditingController();
  final _fieldFocusNode = FocusNode();

  late _Stage _stage;
  String? _error;
  String? _firstPin;
  bool _biometricAvailable = false;
  bool _biometricAttempted = false;

  @override
  void initState() {
    super.initState();
    final provider = context.read<MoneyProvider>();
    _stage = provider.hasPin ? _Stage.login : _Stage.setupPin;
    _checkBiometricAndMaybePrompt();
  }

  Future<void> _checkBiometricAndMaybePrompt() async {
    final provider = context.read<MoneyProvider>();
    if (!provider.hasPin || !provider.biometricEnabled) return;
    final available = await BiometricService.isAvailable();
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
    if (available && !_biometricAttempted) {
      _biometricAttempted = true;
      final ok = await BiometricService.authenticate();
      if (ok && mounted) widget.onUnlocked();
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    _answerController.dispose();
    _fieldFocusNode.dispose();
    super.dispose();
  }

  void _refocusField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fieldFocusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MoneyProvider>();

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _buildStageChildren(provider),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStageChildren(MoneyProvider provider) {
    switch (_stage) {
      case _Stage.login:
        return _pinFieldStage(
          icon: Icons.lock_outline,
          title: 'Introdu parola',
          subtitle: null,
          controller: _pinController,
          buttonLabel: 'Deblochează',
          onSubmit: () => _submitLogin(provider),
          extra: [
            if (provider.biometricEnabled && _biometricAvailable) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final ok = await BiometricService.authenticate();
                  if (ok) widget.onUnlocked();
                },
                icon: const Icon(Icons.fingerprint),
                label: const Text('Autentificare biometrică'),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() {
                _stage = _Stage.forgotAnswer;
                _error = null;
                _answerController.clear();
              }),
              child: const Text('Am uitat parola'),
            ),
          ],
        );

      case _Stage.setupPin:
        return _pinFieldStage(
          icon: Icons.lock_outline,
          title: 'Setează o parolă de acces',
          subtitle: 'Parola protejează accesul la Portofel pe acest dispozitiv.',
          controller: _pinController,
          buttonLabel: 'Continuă',
          onSubmit: _submitFirstPin,
        );

      case _Stage.confirmPin:
        return _pinFieldStage(
          icon: Icons.lock_outline,
          title: 'Confirmă parola',
          subtitle: 'Introdu din nou parola pentru confirmare.',
          controller: _confirmController,
          buttonLabel: 'Confirmă',
          onSubmit: _submitConfirmPin,
        );

      case _Stage.setupSecurity:
        return [
          Icon(Icons.help_outline, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'Întrebare de securitate',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Va fi folosită doar dacă uiți parola.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Text(
            MoneyProvider.securityQuestion,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _answerController,
            focusNode: _fieldFocusNode,
            autofocus: true,
            textAlign: TextAlign.center,
            decoration: InputDecoration(errorText: _error, hintText: 'Răspunsul tău'),
            onSubmitted: (_) => _submitSecurityAnswerSetup(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submitSecurityAnswerSetup,
              child: const Text('Finalizează'),
            ),
          ),
        ];

      case _Stage.forgotAnswer:
        return [
          Icon(Icons.help_outline, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'Recuperare parolă',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          if (!provider.hasSecurityAnswer)
            Text(
              'Nu ai setat o întrebare de securitate, deci parola nu poate fi recuperată automat.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            )
          else ...[
            Text(
              MoneyProvider.securityQuestion,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _answerController,
              focusNode: _fieldFocusNode,
              autofocus: true,
              textAlign: TextAlign.center,
              decoration: InputDecoration(errorText: _error, hintText: 'Răspunsul tău'),
              onSubmitted: (_) => _submitForgotAnswer(provider),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _submitForgotAnswer(provider),
                child: const Text('Verifică răspunsul'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() {
              _stage = _Stage.login;
              _error = null;
              _pinController.clear();
            }),
            child: const Text('Înapoi la parolă'),
          ),
        ];
    }
  }

  List<Widget> _pinFieldStage({
    required IconData icon,
    required String title,
    required String? subtitle,
    required TextEditingController controller,
    required String buttonLabel,
    required VoidCallback onSubmit,
    List<Widget> extra = const [],
  }) {
    return [
      Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 16),
      Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
      if (subtitle != null) ...[
        const SizedBox(height: 8),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
      ],
      const SizedBox(height: 24),
      TextField(
        controller: controller,
        focusNode: _fieldFocusNode,
        autofocus: true,
        obscureText: true,
        enableSuggestions: false,
        autocorrect: false,
        autofillHints: const <String>[],
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: 6,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 24, letterSpacing: 8),
        decoration: InputDecoration(counterText: '', errorText: _error, hintText: '••••'),
        onSubmitted: (_) => onSubmit(),
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: FilledButton(onPressed: onSubmit, child: Text(buttonLabel)),
      ),
      ...extra,
    ];
  }

  void _submitFirstPin() {
    final pin = _pinController.text;
    if (pin.length < 4) {
      setState(() => _error = 'Parola trebuie să aibă minim 4 cifre');
      return;
    }
    _firstPin = pin;
    setState(() {
      _stage = _Stage.confirmPin;
      _error = null;
    });
    _refocusField();
  }

  Future<void> _submitConfirmPin() async {
    final confirm = _confirmController.text;
    if (confirm != _firstPin) {
      setState(() {
        _error = 'Parolele nu coincid';
        _stage = _Stage.setupPin;
        _pinController.clear();
        _confirmController.clear();
      });
      _refocusField();
      return;
    }
    final provider = context.read<MoneyProvider>();
    await provider.setPin(confirm);
    if (!mounted) return;
    if (provider.hasSecurityAnswer) {
      widget.onUnlocked();
    } else {
      setState(() {
        _stage = _Stage.setupSecurity;
        _error = null;
      });
      _refocusField();
    }
  }

  Future<void> _submitSecurityAnswerSetup() async {
    final answer = _answerController.text.trim();
    if (answer.isEmpty) {
      setState(() => _error = 'Introdu un răspuns');
      return;
    }
    final provider = context.read<MoneyProvider>();
    await provider.setSecurityAnswer(answer);
    widget.onUnlocked();
  }

  void _submitLogin(MoneyProvider provider) {
    final pin = _pinController.text;
    if (provider.verifyPin(pin)) {
      widget.onUnlocked();
    } else {
      setState(() {
        _error = 'Parolă incorectă';
        _pinController.clear();
      });
      _refocusField();
    }
  }

  Future<void> _submitForgotAnswer(MoneyProvider provider) async {
    final answer = _answerController.text.trim();
    if (!provider.verifySecurityAnswer(answer)) {
      setState(() => _error = 'Răspuns incorect');
      _refocusField();
      return;
    }
    await provider.removePin();
    if (!mounted) return;
    setState(() {
      _stage = _Stage.setupPin;
      _error = null;
      _pinController.clear();
      _confirmController.clear();
      _answerController.clear();
    });
    _refocusField();
  }
}
