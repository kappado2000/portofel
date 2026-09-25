import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/profile_provider.dart';
import '../services/biometric_service.dart';

enum _Stage {
  pickProfile,
  createName,
  setupPin,
  confirmPin,
  setupSecurity,
  login,
  forgotAnswer,
}

const _securityQuestion = 'Care este numele animalului tău preferat?';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  final _nameController = TextEditingController();
  final _answerController = TextEditingController();
  final _fieldFocusNode = FocusNode();
  final _answerFocusNode = FocusNode();

  late _Stage _stage;
  String? _error;
  String? _firstPin;
  String? _pendingName;
  String? _pendingProfileId;
  bool _isRecovery = false;
  bool _biometricAvailable = false;
  bool _biometricAttempted = false;

  @override
  void initState() {
    super.initState();
    final provider = context.read<ProfileProvider>();
    if (provider.profiles.isEmpty) {
      _stage = _Stage.createName;
    } else if (provider.activeProfileId != null) {
      _pendingProfileId = provider.activeProfileId;
      _stage = _Stage.login;
      _checkBiometricAndMaybePrompt();
    } else {
      _stage = _Stage.pickProfile;
    }
  }

  Future<void> _checkBiometricAndMaybePrompt() async {
    final provider = context.read<ProfileProvider>();
    final profile = provider.byId(_pendingProfileId ?? '');
    if (profile == null || !profile.biometricEnabled) return;
    final available = await BiometricService.isAvailable();
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
    if (available && !_biometricAttempted) {
      _biometricAttempted = true;
      final ok = await BiometricService.authenticate();
      if (ok && mounted) _finishLogin(provider);
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    _nameController.dispose();
    _answerController.dispose();
    _fieldFocusNode.dispose();
    _answerFocusNode.dispose();
    super.dispose();
  }

  void _refocusField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fieldFocusNode.requestFocus();
    });
  }

  void _refocusAnswerField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _answerFocusNode.requestFocus();
    });
  }

  void _finishLogin(ProfileProvider provider) {
    provider.setActiveProfile(_pendingProfileId);
    provider.unlock();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProfileProvider>();

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

  List<Widget> _buildStageChildren(ProfileProvider provider) {
    switch (_stage) {
      case _Stage.pickProfile:
        return [
          Icon(Icons.people_outline, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text('Cine ești?', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ...provider.profiles.map(
            (p) => Card(
              child: ListTile(
                leading: const Icon(Icons.person),
                title: Text(p.name),
                onTap: () => setState(() {
                  _pendingProfileId = p.id;
                  _stage = _Stage.login;
                  _error = null;
                  _pinController.clear();
                  _biometricAttempted = false;
                }),
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => setState(() {
              _stage = _Stage.createName;
              _error = null;
              _nameController.clear();
            }),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Profil nou'),
          ),
        ];

      case _Stage.createName:
        return [
          Icon(Icons.person_add_alt, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text('Cont nou', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Cum te numești?',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nameController,
            focusNode: _answerFocusNode,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textAlign: TextAlign.center,
            decoration: InputDecoration(errorText: _error, hintText: 'Numele tău'),
            onSubmitted: (_) => _submitName(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _submitName, child: const Text('Continuă')),
          ),
          if (provider.profiles.isNotEmpty) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() {
                _stage = _Stage.pickProfile;
                _error = null;
              }),
              child: const Text('Înapoi'),
            ),
          ],
        ];

      case _Stage.setupPin:
        return _pinFieldStage(
          icon: Icons.lock_outline,
          title: 'Setează o parolă de acces',
          subtitle: 'Parola protejează accesul la profilul "${_pendingName ?? provider.byId(_pendingProfileId ?? '')?.name ?? ''}".',
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
            _securityQuestion,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _answerController,
            focusNode: _answerFocusNode,
            autofocus: true,
            keyboardType: TextInputType.text,
            textCapitalization: TextCapitalization.words,
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

      case _Stage.login:
        final profile = provider.byId(_pendingProfileId ?? '');
        return _pinFieldStage(
          icon: Icons.lock_outline,
          title: 'Salut, ${profile?.name ?? ''}',
          subtitle: 'Introdu parola',
          controller: _pinController,
          buttonLabel: 'Deblochează',
          onSubmit: () => _submitLogin(provider),
          extra: [
            if (profile != null && profile.biometricEnabled && _biometricAvailable) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final ok = await BiometricService.authenticate();
                  if (ok) _finishLogin(provider);
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
            if (provider.profiles.length > 1)
              TextButton(
                onPressed: () => setState(() {
                  _stage = _Stage.pickProfile;
                  _error = null;
                }),
                child: const Text('Schimbă profilul'),
              ),
          ],
        );

      case _Stage.forgotAnswer:
        final hasAnswer = provider.hasSecurityAnswer(_pendingProfileId ?? '');
        return [
          Icon(Icons.help_outline, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'Recuperare parolă',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          if (!hasAnswer)
            Text(
              'Nu ai setat o întrebare de securitate, deci parola nu poate fi recuperată automat.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            )
          else ...[
            Text(
              _securityQuestion,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _answerController,
              focusNode: _answerFocusNode,
              autofocus: true,
              keyboardType: TextInputType.text,
              textCapitalization: TextCapitalization.words,
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

  void _submitName() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Introdu un nume');
      return;
    }
    _pendingName = name;
    _isRecovery = false;
    setState(() {
      _stage = _Stage.setupPin;
      _error = null;
      _pinController.clear();
    });
    _refocusField();
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
      _confirmController.clear();
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
    final provider = context.read<ProfileProvider>();

    if (_isRecovery) {
      await provider.resetPinAfterRecovery(_pendingProfileId!, confirm);
      if (!mounted) return;
      _finishLogin(provider);
      return;
    }

    final profile = await provider.createProfile(name: _pendingName!, pin: confirm);
    _pendingProfileId = profile.id;
    if (!mounted) return;
    setState(() {
      _stage = _Stage.setupSecurity;
      _error = null;
      _answerController.clear();
    });
    _refocusAnswerField();
  }

  Future<void> _submitSecurityAnswerSetup() async {
    final answer = _answerController.text.trim();
    if (answer.isEmpty) {
      setState(() => _error = 'Introdu un răspuns');
      return;
    }
    final provider = context.read<ProfileProvider>();
    await provider.setSecurityAnswer(_pendingProfileId!, answer);
    if (!mounted) return;
    _finishLogin(provider);
  }

  void _submitLogin(ProfileProvider provider) {
    final pin = _pinController.text;
    if (provider.verifyPin(_pendingProfileId ?? '', pin)) {
      _finishLogin(provider);
    } else {
      setState(() {
        _error = 'Parolă incorectă';
        _pinController.clear();
      });
      _refocusField();
    }
  }

  Future<void> _submitForgotAnswer(ProfileProvider provider) async {
    final answer = _answerController.text.trim();
    if (!provider.verifySecurityAnswer(_pendingProfileId ?? '', answer)) {
      setState(() => _error = 'Răspuns incorect');
      _refocusAnswerField();
      return;
    }
    _isRecovery = true;
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
