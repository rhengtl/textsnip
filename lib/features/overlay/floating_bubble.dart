import 'dart:ui' show IsolateNameServer;
import 'package:flutter/material.dart';
import '../../services/overlay_ports.dart';

/// Runs inside the flutter_overlay_window isolate — no access to main-app state.
/// On tap it sends a `start_snip` message to the main isolate over an
/// IsolateNameServer port. Native drag (enableDrag: true) handles repositioning.
class FloatingBubble extends StatelessWidget {
  const FloatingBubble({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final port = IsolateNameServer.lookupPortByName(kMainIsolatePort);
        port?.send({'action': 'start_snip'});
      },
      child: Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(
          color: Colors.indigo,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
          ],
        ),
        child: const Icon(Icons.crop, color: Colors.white, size: 28),
      ),
    );
  }
}
