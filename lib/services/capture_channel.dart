import 'package:flutter/services.dart';

class CaptureChannel {
  static const _channel = MethodChannel('textsnip/capture');

  /// Error code the native side reports when there is no live projection —
  /// either because a session was never started or because it ended (user hit
  /// "Stop" on the notification, the system revoked screen sharing, …).
  static const noProjectionCode = 'NO_PROJECTION';

  void Function()? _onSessionEnded;

  CaptureChannel() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  /// Registers the callback invoked when the native capture session ends for
  /// any reason other than an explicit [stopCapture] from this side — the
  /// notification's Stop action, the system revoking the projection, or a
  /// failure while the service was starting. The native side has already taken
  /// the floating bubble down by the time this fires.
  void setOnSessionEnded(void Function()? callback) => _onSessionEnded = callback;

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'sessionEnded':
        _onSessionEnded?.call();
      default:
        throw MissingPluginException('Unknown method ${call.method}');
    }
  }

  void dispose() {
    _onSessionEnded = null;
    _channel.setMethodCallHandler(null);
  }

  /// Requests MediaProjection consent (shows the system dialog) and starts the
  /// foreground capture service. Must be called while the app is in the
  /// foreground. Completes with true only once the projection is actually live
  /// (or was already active); false if consent was refused or the service
  /// failed to start.
  Future<bool> startCapture() async =>
      await _channel.invokeMethod<bool>('startCapture') ?? false;

  /// Stops the capture service and releases the projection (ends the session).
  Future<void> stopCapture() => _channel.invokeMethod<void>('stopCapture');

  /// Whether a projection is currently live. The service outlives the Flutter
  /// widget tree, so use this to resync UI state on start/resume.
  Future<bool> isCaptureActive() async =>
      await _channel.invokeMethod<bool>('isCaptureActive') ?? false;

  /// Tell the native side the floating bubble was just shown, so it can
  /// re-apply the overlay plugin's notification-channel name (the plugin
  /// resets it on every show).
  Future<void> overlayShown() => _channel.invokeMethod<void>('overlayShown');

  /// Brings the TextSnip activity to the foreground.
  /// Call this after OCR completes so the result screen is visible when the
  /// user triggered the snip from inside another app.
  Future<void> bringToFront() => _channel.invokeMethod<void>('bringToFront');

  /// [left], [top], [width], [height] are in physical pixels. Requires an
  /// active capture session (see [startCapture]). Throws a [PlatformException]
  /// with code [noProjectionCode] when there is no live session.
  Future<String?> captureRegion({
    required int left,
    required int top,
    required int width,
    required int height,
  }) =>
      _channel.invokeMethod<String>('captureRegion', {
        'left': left,
        'top': top,
        'width': width,
        'height': height,
      });
}
