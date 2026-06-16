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

  Future<void> showBubble() async {
    await FlutterOverlayWindow.showOverlay(
      enableDrag: true,
      overlayTitle: 'TextSnip active',
      overlayContent: 'Tap the bubble to capture text',
      flag: OverlayFlag.defaultFlag,
      visibility: NotificationVisibility.visibilityPublic,
      // none = stay exactly where the user drops it (no edge snapping).
      positionGravity: PositionGravity.none,
      alignment: OverlayAlignment.centerRight,
      height: 120,
      width: 120,
      startPosition: _lastPosition,
    );
    // The overlay engine is reused across hide/show cycles, so its widget state
    // can still be in selection mode from a previous snip. Tell it to return to
    // bubble mode (and 120×120 size). Queued on the ReceivePort if the engine
    // is still resuming.
    final overlayPort = IsolateNameServer.lookupPortByName(kOverlayIsolatePort);
    overlayPort?.send({'action': 'show_bubble'});
  }

  /// Close the bubble. When [savePosition] is true (the default), remember the
  /// current position first so the next [showBubble] restores it. Pass false
  /// when the overlay is not in bubble mode (e.g. mid-snip, full-screen).
  Future<void> hideBubble({bool savePosition = true}) async {
    if (savePosition) await _rememberPosition();
    await FlutterOverlayWindow.closeOverlay();
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
