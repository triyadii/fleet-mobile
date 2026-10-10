import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';

import '../../../core/theme/app_theme.dart';
import '../tracking_controller.dart';

/// Hero card: live/idle status, vehicle and three compact stats.
class StatusCard extends StatelessWidget {
  const StatusCard({super.key, required this.controller});

  final TrackingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;
    final live = c.isTracking;

    return Container(
      padding: const EdgeInsets.all(Insets.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Insets.radiusLg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: live
              ? const [AppColors.brandDeep, AppColors.brand]
              : const [Color(0xFF1E293B), Color(0xFF334155)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _LiveBadge(live: live),
              const Spacer(),
              Icon(
                Icons.local_shipping_rounded,
                size: 18,
                color: Colors.white.withValues(alpha: 0.8),
              ),
              const Gap(Insets.xs),
              Flexible(
                child: Text(
                  c.session.vehiclePlate ?? 'Vehicle #${c.vehicleId ?? '-'}',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const Gap(Insets.lg),
          Text(
            'Hi, ${c.session.displayName ?? 'Driver'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
          ),
          const Gap(Insets.xs),
          Text(
            live
                ? 'Your location is shared every few seconds.'
                : 'Tap “Start tracking” when you begin your trip.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          const Gap(Insets.lg),
          Row(
            children: [
              _Stat(
                icon: Icons.speed_rounded,
                label: 'Speed',
                value:
                    '${c.lastPoint?.speedKmh?.toStringAsFixed(0) ?? '0'} km/h',
              ),
              _Stat(
                icon: Icons.schedule_rounded,
                label: 'Last sync',
                value: _formatTime(c.lastSyncAt),
              ),
              _Stat(
                icon: Icons.cloud_upload_outlined,
                label: 'Sent',
                value: '${c.samplesSent}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime? t) {
    if (t == null) return '--:--';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}

/// Pill with a pulsing dot while live.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.live});

  final bool live;

  @override
  Widget build(BuildContext context) {
    final color = live ? const Color(0xFF4ADE80) : const Color(0xFF94A3B8);
    Widget dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (live) {
      dot = dot
          .animate(onPlay: (a) => a.repeat(reverse: true))
          .fade(begin: 1, end: 0.35, duration: 900.ms);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          dot,
          const Gap(6),
          Text(
            live ? 'LIVE' : 'OFFLINE',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.7)),
              const Gap(4),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const Gap(2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
