import 'dart:async';
import 'package:flutter/painting.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class OverlayService {
  Future<void> showBubble() => FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        overlayTitle: 'TextSnip active',
        overlayContent: 'Tap the bubble to capture text',
        flag: OverlayFlag.defaultFlag,
        visibility: NotificationVisibility.visibilityPublic,
        positionGravity: PositionGravity.auto,
        height: 120,
        width: 120,
      );

  Future<void> hideBubble() => FlutterOverlayWindow.closeOverlay();

  Future<bool> get isActive => FlutterOverlayWindow.isActive();

  /// Returns the subscription so the caller can cancel it on dispose.
  StreamSubscription<dynamic> listenForSnipRequests(void Function() onStartSnip) =>
      FlutterOverlayWindow.overlayListener.listen((event) {
        if (event is Map && event['action'] == 'start_snip') onStartSnip();
      });

  /// Tells the overlay isolate to expand to full screen and show the selection
  /// UI, then waits for the user to draw a region or cancel.
  ///
  /// [screenSize] is in logical pixels and comes from the main isolate's
  /// MediaQuery — the overlay view itself is only 120×120 so it cannot
  /// determine screen dimensions on its own.
  ///
  /// Returns the region data map on success, or null if the user cancelled
  /// or the 30-second timeout elapsed.
  Future<Map<String, dynamic>?> startRegionSelection(Size screenSize) async {
    final completer = Completer<Map<String, dynamic>?>();
    late StreamSubscription<dynamic> sub;
    sub = FlutterOverlayWindow.overlayListener.listen((event) {
      if (event is! Map) return;
      final action = event['action'] as String?;
      if (action == 'region_selected' || action == 'selection_cancelled') {
        sub.cancel();
        completer.complete(
          action == 'region_selected'
              ? Map<String, dynamic>.from(event)
              : null,
        );
      }
    });

    await FlutterOverlayWindow.shareData({
      'action': 'show_selection',
      'screenWidth': screenSize.width.round(),
      'screenHeight': screenSize.height.round(),
    });

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        sub.cancel();
        return null;
      },
    );
  }
}
