import 'package:flutter/material.dart';

import 'core/config/app_config.dart';
import 'core/storage/session_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/tracking/tracking_screen.dart';
import 'shared/widgets/app_logo.dart';

/// Root widget: theming + session-based start route.
class FleetApp extends StatelessWidget {
  const FleetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      // Clamp extreme system font scaling so the layout stays intact.
      builder: (context, child) =>
          MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: child!),
      home: const _SessionGate(),
    );
  }
}

/// Restores a persisted session so drivers don't re-login on every launch.
class _SessionGate extends StatelessWidget {
  const _SessionGate();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StoredSession?>(
      future: SessionStorage.load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: AppLogo(size: 72)));
        }
        final session = snapshot.data;
        return session == null
            ? const LoginScreen()
            : TrackingScreen(session: session);
      },
    );
  }
}
