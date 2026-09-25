import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/money_provider.dart';
import 'providers/profile_provider.dart';
import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final profileProvider = ProfileProvider();
  await profileProvider.init();
  final moneyProvider = MoneyProvider();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: profileProvider),
        ChangeNotifierProvider.value(value: moneyProvider),
      ],
      child: const PortofelApp(),
    ),
  );
}

class PortofelApp extends StatelessWidget {
  const PortofelApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ProfileProvider>().themeMode;
    final lightScheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    return MaterialApp(
      title: 'Portofel',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: lightScheme,
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            backgroundColor: lightScheme.secondaryContainer,
            foregroundColor: lightScheme.onSecondaryContainer,
            side: BorderSide(color: lightScheme.outline.withValues(alpha: 0.4)),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _loadedProfileId;
  bool _loading = false;

  Future<void> _ensureLoaded(String profileId) async {
    if (_loading || _loadedProfileId == profileId) return;
    _loading = true;
    await context.read<MoneyProvider>().loadProfile(profileId);
    if (!mounted) return;
    setState(() {
      _loadedProfileId = profileId;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profileProvider = context.watch<ProfileProvider>();

    if (!profileProvider.isUnlocked || profileProvider.activeProfileId == null) {
      _loadedProfileId = null;
      return const LockScreen();
    }

    final activeId = profileProvider.activeProfileId!;
    if (_loadedProfileId != activeId) {
      _ensureLoaded(activeId);
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return const HomeScreen();
  }
}
