/// FleetTrack Driver — live GPS + dashcam telemetry client for the
/// Fleet Tracking API (see `/api/documentation` on the backend).
///
/// Project layout:
/// * `core/`     configuration, theme, networking, storage, utilities
/// * `data/`     models and repositories (one per API resource)
/// * `services/` device capabilities: location, camera, background service
/// * `features/` screens grouped by feature, each with its own widgets
/// * `shared/`   reusable widgets
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/alert_notifier.dart';
import 'services/background_tracking_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Draw behind the system bars; every screen pads itself with SafeArea so
  // nothing is hidden by the status bar or the Android navigation buttons.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // The dashcam preview and capture are portrait-oriented.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  await BackgroundTrackingService.configure();
  await AlertNotifier.init();
  runApp(const FleetApp());
}
