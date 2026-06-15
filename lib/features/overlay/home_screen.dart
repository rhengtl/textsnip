import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/overlay_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _overlay = OverlayService();
  StreamSubscription<dynamic>? _subscription;
  bool _bubbleActive = false;

  @override
  void initState() {
    super.initState();
    _subscription = _overlay.listenForSnipRequests(_onSnipRequested);
    _startBubble();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _startBubble() async {
    await _overlay.showBubble();
    if (mounted) setState(() => _bubbleActive = true);
  }

  Future<void> _stopBubble() async {
    await _overlay.hideBubble();
    if (mounted) setState(() => _bubbleActive = false);
  }

  void _onSnipRequested() {
    // Phase 5 will navigate to the capture flow here.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Snip triggered — capture coming in Phase 5')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('TextSnip'), centerTitle: false),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _bubbleActive
                      ? Icons.radio_button_on
                      : Icons.radio_button_off,
                  size: 64,
                  color: _bubbleActive
                      ? Colors.green.shade600
                      : theme.colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  _bubbleActive ? 'Bubble is active' : 'Bubble is inactive',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  _bubbleActive
                      ? 'Tap the floating button over any app to start a snip.'
                      : 'Start the bubble to begin capturing text.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.outline),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  icon: Icon(_bubbleActive ? Icons.stop : Icons.play_arrow),
                  label:
                      Text(_bubbleActive ? 'Stop bubble' : 'Start bubble'),
                  onPressed: _bubbleActive ? _stopBubble : _startBubble,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
