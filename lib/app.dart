import 'package:flutter/material.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/overlay/home_screen.dart';
import 'services/permission_service.dart';
import 'theme/app_theme.dart';

class TextSnipApp extends StatelessWidget {
  const TextSnipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TextSnip',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const _PermissionGate(),
    );
  }
}

class _PermissionGate extends StatefulWidget {
  const _PermissionGate();

  @override
  State<_PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<_PermissionGate>
    with WidgetsBindingObserver {
  final _permissions = PermissionService();
  bool? _allGranted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final granted = await _permissions.allGranted();
    if (mounted) setState(() => _allGranted = granted);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: switch (_allGranted) {
        null => const _SplashScreen(),
        true => const HomeScreen(),
        false => OnboardingScreen(
            onComplete: () => setState(() => _allGranted = true),
          ),
      },
    );
  }
}

/// Branded loading view shown while the initial permission check runs.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(AppAssets.logo, width: 96, height: 96),
            const SizedBox(height: 24),
            Text(
              'TextSnip',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
