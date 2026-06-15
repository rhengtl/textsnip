import 'package:flutter/material.dart';
import 'app.dart';
import 'features/overlay/floating_bubble.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TextSnipApp());
}

// Separate isolate entry point for flutter_overlay_window.
// Must be top-level and annotated so it is not tree-shaken.
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Material(color: Colors.transparent, child: FloatingBubble()),
  ));
}
