import 'dart:async';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'overlay_ports.dart';

class OverlayService {
  // Receives messages from the overlay isolate (tap, region selected/cancelled)
  // via an IsolateNameServer-registered port — see overlay_ports.dart for why.
  ReceivePort? _receivePort;
  void Function()? _onStartSnip;
  Completer<Map<String, dynamic>?>? _regionCompleter;

  // Last known bubble position, so re-showing keeps where the user dragged it.
  OverlayPosition? _lastPosition;

  // Bounds most recently sent to the overlay isolate.
  BubbleBounds? _bounds;

  /// Begin routing overlay→main messages. Call once (e.g. in initState).
  void start(void Function() onStartSnip) {
    _onStartSnip = onStartSnip;
    if (_receivePort != null) return;
    final port = ReceivePort();
    _receivePort = port;
    IsolateNameServer.removePortNameMapping(kMainIsolatePort);
    IsolateNameServer.registerPortWithName(port.sendPort, kMainIsolatePort);
    port.listen(_handleMessage);
  }

  void dispose() {
    IsolateNameServer.removePortNameMapping(kMainIsolatePort);
    _receivePort?.close();
    _receivePort = null;
  }

  void _handleMessage(dynamic message) {
    if (message is! Map) return;
    switch (message['action']) {
      case 'start_snip':
        _onStartSnip?.call();
      case 'region_selected':
        _regionCompleter?.complete(Map<String, dynamic>.from(message));
        _regionCompleter = null;
      case 'selection_cancelled':
        _regionCompleter?.complete(null);
        _regionCompleter = null;
    }
  }

  /// Show the floating bubble, keeping it inside [bounds].
  ///
  /// The window uses a top-left gravity so its (x, y) are plain screen
  /// offsets in logical px; that is what makes the on-screen clamping in the
  /// overlay isolate gravity-independent. A remembered position from an
  /// earlier show is restored (re-clamped in case the screen changed);
  /// otherwise the bubble starts at the right edge, vertically centred.
  ///
  /// [devicePixelRatio] is needed because the plugin sizes the *initial*
  /// window in raw pixels (only its resizeOverlay() speaks logical px).
  Future<void> showBubble(BubbleBounds bounds, double devicePixelRatio) async {
    _bounds = bounds;
    final windowPx = (kBubbleWindowSize * devicePixelRatio).round();
    final remembered = _lastPosition;
    final start = remembered == null
        ? OverlayPosition(bounds.maxX, (bounds.minY + bounds.maxY) / 2)
        : OverlayPosition(
            bounds.clampX(remembered.x), bounds.clampY(remembered.y));

    await FlutterOverlayWindow.showOverlay(
      enableDrag: true,
      overlayTitle: 'TextSnip active',
      overlayContent: 'Tap the bubble to capture text',
      flag: OverlayFlag.defaultFlag,
      visibility: NotificationVisibility.visibilityPublic,
      // none = stay exactly where the user drops it (no edge snapping).
      positionGravity: PositionGravity.none,
      alignment: OverlayAlignment.topLeft,
      height: windowPx,
      width: windowPx,
      startPosition: start,
    );
    // The overlay engine is reused across hide/show cycles, so its widget state
    // can still be in selection mode from a previous snip. Tell it to return to
    // bubble mode (and bubble size), and give it the rectangle it may occupy.
    // Queued on the ReceivePort if the engine is still resuming.
    _sendToOverlay({'action': 'show_bubble', 'bounds': bounds.toMap()});
  }

  /// Push new [bounds] to a bubble that is already showing (screen rotated,
  /// system bars changed). No-op if nothing changed.
  void updateBubbleBounds(BubbleBounds bounds) {
    final current = _bounds;
    if (current != null &&
        current.minX == bounds.minX &&
        current.minY == bounds.minY &&
        current.maxX == bounds.maxX &&
        current.maxY == bounds.maxY) {
      return;
    }
    _bounds = bounds;
    _sendToOverlay({'action': 'set_bounds', 'bounds': bounds.toMap()});
  }

  void _sendToOverlay(Map<String, Object?> message) {
    IsolateNameServer.lookupPortByName(kOverlayIsolatePort)?.send(message);
  }

  /// Close the bubble. When [savePosition] is true (the default), remember the
  /// current position first so the next [showBubble] restores it. Pass false
  /// when the overlay is not in bubble mode (e.g. mid-snip, full-screen).
  ///
  /// Safe to call when the overlay is already gone (e.g. the native side took
  /// it down when the capture session ended).
  Future<void> hideBubble({bool savePosition = true}) async {
    // flutter_overlay_window's closeOverlay() never completes its result when
    // the overlay service isn't running, so the await would hang forever.
    if (!await isActive) return;
    if (savePosition) await _rememberPosition();
    await FlutterOverlayWindow.closeOverlay();
  }

  /// Abort an in-flight [startRegionSelection] as if the user had cancelled.
  /// No-op when nothing is pending.
  void cancelRegionSelection() {
    _regionCompleter?.complete(null);
    _regionCompleter = null;
  }

  Future<void> _rememberPosition() async {
    try {
      _lastPosition = await FlutterOverlayWindow.getOverlayPosition();
    } catch (_) {
      // Best-effort; keep the previous value on failure.
    }
  }

  Future<bool> get isActive => FlutterOverlayWindow.isActive();

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
    // Capture the bubble position now, before it morphs into the full-screen
    // selector, so it can be restored after the snip completes.
    await _rememberPosition();

    final completer = Completer<Map<String, dynamic>?>();
    _regionCompleter = completer;

    final overlayPort = IsolateNameServer.lookupPortByName(kOverlayIsolatePort);
    overlayPort?.send({
      'action': 'show_selection',
      'screenWidth': screenSize.width.round(),
      'screenHeight': screenSize.height.round(),
    });

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _regionCompleter = null;
        return null;
      },
    );
  }
}
