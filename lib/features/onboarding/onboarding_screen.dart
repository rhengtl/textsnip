import 'package:flutter/material.dart';
import '../../services/permission_service.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  final _permissions = PermissionService();
  int _step = 0;
  bool _overlayGranted = false;
  bool _notificationGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatuses();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Re-check after returning from the system Settings screen (overlay permission).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatuses();
  }

  Future<void> _refreshStatuses() async {
    final overlay = await _permissions.hasOverlayPermission();
    final notification = await _permissions.hasNotificationPermission();
    if (!mounted) return;
    setState(() {
      _overlayGranted = overlay;
      _notificationGranted = notification;
    });
    if (_overlayGranted && _notificationGranted) widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: KeyedSubtree(
              key: ValueKey(_step),
              child: _buildStep(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep() => switch (_step) {
        0 => _WelcomePage(onNext: () => setState(() => _step = 1)),
        1 => _PermissionPage(
            icon: Icons.picture_in_picture_alt_outlined,
            title: 'Display over other apps',
            description:
                'TextSnip places a small floating button above your other apps '
                'so you can trigger a capture at any time.\n\n'
                'This only allows showing that button — TextSnip cannot see '
                "what's on your screen unless you explicitly start a snip.",
            granted: _overlayGranted,
            onGrant: _permissions.requestOverlayPermission,
            // Overlay permission opens Settings; the resume observer re-checks.
            onNext: _overlayGranted ? () => setState(() => _step = 2) : null,
          ),
        2 => _PermissionPage(
            icon: Icons.notifications_outlined,
            title: 'Show notifications',
            description:
                'Android requires apps that run a background capture service '
                'to display a persistent notification.\n\n'
                'The notification appears only while a capture is in progress '
                'and is dismissed immediately after.',
            granted: _notificationGranted,
            onGrant: () async {
              await _permissions.requestNotificationPermission();
              await _refreshStatuses();
            },
            onNext: _notificationGranted ? widget.onComplete : null,
          ),
        _ => const SizedBox.shrink(),
      };
}

// ─── Pages ───────────────────────────────────────────────────────────────────

class _WelcomePage extends StatelessWidget {
  final VoidCallback onNext;
  const _WelcomePage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(),
        Image.asset('TextSnip.png', width: 80, height: 80),
        const SizedBox(height: 24),
        Text(
          'Welcome to TextSnip',
          style: theme.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Text(
          'Tap the floating button over any app, drag a rectangle around any '
          'text on screen, and get a clean copy instantly.\n\n'
          'Everything runs on your device — your screen content is never '
          'uploaded anywhere.',
          style: theme.textTheme.bodyLarge,
        ),
        const Spacer(),
        _ActionButton(label: 'Get started', onPressed: onNext),
      ],
    );
  }
}

class _PermissionPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool granted;
  final VoidCallback onGrant;
  final VoidCallback? onNext;

  const _PermissionPage({
    required this.icon,
    required this.title,
    required this.description,
    required this.granted,
    required this.onGrant,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(),
        Row(
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            if (granted)
              Icon(Icons.check_circle_rounded,
                  color: Colors.green.shade600, size: 28),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          title,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Text(description, style: theme.textTheme.bodyLarge),
        const Spacer(),
        if (granted)
          _ActionButton(label: 'Continue', onPressed: onNext ?? () {})
        else
          _ActionButton(label: 'Grant permission', onPressed: onGrant),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const _ActionButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}
