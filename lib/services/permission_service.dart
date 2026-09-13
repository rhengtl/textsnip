import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';

/// Outcome of a permission request that may need the user to finish the job
/// in system Settings rather than in an in-app dialog.
enum PermissionRequestOutcome {
  granted,

  /// The user refused the in-app dialog; asking again may still show it.
  denied,

  /// No dialog can be shown (permanently denied, or the platform has no
  /// runtime prompt for it). System Settings was opened for the user; the
  /// caller should re-check on resume.
  openedSettings,
}

class PermissionService {
  Future<bool> hasOverlayPermission() =>
      FlutterOverlayWindow.isPermissionGranted();

  Future<bool> requestOverlayPermission() async =>
      await FlutterOverlayWindow.requestPermission() ?? false;

  /// True when TextSnip's foreground-service notifications can be shown. On
  /// Android 13+ this is the POST_NOTIFICATIONS runtime permission; on older
  /// versions it reflects the app-level "Show notifications" toggle.
  Future<bool> hasNotificationPermission() =>
      Permission.notification.isGranted;

  Future<PermissionRequestOutcome> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    if (status.isGranted) return PermissionRequestOutcome.granted;

    // Android 13+: after the user refuses twice the system stops showing the
    // dialog and request() returns permanentlyDenied immediately.
    // Android < 13: there is no runtime dialog at all — request() just
    // reports the app-level toggle, so if it's off nothing was shown either.
    // In both cases the only way forward is the app's Settings page.
    if (status.isPermanentlyDenied || !await _canShowNotificationDialog()) {
      await openAppSettings();
      return PermissionRequestOutcome.openedSettings;
    }
    return PermissionRequestOutcome.denied;
  }

  /// Whether the OS can still show the POST_NOTIFICATIONS dialog. Pre-13
  /// devices never can (no runtime permission), which permission_handler
  /// reports as "no rationale needed" alongside a denied status.
  Future<bool> _canShowNotificationDialog() =>
      Permission.notification.shouldShowRequestRationale;

  Future<bool> allGranted() async =>
      await hasOverlayPermission() && await hasNotificationPermission();
}
