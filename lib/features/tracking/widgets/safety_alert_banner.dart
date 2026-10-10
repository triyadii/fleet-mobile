import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/driver_monitor_service.dart';

/// Pop-up warning shown over the dashboard when the driver monitor fires.
/// Pulses to grab attention; dismissed with "I'm focused".
class SafetyAlertBanner extends StatelessWidget {
  const SafetyAlertBanner({
    super.key,
    required this.alert,
    required this.onDismiss,
  });

  final DriverAlert alert;
  final VoidCallback onDismiss;

  IconData get _icon => switch (alert) {
    DriverAlert.drowsy => Icons.bedtime_rounded,
    DriverAlert.distracted => Icons.visibility_off_rounded,
    DriverAlert.talking => Icons.record_voice_over_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.fromLTRB(
              Insets.lg,
              Insets.md,
              Insets.sm,
              Insets.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.danger,
              borderRadius: BorderRadius.circular(Insets.radiusLg),
              boxShadow: [
                BoxShadow(
                  color: AppColors.danger.withValues(alpha: 0.45),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                      padding: const EdgeInsets.all(Insets.sm),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_icon, color: Colors.white, size: 22),
                    )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scaleXY(begin: 1, end: 1.15, duration: 500.ms),
                const Gap(Insets.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        alert.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const Gap(2),
                      Text(
                        alert.message,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: onDismiss,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: const Text('I\'m focused'),
                ),
              ],
            ),
          ),
        )
        .animate(key: ValueKey(alert))
        .slideY(begin: -0.6, duration: 280.ms, curve: Curves.easeOutBack)
        .fadeIn(duration: 200.ms)
        .shake(hz: 4, rotation: 0.01, delay: 280.ms, duration: 500.ms);
  }
}

/// Compact row of live monitor indicators for the camera card.
class MonitorIndicators extends StatelessWidget {
  const MonitorIndicators({
    super.key,
    required this.monitor,
    required this.active,
  });

  final DriverMonitorService monitor;
  final bool active;

  @override
  Widget build(BuildContext context) {
    if (!DriverMonitorService.isSupported) {
      return const _Chip(
        icon: Icons.info_outline_rounded,
        label: 'AI monitor: mobile only',
        state: null,
      );
    }
    if (!active) {
      return const _Chip(
        icon: Icons.shield_outlined,
        label: 'AI monitor starts with tracking',
        state: null,
      );
    }
    return ValueListenableBuilder<MonitorReading>(
      valueListenable: monitor.reading,
      builder: (context, r, _) => r.problem != null
          ? _Chip(
              icon: Icons.error_outline_rounded,
              // First line only; full stack traces don't fit a chip.
              label: r.problem!.split('\n').first,
              state: false,
            )
          : !r.analyzing
          ? const _Chip(
              icon: Icons.hourglass_top_rounded,
              label: 'AI monitor starting…',
              state: null,
            )
          : Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.sm,
              children: [
                _Chip(
                  icon: Icons.face_rounded,
                  label: r.faceVisible ? 'Face' : 'No face',
                  state: r.faceVisible,
                ),
                _Chip(
                  icon: Icons.remove_red_eye_outlined,
                  label: 'Eyes',
                  state: r.faceVisible ? !r.eyesClosed : null,
                ),
                _Chip(
                  icon: Icons.navigation_outlined,
                  label: 'Focus',
                  state: r.faceVisible ? !r.lookingAway : null,
                ),
                _Chip(
                  icon: Icons.mic_none_rounded,
                  label: 'Quiet',
                  state: r.faceVisible ? !r.talking : null,
                ),
              ],
            ),
    );
  }
}

/// Status pill: green = OK, red = warning, grey = unknown.
class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.state});

  final IconData icon;
  final String label;
  final bool? state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (state) {
      true => AppColors.success,
      false => AppColors.danger,
      null => scheme.onSurfaceVariant,
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const Gap(4),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
