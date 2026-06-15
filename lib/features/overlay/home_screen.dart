import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/capture_channel.dart';
import '../../services/ocr_service.dart';
import '../../services/overlay_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _overlay = OverlayService();
  final _capture = CaptureChannel();
  final _ocr = OcrService();
  StreamSubscription<dynamic>? _subscription;
  bool _bubbleActive = false;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _subscription = _overlay.listenForSnipRequests(_onSnipRequested);
    _startBubble();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _ocr.dispose();
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

  Future<void> _onSnipRequested() async {
    if (_isCapturing || !mounted) return;
    _isCapturing = true;
    try {
      await _runSnipFlow();
    } finally {
      _isCapturing = false;
    }
  }

  Future<void> _runSnipFlow() async {
    if (!mounted) return;

    // 1. Expand overlay to full screen and wait for user to draw a region.
    final screenSize = MediaQuery.sizeOf(context);
    final regionData = await _overlay.startRegionSelection(screenSize);

    // 2. Close overlay before capturing so it isn't in the frame.
    await _overlay.hideBubble();
    if (mounted) setState(() => _bubbleActive = false);

    if (regionData == null) {
      // User cancelled — restore the bubble and stop.
      await _startBubble();
      return;
    }

    // 3. Brief delay to let the overlay clear from the screen.
    await Future.delayed(const Duration(milliseconds: 80));

    // 4. Convert logical-pixel rect to physical pixels and capture.
    final dpr = (regionData['dpr'] as num).toDouble();
    String? path;
    try {
      path = await _capture.captureRegion(
        left:   ((regionData['left']   as num) * dpr).round(),
        top:    ((regionData['top']    as num) * dpr).round(),
        width:  ((regionData['width']  as num) * dpr).round(),
        height: ((regionData['height'] as num) * dpr).round(),
      );
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
    }

    // 5. Restore the bubble.
    await _startBubble();

    if (path == null) return;

    // 6. Run OCR on the captured image.
    String text;
    try {
      text = await _ocr.extractText(path);
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('OCR failed: $e')),
        );
      }
      return;
    }

    // Phase 8 will push ResultScreen here; for now show a snackbar preview.
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            text.trim().isEmpty ? 'No text found.' : text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
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
                  label: Text(_bubbleActive ? 'Stop bubble' : 'Start bubble'),
                  onPressed: _isCapturing
                      ? null
                      : (_bubbleActive ? _stopBubble : _startBubble),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
