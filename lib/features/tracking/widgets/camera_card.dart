import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/camera_service.dart';
import '../../../shared/widgets/section_card.dart';

/// Dashcam preview with a lens switch and snapshot counter.
class CameraCard extends StatelessWidget {
  const CameraCard({
    super.key,
    required this.camera,
    required this.snapshotsSent,
    required this.onRetry,
    this.footer,
  });

  /// Optional content under the preview (driver-monitor indicators).
  final Widget? footer;

  final CameraService camera;
  final int snapshotsSent;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: camera,
      builder: (context, _) {
        final controller = camera.controller;
        return SectionCard(
          icon: Icons.videocam_outlined,
          title: 'Dashcam',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CounterChip(count: snapshotsSent),
              if (camera.canSwitch)
                IconButton(
                  tooltip: 'Switch camera',
                  icon: const Icon(Icons.cameraswitch_outlined),
                  onPressed: camera.switchCamera,
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Insets.radiusMd),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: ColoredBox(
                    color: const Color(0xFF0B1220),
                    child: controller != null
                        ? _CoverPreview(controller: controller)
                        : _Placeholder(error: camera.error, onRetry: onRetry),
                  ),
                ),
              ),
              if (footer != null) ...[const Gap(Insets.md), footer!],
            ],
          ),
        );
      },
    );
  }
}

/// Fills the box with the preview without distortion (centre-crop).
///
/// `previewSize` is reported in sensor (landscape) orientation, so width and
/// height are swapped for the portrait-locked UI.
class _CoverPreview extends StatelessWidget {
  const _CoverPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.previewSize;
    if (size == null) return CameraPreview(controller);
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.height,
          height: size.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.error, required this.onRetry});

  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: Colors.white70);
    if (error == null) {
      return const Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white70,
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.videocam_off_outlined,
              color: Colors.white54,
              size: 28,
            ),
            const Gap(Insets.sm),
            Text(error!, style: style, textAlign: TextAlign.center),
            const Gap(Insets.sm),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CounterChip extends StatelessWidget {
  const _CounterChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(right: Insets.xs),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.photo_camera_outlined,
            size: 12,
            color: scheme.onPrimaryContainer,
          ),
          const Gap(4),
          Text(
            '$count',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
