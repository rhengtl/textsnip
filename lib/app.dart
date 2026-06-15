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
        if (snapshot.data!) return const HomeScreen();
        return OnboardingScreen(
          onComplete: () => setState(() {
            _check = Future.value(true);
          }),
        );
      },
    );
  }
}
