import 'package:flutter/material.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/overlay/home_screen.dart';
import 'services/permission_service.dart';

class TextSnipApp extends StatelessWidget {
  const TextSnipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TextSnip',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
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
    if (_allGranted == null) return const SizedBox.shrink();
    if (_allGranted!) return const HomeScreen();
    return OnboardingScreen(
      onComplete: () => setState(() => _allGranted = true),
    );
  }
}
