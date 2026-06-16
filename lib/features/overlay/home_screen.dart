import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/snip_result.dart';
import '../../services/capture_channel.dart';
import '../../services/ocr_service.dart';
import '../../services/overlay_service.dart';
import '../result/result_screen.dart';

enum _SnipState { idle, selectingRegion, capturing, recognising }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _overlay = OverlayService();
  final _capture = CaptureChannel();
  final _ocr = OcrService();
  bool _bubbleActive = false;
  _SnipState _state = _SnipState.idle;

  @override
  void initState() {
    super.initState();
    _overlay.start(_onSnipRequested);
  }

  @override
  void dispose() {
    _overlay.dispose();
    _ocr.dispose();
    super.dispose();
  }

  /// Start a bubble session: request screen-capture consent now (while the app
  /// is in the foreground — it cannot be granted from the background), then show
  /// the bubble. The projection stays alive so later snips from other apps work.
  Future<void> _startBubble() async {
    final granted = await _capture.startCapture();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Screen capture permission is required to snip text.'),
          ),
        );
      }
      return;
    }
    await _overlay.showBubble();
    if (mounted) setState(() => _bubbleActive = true);
  }

  /// Re-show the bubble mid-snip without re-requesting consent (the projection
  /// is already alive).
  Future<void> _showBubble() async {
    await _overlay.showBubble();
    if (mounted) setState(() => _bubbleActive = true);
  }

  Future<void> _stopBubble() async {
    await _overlay.hideBubble();
    await _capture.stopCapture();
    if (mounted) setState(() => _bubbleActive = false);
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

    // 5. Restore the bubble (projection still alive — no re-consent).
    await _showBubble();

    if (path == null) return;
    final imagePath = path; // non-nullable alias — promotion lost across awaits

    // 6. Run OCR on the captured image.
    if (mounted) setState(() => _state = _SnipState.recognising);

    String text;
    try {
      text = await _ocr.extractText(imagePath);
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('OCR failed: $e')),
        );
      }
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
          _bubbleActive ? 'Bubble is active' : 'Bubble is inactive',
        _SnipState.selectingRegion => 'Selecting region…',
        _SnipState.capturing => 'Capturing…',
        _SnipState.recognising => 'Recognising text…',
      };

  String get _statusSubtitle => switch (_state) {
        _SnipState.idle => _bubbleActive
            ? 'Tap the floating button over any app to start a snip.'
            : 'Start the bubble to begin capturing text.',
        _SnipState.selectingRegion =>
          'Draw a rectangle around the text you want to extract.',
        _SnipState.capturing => 'Taking a screenshot of the selected region.',
        _SnipState.recognising => 'Running on-device text recognition.',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _state != _SnipState.idle;

    return Scaffold(
      appBar: AppBar(title: const Text('TextSnip'), centerTitle: false),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: busy
                      ? const SizedBox(
                          key: ValueKey('progress'),
                          width: 64,
                          height: 64,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : Icon(
                          key: const ValueKey('icon'),
                          _bubbleActive
                              ? Icons.radio_button_on
                              : Icons.radio_button_off,
                          size: 64,
                          color: _bubbleActive
                              ? Colors.green.shade600
                              : theme.colorScheme.outline,
                        ),
                ),
                const SizedBox(height: 16),
                Text(_statusLabel, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  _statusSubtitle,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.outline),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  icon: Icon(
                      _bubbleActive && !busy ? Icons.stop : Icons.play_arrow),
                  label: Text(
                      _bubbleActive && !busy ? 'Stop bubble' : 'Start bubble'),
                  onPressed: busy
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
