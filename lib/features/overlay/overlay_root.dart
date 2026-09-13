import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;
import 'package:flutter/material.dart' hide SelectionOverlay;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'floating_bubble.dart';
import '../capture/selection_overlay.dart';
import '../../services/overlay_ports.dart';

/// [hidden] renders nothing (fully transparent). It is the state the window
/// is put in for every geometry change: Android's TextureView scales the last
/// rendered buffer to the new window size until Flutter draws a fresh frame,
/// so resizing while the bubble or the selection UI is on screen shows them
/// stretched/squashed for a frame or two. A transparent buffer stretches to
/// nothing.
enum _OverlayMode { bubble, selection, hidden }

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
          final position = message['position'];
          _enterBubbleMode(
            BubbleBounds.fromMap(message['bounds']),
            position is Map
                ? OverlayPosition(
                    (position['x'] as num).toDouble(),
                    (position['y'] as num).toDouble(),
                  )
                : null,
          );
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
    // Blank the window first so the bubble isn't smeared across the screen
    // while the window grows.
    await _hideAndSettle();
    if (!mounted) return;
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
    // Show the scrim straight away: a uniform colour scales cleanly if the
    // window manager animates the resize (it reads as the scrim expanding
    // out of the bubble). The selection UI holds back its text/pill until
    // kWindowResizeSettle has passed — see SelectionOverlay.
    if (mounted) setState(() => _mode = _OverlayMode.selection);
  }

  /// Return to bubble mode and bubble size.
  ///
  /// Two situations arrive here:
  ///  * A fresh window after a capture (the main isolate closed the old one
  ///    so it wasn't in the screenshot). The tree is already blank, the
  ///    window is already bubble-sized, so this is just a mode switch.
  ///  * The live full-screen selector after a cancel/timeout, with
  ///    [position] telling us where the bubble belongs. The window has to
  ///    shrink, which some ROMs animate; blank it first, and only draw the
  ///    bubble once the animation has had time to settle — otherwise the
  ///    bubble would be drawn squashed from full-screen down to its size.
  Future<void> _enterBubbleMode(
      BubbleBounds? bounds, OverlayPosition? position) async {
    final morphing = _mode == _OverlayMode.selection;
    if (morphing) await _hideAndSettle();
    if (!mounted) return;
    await _resizeWhenReady(kBubbleWindowSize, kBubbleWindowSize, true);
    if (position != null) {
      await FlutterOverlayWindow.moveOverlay(position);
    }
    if (morphing) await Future.delayed(kWindowResizeSettle);
    if (!mounted) return;
    setState(() {
      _mode = _OverlayMode.bubble;
      if (bounds != null) _bounds = bounds;
    });
  }

  /// Switch to [_OverlayMode.hidden] and wait until that transparent frame
  /// has actually been produced, so a subsequent window resize scales an
  /// empty buffer rather than the last visible UI.
  Future<void> _hideAndSettle() async {
    if (!mounted) return;
    if (_mode != _OverlayMode.hidden) {
      setState(() => _mode = _OverlayMode.hidden);
    }
    // endOfFrame resolves once the frame is handed to the engine; give the
    // raster thread a beat to present it before the window changes shape.
    await WidgetsBinding.instance.endOfFrame;
    await Future.delayed(const Duration(milliseconds: 32));
  }

  /// Called by the selection UI the moment it has a result (or is cancelled),
  /// before the main isolate is told. The main isolate reacts by closing this
  /// window and opening a fresh bubble-sized one on the same cached engine;
  /// having the tree already blank means that new window's first frame is
  /// empty instead of the selection scrim shrunk to 120×120.
  void _onSelectionFinished() {
    if (mounted) setState(() => _mode = _OverlayMode.hidden);
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
        _OverlayMode.selection =>
          SelectionOverlay(onFinished: _onSelectionFinished),
        _OverlayMode.hidden => const SizedBox.shrink(),
      };
}
