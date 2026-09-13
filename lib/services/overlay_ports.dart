/// IsolateNameServer port names used for communication between the main
/// isolate and the flutter_overlay_window isolate.
///
/// The package's own shareData/overlayListener (a BasicMessageChannel) does not
/// reliably deliver overlay→main messages, so — like the package's official
/// example — we use SendPort/ReceivePort registered with IsolateNameServer,
/// which is process-global and works across both isolates.
const String kMainIsolatePort = 'textsnip_main';
const String kOverlayIsolatePort = 'textsnip_overlay';

/// How long to let the window manager finish animating an overlay resize
/// before drawing non-uniform content into it. Some ROMs (ColorOS, for one)
/// scale the window surface from its old bounds to the new ones over roughly
/// 400 ms; anything drawn during that time is scaled with it. Stock Android
/// applies the new bounds instantly, where this is merely a short delay.
const Duration kWindowResizeSettle = Duration(milliseconds: 450);

/// Size (logical px) of the overlay window while it is in bubble mode. The
/// window is square and the 60dp bubble is centred inside it, so the extra
/// margin is the bubble's glow/shadow and a comfortable touch target.
const int kBubbleWindowSize = 120;

/// The rectangle (logical px, top-left origin) the bubble window's top-left
/// corner may occupy so the whole bubble stays on the visible screen, outside
/// the status and navigation bars. Computed in the main isolate (the only one
/// that knows the real screen metrics) and shipped to the overlay isolate.
class BubbleBounds {
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;

  const BubbleBounds({
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
  });

  /// [screenWidth]/[screenHeight] and the four insets are in logical px.
  factory BubbleBounds.forScreen({
    required double screenWidth,
    required double screenHeight,
    double insetLeft = 0,
    double insetTop = 0,
    double insetRight = 0,
    double insetBottom = 0,
  }) {
    final size = kBubbleWindowSize.toDouble();
    final minX = insetLeft;
    final minY = insetTop;
    // Never let max fall below min on tiny/odd screens.
    final maxX = (screenWidth - insetRight - size).clamp(minX, double.infinity);
    final maxY = (screenHeight - insetBottom - size).clamp(minY, double.infinity);
    return BubbleBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  double clampX(double x) => x.clamp(minX, maxX);
  double clampY(double y) => y.clamp(minY, maxY);

  Map<String, double> toMap() =>
      {'minX': minX, 'minY': minY, 'maxX': maxX, 'maxY': maxY};

  static BubbleBounds? fromMap(Object? map) {
    if (map is! Map) return null;
    double? d(String k) => (map[k] as num?)?.toDouble();
    final minX = d('minX'), minY = d('minY'), maxX = d('maxX'), maxY = d('maxY');
    if (minX == null || minY == null || maxX == null || maxY == null) return null;
    return BubbleBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }
}
