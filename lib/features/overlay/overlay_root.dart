import 'package:flutter/material.dart' hide SelectionOverlay;
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'floating_bubble.dart';
import '../capture/selection_overlay.dart';

enum _OverlayMode { bubble, selection }

/// Root widget for the flutter_overlay_window isolate.
/// Switches between the floating bubble and the full-screen selection UI
/// in response to messages from the main isolate.
class OverlayRoot extends StatefulWidget {
  const OverlayRoot({super.key});

  @override
  State<OverlayRoot> createState() => _OverlayRootState();
}

class _OverlayRootState extends State<OverlayRoot> {
  _OverlayMode _mode = _OverlayMode.bubble;

  @override
  void initState() {
    super.initState();
    // Listen for commands sent from the main isolate via shareData.
    FlutterOverlayWindow.overlayListener.listen((event) {
      if (event is Map && event['action'] == 'show_selection') {
        _enterSelectionMode(
          width: (event['screenWidth'] as num).toInt(),
          height: (event['screenHeight'] as num).toInt(),
        );
      }
    });
  }

  Future<void> _enterSelectionMode({required int width, required int height}) async {
    // Expand the overlay window to cover the full screen before showing the
    // selection UI. Screen dimensions (in logical px) come from the main isolate
    // so we don't have to query them from the overlay's own (120×120) view.
    // enableDrag: false — the selection overlay must not be repositionable.
    await FlutterOverlayWindow.resizeOverlay(width, height, false);
    if (mounted) setState(() => _mode = _OverlayMode.selection);
  }

  @override
  Widget build(BuildContext context) => switch (_mode) {
        _OverlayMode.bubble => const FloatingBubble(),
        _OverlayMode.selection => const SelectionOverlay(),
      };
}
