import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/entry.dart';
import '../state/app_state.dart';
import '../widgets/entry_image.dart';
import '../widgets/trip_records_panel.dart';
import 'entry_form.dart';
import 'new_trip_sheet.dart';
import 'trip_detail_screen.dart';

/// View 1: a single map with custom-glyph markers pinned at each located entry.
class MapScreen extends StatefulWidget {
  /// Overridable so widget tests can supply an offline provider instead of
  /// hitting the real OSM tile servers.
  final TileProvider? tileProvider;

  const MapScreen({super.key, this.tileProvider});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final MapController _map = MapController();

  /// Mouse hover position over the map (desktop/web), for the "click to add"
  /// hint shown once zoomed in enough. A notifier so moving the mouse rebuilds
  /// only the hint, not the whole map.
  final ValueNotifier<Offset?> _hover = ValueNotifier(null);

  /// Drives the short zoom-in animation on a map tap.
  AnimationController? _moveController;

  @override
  void dispose() {
    _moveController?.dispose();
    _hover.dispose();
    super.dispose();
  }

  /// Smoothly zooms/pans to [dest] at [destZoom] by interpolating the camera —
  /// flutter_map's own [MapController.move] is instant.
  void _animatedMove(LatLng dest, double destZoom) {
    final startCenter = _map.camera.center;
    final startZoom = _map.camera.zoom;
    final latTween =
        Tween(begin: startCenter.latitude, end: dest.latitude);
    final lngTween =
        Tween(begin: startCenter.longitude, end: dest.longitude);
    final zoomTween = Tween(begin: startZoom, end: destZoom);

    _moveController?.dispose();
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _moveController = controller;
    final curve = CurvedAnimation(parent: controller, curve: Curves.easeOutCubic);

    controller.addListener(() {
      _map.move(
        LatLng(latTween.evaluate(curve), lngTween.evaluate(curve)),
        zoomTween.evaluate(curve),
      );
    });
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        controller.dispose();
        if (_moveController == controller) _moveController = null;
      }
    });
    controller.forward();
  }

  /// The entry whose preview popup is shown, if any.
  Entry? _selected;

  /// The point where a new-entry form popup is open, if any. Mutually exclusive
  /// with [_selected].
  LatLng? _addingPoint;

  /// The trip whose records fill the right-hand panel (wide layout only), set by
  /// tapping its cluster bubble.
  String? _panelTripId;

  /// Below this width there's no room for a side panel; a trip tap navigates.
  static const double _panelBreakpoint = 720;

  /// Current map zoom, tracked so markers can collapse into per-trip clusters
  /// when zoomed out. Below [_recordZoom] shows trips; at/above it, records.
  double _zoom = 5;
  static const double _recordZoom = 9;

  /// Street-level zoom. Below this, a map tap zooms in rather than placing a
  /// record — so records are only added when the location is precise.
  static const double _addZoom = 15;

  bool get _collapsed => _zoom < _recordZoom;

  /// Tapping empty map space opens the new-entry form as a popup anchored at
  /// that point (the location is pre-filled into the form).
  Future<void> _startAddAt(LatLng point) async {
    // Every entry needs a trip; make one first if there are none.
    if (context.read<AppState>().trips.isEmpty) {
      final created = await NewTripSheet.show(context);
      if (!created || !mounted) return;
    }
    if (!mounted) return;
    setState(() {
      _selected = null;
      _addingPoint = point;
    });
  }

  void _onSaved() {
    setState(() => _addingPoint = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('记录已保存')),
    );
  }

  /// Tapping a trip cluster zooms the map to fit that trip's records, which
  /// crosses [_recordZoom] and expands them back into individual bubbles.
  void _fitTrip(List<LatLng> points) {
    setState(() {
      _selected = null;
      _addingPoint = null;
    });
    if (points.length == 1) {
      _map.move(points.first, _recordZoom + 2);
    } else {
      _map.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(60),
        ),
      );
      // Guarantee we land in the records view even for a tightly-packed trip.
      if (_map.camera.zoom < _recordZoom) {
        _map.move(_map.camera.center, _recordZoom + 1);
      }
    }
  }

  /// Tapping a trip cluster: on a wide window it opens the trip's records in a
  /// right-hand panel (and fits the trip on the map); on a phone, where there's
  /// no room for a panel, it opens the trip's records full-screen.
  void _openTripPanel(String tripId, List<LatLng> points) {
    final wide = MediaQuery.sizeOf(context).width >= _panelBreakpoint;
    if (wide) {
      setState(() {
        _selected = null;
        _addingPoint = null;
        _panelTripId = tripId;
      });
      _fitTrip(points);
    } else {
      final appState = context.read<AppState>();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider.value(
            value: appState,
            child: TripDetailScreen(tripId: tripId),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final entries = appState.locatedEntries;

    // A panel pointing at a since-deleted trip falls back to closed.
    if (_panelTripId != null &&
        !appState.trips.any((t) => t.id == _panelTripId)) {
      _panelTripId = null;
    }

    // If the selected entry was deleted/filtered out, drop the popup.
    if (_selected != null && !entries.any((e) => e.id == _selected!.id)) {
      _selected = null;
    }

    final center = entries.isNotEmpty
        ? entries.first.location!.latLng
        : const LatLng(35.0, 135.76);

    // One polyline per trip, joining that trip's located entries in time order.
    final byTrip = <String, List<Entry>>{};
    for (final e in entries) {
      (byTrip[e.tripId] ??= []).add(e);
    }
    final polylines = <Polyline>[];
    byTrip.forEach((tripId, list) {
      if (list.length < 2) return;
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      polylines.add(Polyline(
        points: [for (final e in list) e.location!.latLng],
        color: _tripColor(tripId),
        strokeWidth: 3,
      ));
    });

    final map = LayoutBuilder(
      builder: (context, constraints) {
        return MouseRegion(
          onHover: (e) {
            _hover.value = (_zoom >= _addZoom &&
                    _selected == null &&
                    _addingPoint == null)
                ? e.localPosition
                : null;
          },
          onExit: (_) => _hover.value = null,
          child: Stack(
            children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 5,
                onTap: (_, point) {
                  // An open popup (preview or add form) gets dismissed first.
                  if (_selected != null || _addingPoint != null) {
                    setState(() {
                      _selected = null;
                      _addingPoint = null;
                    });
                  } else if (_zoom < _addZoom) {
                    // Not zoomed in enough to place a record precisely — zoom
                    // (animated) toward the tapped point instead of adding.
                    _animatedMove(
                        point, (_zoom + 3).clamp(0, _addZoom).toDouble());
                  } else {
                    _startAddAt(point);
                  }
                },
                // Track zoom (to collapse/expand markers) and keep any open
                // popup pinned to its point while the map moves.
                onPositionChanged: (camera, __) {
                  final crossed =
                      (camera.zoom < _recordZoom) != (_zoom < _recordZoom);
                  _zoom = camera.zoom;
                  // The hover hint is only valid at add zoom; drop it otherwise.
                  if (_zoom < _addZoom) _hover.value = null;
                  if (crossed || _selected != null || _addingPoint != null) {
                    setState(() {});
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.travel_log',
                  tileProvider: widget.tileProvider,
                ),
                // Per-record lines only make sense when records are shown.
                if (!_collapsed && polylines.isNotEmpty)
                  PolylineLayer(polylines: polylines),
                MarkerLayer(
                  markers: [
                    if (_collapsed)
                      // Zoomed out: one cluster bubble per trip.
                      for (final group in byTrip.entries)
                        Marker(
                          point: _centroid(group.value),
                          width: 168,
                          height: 50,
                          alignment: Alignment.topCenter,
                          child: _HoverBounce(
                            alignment: Alignment.bottomCenter,
                            child: _TripCluster(
                              title: appState.tripById(group.key).title,
                              count: group.value.length,
                              color: _tripColor(group.key),
                              onTap: () => _openTripPanel(group.key,
                                  [for (final e in group.value) e.location!.latLng]),
                            ),
                          ),
                        )
                    else
                      // Zoomed in: individual record bubbles (except the selected
                      // one, drawn expanded, last, on top).
                      for (final e in entries)
                        if (_selected?.id != e.id)
                          Marker(
                            point: e.location!.latLng,
                            width: 30,
                            height: 40,
                            // Bottom-centre (the teardrop tip) sits on the point.
                            alignment: Alignment.topCenter,
                            child: _HoverBounce(
                              alignment: Alignment.bottomCenter,
                              child: _EntryMarker(
                                entry: e,
                                onTap: () => setState(() {
                                  _addingPoint = null;
                                  _selected = e;
                                }),
                              ),
                            ),
                          ),
                    // A pulsing pin marks exactly where the tap landed while the
                    // add-record popup is open.
                    if (_addingPoint != null)
                      Marker(
                        point: _addingPoint!,
                        width: 72,
                        height: 72,
                        child: const _PulsePin(),
                      ),
                    // The selected entry: the bubble expands in place into its
                    // content. Only in the records (zoomed-in) view.
                    if (!_collapsed && _selected != null)
                      Marker(
                        point: _selected!.location!.latLng,
                        width: 250,
                        height: 280,
                        alignment: Alignment.topCenter,
                        child: _ExpandedBubble(
                          entry: _selected!,
                          onClose: () => setState(() => _selected = null),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            if (_addingPoint != null)
              _addPopup(constraints.biggest, _addingPoint!),
            // "Click to add" hint that follows the mouse once zoomed in.
            ValueListenableBuilder<Offset?>(
              valueListenable: _hover,
              builder: (context, pos, _) {
                if (pos == null) return const SizedBox.shrink();
                return Positioned(
                  left: pos.dx,
                  top: pos.dy,
                  child: const IgnorePointer(
                    child: FractionalTranslation(
                      translation: Offset(-0.5, -1.0),
                      child: _AddHint(),
                    ),
                  ),
                );
              },
            ),
          ],
          ),
        );
      },
    );

    // Wide window with a trip selected: the map shares the row with a right-hand
    // records panel. Otherwise the map fills the view on its own.
    final wide = MediaQuery.sizeOf(context).width >= _panelBreakpoint;
    if (!wide || _panelTripId == null) return map;

    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: map),
        VerticalDivider(width: 1, color: theme.dividerColor),
        SizedBox(
          width: 360,
          child: Material(
            child: TripRecordsPanel(
              tripId: _panelTripId!,
              onClose: () => setState(() => _panelTripId = null),
            ),
          ),
        ),
      ],
    );
  }

  /// Hosts the new-entry [EntryForm] as a card anchored at the tapped point,
  /// using the same side-picking / height-capping logic as the preview popup.
  Widget _addPopup(Size size, LatLng point) {
    final pt = _map.camera.latLngToScreenPoint(point);
    // Wider than the preview card to fit the image + side config strip.
    final cardW = size.width - 16 < 460 ? size.width - 16 : 460.0;

    final left =
        (pt.x - cardW / 2).clamp(8.0, size.width - cardW - 8).toDouble();

    // A generous cap based on the whole screen (not just the tap's room), so
    // the form fits without scrolling; the card still sizes to its content.
    final maxHeight = (size.height - 96).clamp(260.0, 460.0);

    final card = Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: EntryForm(
          compact: true,
          initialPoint: point,
          onSaved: _onSaved,
          onClose: () => setState(() => _addingPoint = null),
        ),
      ),
    );

    // Prefer just below the tap; flip above if it would overflow; then clamp so
    // the whole card stays on screen.
    const gap = 24.0;
    var top = pt.y + gap;
    if (top + maxHeight > size.height - 8) top = pt.y - gap - maxHeight;
    top = top.clamp(8.0, size.height - maxHeight - 8).toDouble();

    return Positioned(left: left, top: top, width: cardW, child: card);
  }

}

/// A small label + pin shown at the mouse position once the map is zoomed in
/// enough that a click will place a record there.
class _AddHint extends StatelessWidget {
  const _AddHint();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text('点击此处添加记录',
              style: TextStyle(color: Colors.white, fontSize: 11)),
        ),
        Icon(Icons.place, color: primary, size: 26),
      ],
    );
  }
}

/// Wraps a map bubble so that moving the mouse onto it plays a lively "pop":
/// the bubble swells and springs back to its resting size. [alignment] is the
/// fixed anchor the scale grows from — bottom-centre for teardrop/tailed
/// bubbles, so their tip stays pinned to the map point during the animation.
class _HoverBounce extends StatefulWidget {
  final Widget child;
  final Alignment alignment;

  const _HoverBounce({
    required this.child,
    this.alignment = Alignment.center,
  });

  @override
  State<_HoverBounce> createState() => _HoverBounceState();
}

class _HoverBounceState extends State<_HoverBounce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );

  // Grow quickly, then spring back past the resting size and settle — the
  // elastic tail is what gives it the playful bounce.
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 1.22).chain(
        CurveTween(curve: Curves.easeOut),
      ),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.22, end: 1.0).chain(
        CurveTween(curve: Curves.elasticOut),
      ),
      weight: 65,
    ),
  ]).animate(_c);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _pop() {
    // Replay from the start so a re-entry always bounces afresh.
    _c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _pop(),
      child: ScaleTransition(
        scale: _scale,
        alignment: widget.alignment,
        child: widget.child,
      ),
    );
  }
}

/// An expanding, fading ring around a solid dot — the tap feedback that shows
/// which point on the map is currently selected.
class _PulsePin extends StatefulWidget {
  const _PulsePin();

  @override
  State<_PulsePin> createState() => _PulsePinState();
}

class _PulsePinState extends State<_PulsePin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return CustomPaint(
            painter: _PulsePainter(progress: _c.value, color: color),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  final double progress;
  final Color color;
  _PulsePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.width / 2;

    // Two rings, offset in phase, expanding outward and fading.
    for (final phase in [progress, (progress + 0.5) % 1.0]) {
      final r = maxR * phase;
      final ring = Paint()
        ..color = color.withValues(alpha: (1 - phase) * 0.5)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, r, ring);
    }

    // Solid centre dot with a white outline.
    canvas.drawCircle(center, 8, Paint()..color = Colors.white);
    canvas.drawCircle(center, 6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PulsePainter old) =>
      old.progress != progress || old.color != color;
}

/// A stable colour per trip, so each trip's connecting line is distinguishable.
Color _tripColor(String tripId) {
  final hue = (tripId.hashCode % 360).abs().toDouble();
  return HSLColor.fromAHSL(1, hue, 0.55, 0.45).toColor();
}

/// Average position of a trip's located entries — where its cluster sits.
LatLng _centroid(List<Entry> entries) {
  var lat = 0.0, lng = 0.0;
  for (final e in entries) {
    lat += e.location!.lat;
    lng += e.location!.lng;
  }
  return LatLng(lat / entries.length, lng / entries.length);
}

/// The collapsed, zoomed-out marker for a whole trip: its name and record
/// count in a bubble. Tapping it zooms in to reveal the individual records.
class _TripCluster extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  final VoidCallback onTap;

  const _TripCluster({
    required this.title,
    required this.count,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: _BubblePainter(tailHeight: 10),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87)),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$count',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: color)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A plain teardrop (map-pin) marker. Colour tells the record apart by whether
/// it carries an image: white when it has none, green when it does.
class _EntryMarker extends StatelessWidget {
  final Entry entry;
  final VoidCallback onTap;

  const _EntryMarker({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasImage = entry.hasImage;
    final primary = Theme.of(context).colorScheme.primary;

    final fill = hasImage ? primary : Colors.white;
    final Color border;
    if (hasImage) {
      final hsl = HSLColor.fromColor(primary);
      border = hsl.withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0)).toColor();
    } else {
      border = Colors.grey.shade500;
    }

    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: _TeardropPainter(fill: fill, border: border),
      ),
    );
  }
}

/// Paints a smooth teardrop whose tip is at the bottom-centre. Fill + a thin
/// border + a soft shadow — the plainest map-pin shape.
class _TeardropPainter extends CustomPainter {
  final Color fill;
  final Color border;

  _TeardropPainter({required this.fill, required this.border});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = w / 2;
    final cx = w / 2;
    final center = Offset(cx, r);
    final d = h - r; // circle centre → tip distance
    final alpha = math.acos((r / d).clamp(-1.0, 1.0)); // tangent half-angle

    final path = ui.Path()..moveTo(cx, h); // tip
    // The two straight sides are tangent to the circle; the top is the major arc.
    const down = math.pi / 2;
    path.lineTo(cx + r * math.cos(down + alpha), r + r * math.sin(down + alpha));
    path.arcTo(
      Rect.fromCircle(center: center, radius: r),
      down + alpha,
      2 * math.pi - 2 * alpha,
      false,
    );
    path.close();

    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.4), 2.5, false);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(_TeardropPainter old) =>
      old.fill != fill || old.border != border;
}

/// The selected entry's bubble, expanded in place to show its content. Uses the
/// same tail-at-the-bottom shape, so it still points at the location.
class _ExpandedBubble extends StatelessWidget {
  static const double tailHeight = 12;

  final Entry entry;
  final VoidCallback onClose;

  const _ExpandedBubble({required this.entry, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      // Absorb taps so tapping the card doesn't fall through to the map (which
      // would deselect it); only the close button closes it.
      onTap: () {},
      child: CustomPaint(
        painter: _BubblePainter(tailHeight: tailHeight),
        child: Padding(
          padding: const EdgeInsets.only(bottom: tailHeight),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (entry.hasImage)
                    Stack(
                      children: [
                        EntryImage(
                          imagePath: entry.imagePath,
                          height: 120,
                          fallback: const SizedBox.shrink(),
                        ),
                        // A small count badge when the record has several images.
                        if (entry.imagePaths.length > 1)
                          Positioned(
                            right: 6,
                            bottom: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.photo_library_outlined,
                                      size: 12, color: Colors.white),
                                  const SizedBox(width: 3),
                                  Text('${entry.imagePaths.length}',
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.white)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.markerGlyph,
                                style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(entry.displayTitle,
                                    style: theme.textTheme.titleSmall),
                              ),
                            ),
                            InkWell(
                              onTap: onClose,
                              customBorder: const CircleBorder(),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.close, size: 18),
                              ),
                            ),
                          ],
                        ),
                        if (entry.location != null &&
                            entry.location!.placeName.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('📍 ${entry.location!.placeName}',
                              style: TextStyle(
                                  fontSize: 12, color: theme.hintColor)),
                        ],
                        if (entry.body.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(entry.body,
                              maxLines: 5, overflow: TextOverflow.ellipsis),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a rounded-rectangle bubble with a downward tail. Fill + drop shadow
/// only (no border) — the shadow is what separates it from the map.
class _BubblePainter extends CustomPainter {
  final double tailHeight;

  _BubblePainter({required this.tailHeight});

  @override
  void paint(Canvas canvas, Size size) {
    const r = 8.0;
    const tailW = 12.0;
    final w = size.width;
    final bodyH = size.height - tailHeight;
    final cx = w / 2;

    final path = ui.Path()
      ..moveTo(r, 0)
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: const Radius.circular(r))
      ..lineTo(w, bodyH - r)
      ..arcToPoint(Offset(w - r, bodyH), radius: const Radius.circular(r))
      ..lineTo(cx + tailW / 2, bodyH)
      ..lineTo(cx, size.height) // tail tip = the location
      ..lineTo(cx - tailW / 2, bodyH)
      ..lineTo(r, bodyH)
      ..arcToPoint(Offset(0, bodyH - r), radius: const Radius.circular(r))
      ..lineTo(0, r)
      ..arcToPoint(const Offset(r, 0), radius: const Radius.circular(r))
      ..close();

    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.5), 4, false);
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.tailHeight != tailHeight;
}
