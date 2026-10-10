import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/telemetry_point.dart';
import '../../../shared/widgets/section_card.dart';

/// OpenStreetMap view with the route polyline and current-position marker.
///
/// The map auto-follows new points until the user pans it; the "recenter"
/// button re-enables following.
class LiveMapCard extends StatefulWidget {
  const LiveMapCard({
    super.key,
    required this.route,
    required this.current,
    required this.loading,
    required this.onRefresh,
  });

  final List<TelemetryPoint> route;
  final TelemetryPoint? current;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  State<LiveMapCard> createState() => _LiveMapCardState();
}

class _LiveMapCardState extends State<LiveMapCard> {
  final _map = MapController();
  bool _ready = false;
  bool _follow = true;

  static const _zoom = 16.0;

  LatLng? get _currentLatLng {
    final p = widget.current;
    return p == null ? null : LatLng(p.lat, p.lng);
  }

  @override
  void didUpdateWidget(covariant LiveMapCard old) {
    super.didUpdateWidget(old);
    final target = _currentLatLng;
    if (_ready && _follow && target != null && widget.current != old.current) {
      _map.move(target, _map.camera.zoom);
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _recenter() {
    final target = _currentLatLng;
    setState(() => _follow = true);
    if (target != null) _map.move(target, _zoom);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = _currentLatLng;

    return SectionCard(
      icon: Icons.map_outlined,
      title: 'Live route',
      trailing: widget.loading
          ? const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : IconButton(
              tooltip: 'Reload history',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: widget.onRefresh,
            ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Insets.radiusMd),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: Stack(
            children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter:
                      current ??
                      const LatLng(
                        AppConfig.fallbackLat,
                        AppConfig.fallbackLng,
                      ),
                  initialZoom: _zoom,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                  onMapReady: () => _ready = true,
                  onPositionChanged: (_, hasGesture) {
                    if (hasGesture && _follow) setState(() => _follow = false);
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: AppConfig.userAgentPackageName,
                  ),
                  if (widget.route.length > 1)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: [
                            for (final p in widget.route) LatLng(p.lat, p.lng),
                          ],
                          color: AppColors.brand,
                          strokeWidth: 4,
                          borderColor: Colors.white,
                          borderStrokeWidth: 1.5,
                        ),
                      ],
                    ),
                  if (current != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: current,
                          width: 28,
                          height: 28,
                          child: const _PositionDot(),
                        ),
                      ],
                    ),
                ],
              ),
              Positioned(
                right: Insets.sm,
                bottom: Insets.sm,
                child: AnimatedOpacity(
                  opacity: _follow ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: _follow,
                    child: FloatingActionButton.small(
                      heroTag: 'recenter',
                      tooltip: 'Recenter',
                      backgroundColor: scheme.surface,
                      foregroundColor: scheme.primary,
                      elevation: 2,
                      onPressed: _recenter,
                      child: const Icon(Icons.my_location_rounded, size: 18),
                    ),
                  ),
                ),
              ),
              // Attribution required by the OSM tile usage policy.
              Positioned(
                left: Insets.sm,
                bottom: Insets.xs,
                child: Text(
                  '© OpenStreetMap',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    color: Colors.black54,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "You are here" dot with a soft halo.
class _PositionDot extends StatelessWidget {
  const _PositionDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.brand.withValues(alpha: 0.2),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.brand,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
      ),
    );
  }
}
