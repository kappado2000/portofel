import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/money_provider.dart';
import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final moneyProvider = MoneyProvider();
  await moneyProvider.init();

  runApp(
    ChangeNotifierProvider.value(
      value: moneyProvider,
      child: const PortofelApp(),
    ),
  );
}

class PortofelApp extends StatelessWidget {
  const PortofelApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<MoneyProvider>().themeMode;
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
  bool _unlocked = false;

  @override
  Widget build(BuildContext context) {
    if (!_unlocked) {
      return LockScreen(onUnlocked: () => setState(() => _unlocked = true));
    }
    return const HomeScreen();
  }
}
