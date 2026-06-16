import 'dart:ui' show IsolateNameServer;
import 'package:flutter/material.dart';
import '../../services/overlay_ports.dart';

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
          ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
          if (_rect != null)
            Positioned.fromRect(
              rect: _rect!,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.cyanAccent, width: 2),
                  color: Colors.cyanAccent.withValues(alpha: 0.1),
                ),
              ),
            ),
          Positioned(
            top: 48,
            left: 0,
            right: 0,
            child: Text(
              'Drag to select  •  tap to cancel',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13,
                decoration: TextDecoration.none,
                fontWeight: FontWeight.w500,
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
