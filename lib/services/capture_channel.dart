import 'package:flutter/services.dart';

class CaptureChannel {
  static const _channel = MethodChannel('textsnip/capture');

  /// Brings the TextSnip activity to the foreground.
  /// Call this after OCR completes so the result screen is visible when the
  /// user triggered the snip from inside another app.
  Future<void> bringToFront() => _channel.invokeMethod<void>('bringToFront');

  /// [left], [top], [width], [height] are in physical pixels.
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
