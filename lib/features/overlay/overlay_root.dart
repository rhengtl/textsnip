import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;
import 'package:flutter/material.dart' hide SelectionOverlay;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'floating_bubble.dart';
import '../capture/selection_overlay.dart';
import '../../services/overlay_ports.dart';

enum _OverlayMode { bubble, selection }

/// Root widget for the flutter_overlay_window isolate.
/// Switches between the floating bubble and the full-screen selection UI
/// in response to messages from the main isolate (delivered over an
/// IsolateNameServer port — see overlay_ports.dart).
class OverlayRoot extends StatefulWidget {
  const OverlayRoot({super.key});

  @override
  State<OverlayRoot> createState() => _OverlayRootState();
}

class _OverlayRootState extends State<OverlayRoot> {
  _OverlayMode _mode = _OverlayMode.bubble;
  final ReceivePort _receivePort = ReceivePort();

  /// Where the bubble window may sit so it stays fully on screen. Null until
  /// the main isolate has told us (the overlay view can't measure the screen
  /// itself); the bubble simply doesn't clamp until then.
  BubbleBounds? _bounds;

  @override
  void initState() {
    super.initState();
    IsolateNameServer.removePortNameMapping(kOverlayIsolatePort);
    IsolateNameServer.registerPortWithName(
        _receivePort.sendPort, kOverlayIsolatePort);
    _receivePort.listen((message) {
      if (message is! Map) return;
      switch (message['action']) {
        case 'show_selection':
          _enterSelectionMode(
            width: (message['screenWidth'] as num).toInt(),
            height: (message['screenHeight'] as num).toInt(),
          );
        case 'show_bubble':
          _enterBubbleMode(BubbleBounds.fromMap(message['bounds']));
        case 'set_bounds':
          final bounds = BubbleBounds.fromMap(message['bounds']);
          if (bounds != null && mounted) setState(() => _bounds = bounds);
      }
    });
  }

  @override
  void dispose() {
    IsolateNameServer.removePortNameMapping(kOverlayIsolatePort);
    _receivePort.close();
    super.dispose();
  }

  Future<void> _enterSelectionMode(
      {required int width, required int height}) async {
    // Expand the overlay window to cover the full screen before showing the
    // selection UI. Screen dimensions (in logical px) come from the main isolate
    // so we don't have to query them from the overlay's own (120×120) view.
    // enableDrag: false — the selection overlay must not be repositionable.
    await FlutterOverlayWindow.resizeOverlay(width, height, false);
    // resizeOverlay only changes the window size, not its position — the
    // full-screen window would otherwise keep the floating bubble's leftover
    // offset (e.g. shifted up by wherever the bubble was dragged), leaving a
    // band at the opposite edge undimmed and skewing the capture coordinates.
    // Pin it to the top-left origin so it covers the whole display and the
    // selection rect maps 1:1 onto the captured screenshot.
    await FlutterOverlayWindow.moveOverlay(const OverlayPosition(0, 0));
    if (mounted) setState(() => _mode = _OverlayMode.selection);
  }

  // Return the (reused) overlay engine to bubble mode and bubble size after a
  // snip, since its widget state persists across hide/show cycles.
  Future<void> _enterBubbleMode(BubbleBounds? bounds) async {
    await _resizeWhenReady(kBubbleWindowSize, kBubbleWindowSize, true);
    if (!mounted) return;
    setState(() {
      _mode = _OverlayMode.bubble;
      if (bounds != null) _bounds = bounds;
    });
  }

  /// resizeOverlay() with retries. The overlay engine (and this widget) is
  /// cached across hide/show cycles, so a `show_bubble` message can arrive
  /// before the plugin's freshly restarted service has attached the window
  /// and registered its method-channel handler — the call then fails with
  /// MissingPluginException or returns false. Retry briefly rather than
  /// leaving the window at the wrong size / this widget in the wrong mode.
  Future<void> _resizeWhenReady(int width, int height, bool enableDrag) async {
    const attempts = 40;
    const delay = Duration(milliseconds: 50);
    for (var i = 0; i < attempts; i++) {
      try {
        final ok = await FlutterOverlayWindow.resizeOverlay(
            width, height, enableDrag);
        if (ok == true) return;
      } on MissingPluginException {
        // Handler not registered yet.
      }
      if (!mounted) return;
      await Future.delayed(delay);
    }
  }

  @override
  Widget build(BuildContext context) => switch (_mode) {
        _OverlayMode.bubble => FloatingBubble(bounds: _bounds),
        _OverlayMode.selection => const SelectionOverlay(),
      };
}
