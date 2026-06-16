import 'dart:ui' show IsolateNameServer;
import 'package:flutter/material.dart';
import '../../services/overlay_ports.dart';
import '../../theme/app_theme.dart';

class SelectionOverlay extends StatefulWidget {
  const SelectionOverlay({super.key});

  @override
  State<SelectionOverlay> createState() => _SelectionOverlayState();
}

class _SelectionOverlayState extends State<SelectionOverlay> {
  Offset? _start;
  Offset? _current;

  Rect? get _rect {
    if (_start == null || _current == null) return null;
    return Rect.fromPoints(_start!, _current!);
  }

  @override
  Widget build(BuildContext context) {
    final rect = _rect;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) => setState(() {
        _start = d.globalPosition;
        _current = d.globalPosition;
      }),
      onPanUpdate: (d) => setState(() => _current = d.globalPosition),
      onPanEnd: (_) => _confirmSelection(),
      onTap: _cancel,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _SelectionPainter(
                rect: rect,
                dim: Colors.black.withValues(alpha: 0.55),
                accent: AppColors.brandCyan,
              ),
            ),
          ),
          // Instruction pill.
          Positioned(
            top: 40,
            left: 0,
            right: 0,
            child: Center(child: _Pill(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.crop_free, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  _PillText('Drag to select  •  tap to cancel'),
                ],
              ),
            )),
          ),
          // Live dimension badge near the selection.
          if (rect != null && rect.width >= 8 && rect.height >= 8)
            Positioned(
              left: rect.left.clamp(8.0, double.infinity),
              top: (rect.top - 32).clamp(8.0, double.infinity),
              child: _Pill(
                color: AppColors.brandCyan,
                child: _PillText(
                  '${rect.width.round()} × ${rect.height.round()}',
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _confirmSelection() {
    final rect = _rect;
    if (rect == null || rect.width < 8 || rect.height < 8) {
      _cancel();
      return;
    }
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final port = IsolateNameServer.lookupPortByName(kMainIsolatePort);
    port?.send({
      'action': 'region_selected',
      'left': rect.left,
      'top': rect.top,
      'width': rect.width,
      'height': rect.height,
      'dpr': dpr,
    });
  }

  void _cancel() {
    final port = IsolateNameServer.lookupPortByName(kMainIsolatePort);
    port?.send({'action': 'selection_cancelled'});
  }
}

/// Paints the dimming scrim with the selection rect "cut out", plus the rect
/// border and corner handles.
class _SelectionPainter extends CustomPainter {
  final Rect? rect;
  final Color dim;
  final Color accent;

  _SelectionPainter({
    required this.rect,
    required this.dim,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final dimPaint = Paint()..color = dim;

    final r = rect;
    if (r == null || r.width < 1 || r.height < 1) {
      canvas.drawRect(full, dimPaint);
      return;
    }

    // Dim everything except the selection (even-odd leaves the rect clear).
    final scrim = Path()
      ..addRect(full)
      ..addRect(r)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(scrim, dimPaint);

    // Selection border.
    final border = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(4)),
      border,
    );

    // Corner handles.
    final handle = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const len = 18.0;
    void corner(Offset c, double dx, double dy) {
      canvas.drawLine(c, c + Offset(dx, 0), handle);
      canvas.drawLine(c, c + Offset(0, dy), handle);
    }

    corner(r.topLeft, len, len);
    corner(r.topRight, -len, len);
    corner(r.bottomLeft, len, -len);
    corner(r.bottomRight, -len, -len);
  }

  @override
  bool shouldRepaint(covariant _SelectionPainter old) =>
      old.rect != rect || old.dim != dim || old.accent != accent;
}

class _Pill extends StatelessWidget {
  final Widget child;
  final Color? color;
  const _Pill({required this.child, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color ?? Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}

class _PillText extends StatelessWidget {
  final String text;
  const _PillText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        decoration: TextDecoration.none,
      ),
    );
  }
}
