import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';

import '../../core/config/app_config.dart';
import '../../core/storage/session_storage.dart';
import '../../core/theme/app_theme.dart';
import '../auth/login_screen.dart';
import 'tracking_controller.dart';
import 'widgets/camera_card.dart';
import 'widgets/live_map_card.dart';
import 'widgets/safety_alert_banner.dart';
import 'widgets/status_card.dart';

/// Main dashboard: status, live map, dashcam and the start/stop action.
class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key, required this.session});

  final StoredSession session;

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with WidgetsBindingObserver {
  late final TrackingController _c = TrackingController(widget.session);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c.addListener(_onControllerChanged);
    _c.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.removeListener(_onControllerChanged);
    _c.dispose();
    super.dispose();
  }

  /// Releases the camera in the background and re-acquires it on resume —
  /// without this the preview freezes / throws after returning to the app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _c.setForeground(true);
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _c.setForeground(false);
      case AppLifecycleState.detached:
        break;
    }
  }

  void _onControllerChanged() {
    if (_c.sessionExpired) {
      _c.removeListener(_onControllerChanged);
      SessionStorage.clear().then((_) => _goToLogin());
    }
  }

  void _goToLogin() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _toggleTracking() async {
    if (_c.isTracking) {
      _c.stop();
      return;
    }
    final problem = await _c.start();
    if (problem != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('Live tracking will stop on this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              backgroundColor: AppColors.danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _c.logout();
    _goToLogin();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          titleSpacing: Insets.lg,
          title: const Text(AppConfig.appName),
          actions: [
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout_rounded),
              onPressed: _confirmLogout,
            ),
            const Gap(Insets.xs),
          ],
        ),
        // Body never extends under the bottom bar; the bar itself handles
        // the Android navigation-bar inset.
        body: SafeArea(
          top: false,
          bottom: false,
          child: Stack(
            children: [
              RefreshIndicator(
                onRefresh: _c.refreshHistory,
                child: LayoutBuilder(
                  builder: (context, constraints) => _buildContent(constraints),
                ),
              ),
              // Driver-safety pop-up, pinned above the scrolling content.
              if (_c.activeAlert != null)
                Positioned(
                  top: Insets.sm,
                  left: Insets.lg,
                  right: Insets.lg,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: Insets.maxContentWidth,
                      ),
                      child: SafetyAlertBanner(
                        alert: _c.activeAlert!,
                        onDismiss: _c.dismissAlert,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        bottomNavigationBar: _ActionBar(
          tracking: _c.isTracking,
          busy: _c.isStarting,
          onPressed: _toggleTracking,
        ),
      ),
    );
  }

  Widget _buildContent(BoxConstraints constraints) {
    // Two columns on tablets / landscape, single column on phones.
    final wide = constraints.maxWidth >= 720;
    final map = LiveMapCard(
      route: _c.route,
      // Prefer the phone's live GPS; fall back to the last server point.
      current: _c.devicePosition ?? _c.lastPoint,
      loading: _c.isLoadingHistory,
      onRefresh: _c.refreshHistory,
    );
    final camera = CameraCard(
      camera: _c.camera,
      snapshotsSent: _c.snapshotsSent,
      footer: MonitorIndicators(monitor: _c.monitor, active: _c.isTracking),
      onRetry: () => _c.camera.initialize(),
    );

    final children = <Widget>[
      StatusCard(controller: _c),
      if (_c.error != null) _ErrorBanner(message: _c.error!),
      if (wide)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: map),
            const Gap(Insets.lg),
            Expanded(child: camera),
          ],
        )
      else ...[
        map,
        camera,
      ],
    ];

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: _horizontalPadding(constraints.maxWidth, wide),
        vertical: Insets.lg,
      ),
      itemCount: children.length,
      separatorBuilder: (_, _) => const Gap(Insets.lg),
      itemBuilder: (_, i) => children[i]
          .animate()
          .fadeIn(duration: 300.ms, delay: (40 * i).ms)
          .slideY(begin: 0.04, curve: Curves.easeOut),
    );
  }

  /// Centres content with a max width; otherwise a 16dp gutter.
  double _horizontalPadding(double width, bool wide) {
    final max = wide ? 1100.0 : Insets.maxContentWidth;
    return width > max ? (width - max) / 2 : Insets.lg;
  }
}

/// Sticky bottom action. Wrapped in [SafeArea] so it always sits **above**
/// the Android 3-button / gesture navigation bar instead of underneath it.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.tracking,
    required this.busy,
    required this.onPressed,
  });

  final bool tracking;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(
          Insets.lg,
          Insets.md,
          Insets.lg,
          Insets.md,
        ),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: FilledButton.icon(
              onPressed: busy ? null : onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: tracking ? AppColors.danger : AppColors.brand,
                foregroundColor: Colors.white,
              ),
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      tracking ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    ),
              label: Text(tracking ? 'Stop tracking' : 'Start tracking'),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Insets.radiusMd),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppColors.warning,
          ),
          const Gap(Insets.sm),
          Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
