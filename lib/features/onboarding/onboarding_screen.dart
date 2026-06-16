import 'package:flutter/material.dart';
import '../../services/permission_service.dart';
import '../../theme/app_theme.dart';

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
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
          child: Column(
            children: [
              _StepDots(count: 3, active: _step),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.06, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: _buildStep(),
                  ),
                ),
              ),
            ],
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

// ─── Shared chrome ───────────────────────────────────────────────────────────

/// Row of progress pills reflecting the current onboarding step.
class _StepDots extends StatelessWidget {
  final int count;
  final int active;
  const _StepDots({required this.count, required this.active});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 5,
              margin: EdgeInsets.only(right: i == count - 1 ? 0 : 8),
              decoration: BoxDecoration(
                color: i <= active
                    ? scheme.primary
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
      ],
    );
  }
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
        const Spacer(flex: 2),
        Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.brandCyan.withValues(alpha: 0.10),
            ),
            child: Image.asset(AppAssets.logo, width: 104, height: 104),
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'Welcome to TextSnip',
          style: theme.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Text(
          'Grab any text off your screen in seconds — fully on-device.',
          style: theme.textTheme.bodyLarge
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 28),
        const _FeatureRow(
          icon: Icons.touch_app_outlined,
          title: 'Tap the bubble',
          subtitle: 'A floating button sits over any app.',
        ),
        const SizedBox(height: 18),
        const _FeatureRow(
          icon: Icons.crop_free,
          title: 'Drag to select',
          subtitle: 'Draw a box around the text you want.',
        ),
        const SizedBox(height: 18),
        const _FeatureRow(
          icon: Icons.content_copy_outlined,
          title: 'Copy or share',
          subtitle: 'Get clean, editable text instantly.',
        ),
        const Spacer(flex: 3),
        const _PrivacyNote(),
        const SizedBox(height: 16),
        _ActionButton(label: 'Get started', onPressed: onNext),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon,
              size: 22, color: theme.colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.lock_outline,
            size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Your screen content never leaves your device.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
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
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(flex: 2),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: granted
                ? Colors.green.withValues(alpha: 0.14)
                : scheme.primaryContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(
            granted ? Icons.check_rounded : icon,
            size: 38,
            color: granted ? Colors.green.shade600 : scheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            if (granted) _GrantedChip(),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          description,
          style: theme.textTheme.bodyLarge
              ?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
        ),
        const Spacer(flex: 3),
        if (granted)
          _ActionButton(label: 'Continue', onPressed: onNext ?? () {})
        else
          _ActionButton(label: 'Grant permission', onPressed: onGrant),
      ],
    );
  }
}

class _GrantedChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded,
              size: 16, color: Colors.green.shade600),
          const SizedBox(width: 5),
          Text(
            'Granted',
            style: TextStyle(
              color: Colors.green.shade700,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
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
      child: FilledButton(
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}
