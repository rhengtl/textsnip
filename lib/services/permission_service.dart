import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  Future<bool> hasOverlayPermission() =>
      FlutterOverlayWindow.isPermissionGranted();

  Future<bool> requestOverlayPermission() async =>
      await FlutterOverlayWindow.requestPermission() ?? false;

  Future<bool> hasNotificationPermission() =>
      Permission.notification.isGranted;

  Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  Future<bool> allGranted() async =>
      await hasOverlayPermission() && await hasNotificationPermission();
}
