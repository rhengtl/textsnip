import 'dart:ui' show IsolateNameServer;
import 'package:flutter/material.dart';
import '../../services/overlay_ports.dart';
import '../../theme/app_theme.dart';

/// Runs inside the flutter_overlay_window isolate — no access to main-app state
/// or [Theme], so it styles itself from the shared [AppColors] constants. On tap
/// it sends a `start_snip` message to the main isolate over an IsolateNameServer
/// port. Native drag (enableDrag: true) handles repositioning.
class FloatingBubble extends StatelessWidget {
  const FloatingBubble({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: () {
          final port = IsolateNameServer.lookupPortByName(kMainIsolatePort);
          port?.send({'action': 'start_snip'});
        },
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.9),
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.brandCyan.withValues(alpha: 0.45),
                blurRadius: 16,
                spreadRadius: 1,
              ),
              const BoxShadow(
                color: Colors.black38,
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(
            Icons.document_scanner_outlined,
            color: Colors.white,
            size: 28,
          ),
        ),
      ),
    );
  }
}
