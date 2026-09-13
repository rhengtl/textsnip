import 'dart:ui' show IsolateNameServer;
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../../services/overlay_ports.dart';
import '../../theme/app_theme.dart';

/// Runs inside the flutter_overlay_window isolate — no access to main-app state
/// or [Theme], so it styles itself from the shared [AppColors] constants. On tap
/// it sends a `start_snip` message to the main isolate over an IsolateNameServer
/// port.
///
/// Dragging is done natively by the plugin (enableDrag: true), which simply
/// adds the finger delta to the window position with no limits — the bubble
/// could be dragged completely off screen. The plugin can't be told to clamp,
/// but this widget sees the same pointer events, so after every move (and on
/// release) it reads the window position back and, if it has strayed outside
/// [bounds], moves it to the nearest allowed point. Native dragging then
/// continues from the clamped position, so the bubble sticks to the edge
/// instead of disappearing behind it.
class FloatingBubble extends StatefulWidget {
  /// Allowed rectangle for the window's top-left corner (logical px). While
  /// null, no clamping happens.
  final BubbleBounds? bounds;

  const FloatingBubble({super.key, this.bounds});

  @override
  State<FloatingBubble> createState() => _FloatingBubbleState();
}

class _FloatingBubbleState extends State<FloatingBubble> {
  // Position reads/writes go over a method channel; keep at most one in
  // flight and remember whether another pass is needed afterwards.
  bool _clampInFlight = false;
  bool _clampPending = false;

  @override
  void didUpdateWidget(FloatingBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    // New bounds (e.g. after a rotation) may leave the bubble off screen.
    if (widget.bounds != oldWidget.bounds) _clampToBounds();
  }

  Future<void> _clampToBounds() async {
    if (widget.bounds == null) return;
    if (_clampInFlight) {
      _clampPending = true;
      return;
    }
    _clampInFlight = true;
    try {
      do {
        _clampPending = false;
        final bounds = widget.bounds;
        if (bounds == null) break;
        final pos = await FlutterOverlayWindow.getOverlayPosition();
        final x = bounds.clampX(pos.x);
        final y = bounds.clampY(pos.y);
        if (x != pos.x || y != pos.y) {
          await FlutterOverlayWindow.moveOverlay(OverlayPosition(x, y));
        }
      } while (_clampPending && mounted);
    } catch (_) {
      // Best effort: the window may be mid-teardown.
    } finally {
      _clampInFlight = false;
    }
  }

  void _onTap() {
    final port = IsolateNameServer.lookupPortByName(kMainIsolatePort);
    port?.send({'action': 'start_snip'});
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerMove: (_) => _clampToBounds(),
      onPointerUp: (_) => _clampToBounds(),
      onPointerCancel: (_) => _clampToBounds(),
      child: Center(
        child: GestureDetector(
          onTap: _onTap,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.9),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandCyan.withValues(alpha: 0.45),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
                const BoxShadow(
                  color: Colors.black38,
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.document_scanner_outlined,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}
