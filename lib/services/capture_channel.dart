import 'package:flutter/services.dart';

class CaptureChannel {
  static const _channel = MethodChannel('textsnip/capture');

  /// Requests MediaProjection consent (shows the system dialog) and starts the
  /// foreground capture service. Must be called while the app is in the
  /// foreground. Returns true if consent was granted / already active.
  Future<bool> startCapture() async =>
      await _channel.invokeMethod<bool>('startCapture') ?? false;

  /// Stops the capture service and releases the projection (ends the session).
  Future<void> stopCapture() => _channel.invokeMethod<void>('stopCapture');

  /// Brings the TextSnip activity to the foreground.
  /// Call this after OCR completes so the result screen is visible when the
  /// user triggered the snip from inside another app.
  Future<void> bringToFront() => _channel.invokeMethod<void>('bringToFront');

  /// [left], [top], [width], [height] are in physical pixels. Requires an
  /// active capture session (see [startCapture]).
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
