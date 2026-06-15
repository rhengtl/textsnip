import 'package:flutter/services.dart';

class CaptureChannel {
  static const _channel = MethodChannel('textsnip/capture');

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
