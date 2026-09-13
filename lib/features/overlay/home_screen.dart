import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import '../../models/snip_result.dart';
import '../../services/capture_channel.dart';
import '../../services/ocr_service.dart';
import '../../services/overlay_service.dart';
import '../../theme/app_theme.dart';
import '../result/result_screen.dart';

enum _SnipState { idle, selectingRegion, capturing, recognising }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _overlay = OverlayService();
  final _capture = CaptureChannel();
  final _ocr = OcrService();

  /// True while a capture session (projection + bubble + notification) is
  /// live. Mirrors native state; see [_syncSessionState].
  bool _bubbleActive = false;
  _SnipState _state = _SnipState.idle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _overlay.start(_onSnipRequested);
    _capture.setOnSessionEnded(_onSessionEnded);
    // The native services outlive this widget (permission round-trips,
    // hot restart, activity recreation), so pick up whatever is already live.
    _syncSessionState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _overlay.dispose();
    _capture.dispose();
    _ocr.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from another app / Settings / the notification shade: the
    // session may have been ended from the notification or by the system.
    if (state == AppLifecycleState.resumed) _syncSessionState();
  }

  /// Reconcile [_bubbleActive] (and the bubble itself) with the native
  /// capture service, which is the source of truth for whether a session is
  /// live. Never runs mid-snip, when the overlay is intentionally hidden.
  Future<void> _syncSessionState() async {
    if (_state != _SnipState.idle) return;
    final captureActive = await _capture.isCaptureActive();
    if (!mounted || _state != _SnipState.idle) return;

    if (captureActive) {
      // Session alive but bubble missing (e.g. the overlay isolate lost its
      // port while this screen was unmounted): restore it.
      if (!await _overlay.isActive) await _presentBubble();
    } else {
      // No projection: a bubble would be a dead button. Remove it.
      await _overlay.hideBubble();
    }
    if (mounted) setState(() => _bubbleActive = captureActive);
  }

  /// The native session ended without us asking (Stop action on the
  /// notification, projection revoked by the system, service failure). The
  /// bubble has already been taken down natively.
  void _onSessionEnded() {
    if (!mounted) return;
    final wasActive = _bubbleActive || _state != _SnipState.idle;
    setState(() => _bubbleActive = false);
    // Unblock a snip that is waiting for the user to draw a region; the flow
    // then sees the session is gone and bails out cleanly.
    _overlay.cancelRegionSelection();
    if (wasActive) {
      _showMessage(
        'Screen capture session ended. Start the bubble again to keep snipping.',
      );
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Start a bubble session: request screen-capture consent now (while the app
  /// is in the foreground — it cannot be granted from the background), then show
  /// the bubble. The projection stays alive so later snips from other apps work.
  Future<void> _startBubble() async {
    final granted = await _capture.startCapture();
    if (!granted) {
      _showMessage('Screen capture permission is required to snip text.');
      return;
    }
    try {
      await _presentBubble();
    } catch (e) {
      // Overlay permission revoked meanwhile, or the overlay engine failed.
      // Don't leave a headless capture session (and its notification) behind.
      await _capture.stopCapture();
      _showMessage('Could not show the floating bubble: $e');
      return;
    }
    // The session could have ended during the await above (e.g. the user hit
    // Stop on the notification straight away); trust native state, not ours.
    final stillActive = await _capture.isCaptureActive();
    if (!stillActive) {
      await _overlay.hideBubble();
      _showMessage('Screen capture session ended before it could start.');
    }
    if (mounted) setState(() => _bubbleActive = stillActive);
  }

  /// Show the bubble and let the native side tidy the overlay plugin's
  /// notification channel. Every bubble show goes through here.
  Future<void> _presentBubble() async {
    await _overlay.showBubble();
    await _capture.overlayShown();
  }

  /// Re-show the bubble mid-snip without re-requesting consent (the projection
  /// is already alive).
  Future<void> _showBubble() async {
    await _presentBubble();
    if (mounted) setState(() => _bubbleActive = true);
  }

  Future<void> _stopBubble() async {
    // Mark inactive first: stopCapture() makes the native side fire
    // sessionEnded, and _onSessionEnded must see this as a deliberate stop.
    if (mounted) setState(() => _bubbleActive = false);
    await _overlay.hideBubble();
    await _capture.stopCapture();
  }

  Future<void> _onSnipRequested() async {
    if (_state != _SnipState.idle || !mounted) return;
    if (mounted) setState(() => _state = _SnipState.selectingRegion);
    try {
      await _runSnipFlow();
    } finally {
      if (mounted) setState(() => _state = _SnipState.idle);
    }
  }

  Future<void> _runSnipFlow() async {
    if (!mounted) return;

    // 1. Expand overlay to full screen and wait for the user to draw a region.
    final screenSize = MediaQuery.sizeOf(context);
    final regionData = await _overlay.startRegionSelection(screenSize);

    // 2. Close overlay before capturing so it isn't in the frame.
    //    Position was already saved by startRegionSelection; the overlay is now
    //    full-screen, so don't overwrite the saved bubble position here.
    await _overlay.hideBubble(savePosition: false);
    if (mounted) setState(() => _bubbleActive = false);

    // The session may have ended while the selector was up (Stop on the
    // notification, projection revoked). There is nothing to capture with and
    // no bubble to restore; _onSessionEnded has already told the user.
    if (!await _capture.isCaptureActive()) return;

    if (regionData == null) {
      await _showBubble();
      return;
    }

    // 3. Brief delay to let the overlay clear from the screen.
    await Future.delayed(const Duration(milliseconds: 80));

    // 4. Convert logical-pixel rect to physical pixels and capture.
    if (mounted) setState(() => _state = _SnipState.capturing);

    final dpr = (regionData['dpr'] as num).toDouble();
    String? path;
    var sessionLost = false;
    try {
      path = await _capture.captureRegion(
        left:   ((regionData['left']   as num) * dpr).round(),
        top:    ((regionData['top']    as num) * dpr).round(),
        width:  ((regionData['width']  as num) * dpr).round(),
        height: ((regionData['height'] as num) * dpr).round(),
      );
    } on PlatformException catch (e) {
      sessionLost = e.code == CaptureChannel.noProjectionCode;
      if (!sessionLost) _showMessage('Capture failed: ${e.message ?? e.code}');
    } on Exception catch (e) {
      _showMessage('Capture failed: $e');
    }

    // 5. Restore the bubble (projection still alive — no re-consent). If the
    //    projection died during the capture, the native side has already
    //    removed the bubble and _onSessionEnded handled the UI.
    if (sessionLost) return;
    await _showBubble();

    if (path == null) return;
    final imagePath = path; // non-nullable alias — promotion lost across awaits

    // 6. Run OCR on the captured image.
    if (mounted) setState(() => _state = _SnipState.recognising);

    String text;
    try {
      text = await _ocr.extractText(imagePath);
    } on Exception catch (e) {
      _showMessage('OCR failed: $e');
      return;
    } finally {
      // Privacy: delete the cached PNG regardless of OCR outcome.
      try {
        await File(imagePath).delete();
      } catch (_) {}
    }

    // 7. Bring TextSnip to the foreground (user may be in another app).
    await _capture.bringToFront();

    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            result: SnipResult(text: text),
          ),
        ),
      );
    }
  }

  String get _statusLabel => switch (_state) {
        _SnipState.idle =>
          _bubbleActive ? 'Bubble is active' : 'Ready to snip',
        _SnipState.selectingRegion => 'Selecting region…',
        _SnipState.capturing => 'Capturing…',
        _SnipState.recognising => 'Recognising text…',
      };

  String get _statusSubtitle => switch (_state) {
        _SnipState.idle => _bubbleActive
            ? 'Tap the floating button over any app to start a snip.'
            : 'Start the bubble to begin capturing text from any app.',
        _SnipState.selectingRegion =>
          'Draw a rectangle around the text you want to extract.',
        _SnipState.capturing => 'Taking a screenshot of the selected region.',
        _SnipState.recognising => 'Running on-device text recognition.',
      };

  @override
  Widget build(BuildContext context) {
    final busy = _state != _SnipState.idle;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(AppAssets.logo, height: 30),
            const SizedBox(width: 10),
            const Text('TextSnip'),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _StatusHero(state: _state, bubbleActive: _bubbleActive),
                        const SizedBox(height: 28),
                        Text(
                          _statusLabel,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _statusSubtitle,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 28),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: !busy && !_bubbleActive
                              ? const _HowItWorksCard()
                              : (_bubbleActive && !busy
                                  ? const _ActiveSessionCard()
                                  : const SizedBox.shrink()),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _PrimaryAction(
                bubbleActive: _bubbleActive,
                busy: busy,
                onStart: _startBubble,
                onStop: _stopBubble,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Hero status indicator ───────────────────────────────────────────────────

class _StatusHero extends StatelessWidget {
  final _SnipState state;
  final bool bubbleActive;
  const _StatusHero({required this.state, required this.bubbleActive});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final busy = state != _SnipState.idle;

    final Widget core;
    if (busy) {
      core = _Ring(
        gradient: false,
        scheme: scheme,
        child: SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(strokeWidth: 3, color: scheme.primary),
        ),
      );
    } else if (bubbleActive) {
      core = _PulsingRing(
        child: _Ring(
          gradient: true,
          scheme: scheme,
          child: const Icon(Icons.document_scanner_outlined,
              size: 48, color: Colors.white),
        ),
      );
    } else {
      core = _Ring(
        gradient: false,
        scheme: scheme,
        child: Icon(Icons.crop_free,
            size: 48, color: scheme.onSurfaceVariant),
      );
    }

    return SizedBox(width: 160, height: 160, child: Center(child: core));
  }
}

/// Circular badge — gradient-filled when active, soft surface otherwise.
class _Ring extends StatelessWidget {
  final bool gradient;
  final ColorScheme scheme;
  final Widget child;
  const _Ring({
    required this.gradient,
    required this.scheme,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      height: 132,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: gradient ? AppColors.brandGradient : null,
        color: gradient ? null : scheme.surfaceContainerHighest,
        boxShadow: gradient
            ? [
                BoxShadow(
                  color: AppColors.brandCyan.withValues(alpha: 0.35),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Center(child: child),
    );
  }
}

/// Expanding, fading halo behind an active badge to signal "live".
class _PulsingRing extends StatefulWidget {
  final Widget child;
  const _PulsingRing({required this.child});

  @override
  State<_PulsingRing> createState() => _PulsingRingState();
}

class _PulsingRingState extends State<_PulsingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 132 + 56 * t,
              height: 132 + 56 * t,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.brandCyan.withValues(alpha: 0.22 * (1 - t)),
              ),
            ),
            child!,
          ],
        );
      },
      child: widget.child,
    );
  }
}

// ─── Supporting cards ────────────────────────────────────────────────────────

class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How it works',
            style:
                theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          const _Step(
            number: 1,
            text: 'Start the bubble — a floating button appears over your apps.',
          ),
          const SizedBox(height: 12),
          const _Step(
            number: 2,
            text: 'Tap it in any app, then drag a box around the text.',
          ),
          const SizedBox(height: 12),
          const _Step(
            number: 3,
            text: 'Review the extracted text, then copy or share it.',
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String text;
  const _Step({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$number',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              text,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActiveSessionCard extends StatelessWidget {
  const _ActiveSessionCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              size: 20, color: theme.colorScheme.onPrimaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Switch to any app — the bubble stays on top, ready to snip. '
              'You can also stop it from the TextSnip notification.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Primary action button ───────────────────────────────────────────────────

class _PrimaryAction extends StatelessWidget {
  final bool bubbleActive;
  final bool busy;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;

  const _PrimaryAction({
    required this.bubbleActive,
    required this.busy,
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showStop = bubbleActive && !busy;

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        icon: Icon(showStop ? Icons.stop_rounded : Icons.play_arrow_rounded),
        label: Text(showStop ? 'Stop bubble' : 'Start bubble'),
        style: showStop
            ? FilledButton.styleFrom(
                backgroundColor: scheme.errorContainer,
                foregroundColor: scheme.onErrorContainer,
              )
            : null,
        onPressed: busy ? null : (bubbleActive ? onStop : onStart),
      ),
    );
  }
}
