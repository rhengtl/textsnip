import 'package:flutter/material.dart';
import 'features/onboarding/onboarding_screen.dart';
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

/// Checks permissions on startup and routes to onboarding if needed.
class _PermissionGate extends StatefulWidget {
  const _PermissionGate();

  @override
  State<_PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<_PermissionGate> {
  final _permissions = PermissionService();
  late final Future<bool> _check;

  @override
  void initState() {
    super.initState();
    _check = _permissions.allGranted();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _check,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        if (snapshot.data!) return const _HomeScreen();
        return OnboardingScreen(
          onComplete: () => setState(() {
            _check = Future.value(true);
          }),
        );
      },
    );
  }
}

// Placeholder home screen — will be replaced when the overlay is wired up (Phase 4).
class _HomeScreen extends StatelessWidget {
  const _HomeScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.crop, size: 72, color: theme.colorScheme.primary),
              const SizedBox(height: 24),
              Text('TextSnip is ready',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('The floating button will appear here in Phase 4.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.outline)),
            ],
          ),
        ),
      ),
    );
  }
}
