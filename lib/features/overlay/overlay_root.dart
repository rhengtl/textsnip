import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;
import 'package:flutter/material.dart' hide SelectionOverlay;
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
          _enterBubbleMode();
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
    if (mounted) setState(() => _mode = _OverlayMode.selection);
  }

  // Return the (reused) overlay engine to bubble mode and 120×120 size after a
  // snip, since its widget state persists across hide/show cycles.
  Future<void> _enterBubbleMode() async {
    await FlutterOverlayWindow.resizeOverlay(120, 120, true);
    if (mounted) setState(() => _mode = _OverlayMode.bubble);
  }

  @override
  Widget build(BuildContext context) => switch (_mode) {
        _OverlayMode.bubble => const FloatingBubble(),
        _OverlayMode.selection => const SelectionOverlay(),
      };
}
