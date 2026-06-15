import 'dart:async';
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
}
