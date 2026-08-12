import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
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

/// A one-way command channel from the desktop side panels into the map: the
/// 旅途 panel asks the map to open a trip's floating records panel (and fit it
/// on the map), so browsing a trip from the nav lands in the very same floating
/// experience as tapping the trip's cluster on the map. Re-issuing the same
/// trip still fires, so tapping a trip twice re-opens it.
class MapCommands extends ChangeNotifier {
  String? _openTripId;
  String? get openTripId => _openTripId;

  void openTrip(String tripId) {
    _openTripId = tripId;
    notifyListeners();
  }
}

/// View 1: a single map with custom-glyph markers pinned at each located entry.
class MapScreen extends StatefulWidget {
  /// Overridable so widget tests can supply an offline provider instead of
  /// hitting the real OSM tile servers.
  final TileProvider? tileProvider;

  /// Optional channel the desktop 旅途 panel uses to open a trip on the map.
  final MapCommands? commands;

  const MapScreen({super.key, this.tileProvider, this.commands});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final MapController _map = MapController();

  /// Selected base-map style (index into [_mapStyles]); switchable at runtime
  /// from the settings button in the bottom-left corner.
  int _styleIndex = 0;

  /// Hides the place-name label overlay on styles that ship one as a separate
  /// layer (the CARTO family); baked-label styles ignore it.
  bool _labelsHidden = false;

  /// How each trip's records are joined into a route line. The two modes are
  /// mutually exclusive and switched from the map settings dialog. See
  /// [_centripetalCurve] and [_greatCircleCurve].
  _CurveStyle _curveStyle = _CurveStyle.centripetal;

  /// Mouse hover position over the map (desktop/web), for the "click to add"
  /// hint shown once zoomed in enough. A notifier so moving the mouse rebuilds
  /// only the hint, not the whole map.
  final ValueNotifier<Offset?> _hover = ValueNotifier(null);

  /// Drives the short zoom-in animation on a map tap.
  AnimationController? _moveController;

  /// Target zoom of an in-flight mouse-wheel zoom, so quick successive notches
  /// accumulate instead of each re-reading the mid-animation zoom. Null when no
  /// wheel zoom is currently settling.
  double? _wheelTargetZoom;

  /// Zoom change per unit of scroll-wheel delta — flutter_map's own default
  /// (`scrollWheelVelocity`), kept so the sensitivity is unchanged; only the
  /// easing below is new.
  static const double _wheelZoomPerScroll = 0.005;

  /// Ceiling for wheel zoom. The map sets no `maxZoom`, so this just keeps the
  /// eased animation from chasing an unbounded target on a long scroll.
  static const double _wheelMaxZoom = 20;

  @override
  void initState() {
    super.initState();
    // After the first frame (a live GPU context exists), warm the one-off
    // CanvasKit compiles the record bubble triggers. See [_warmUpBubble].
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _warmUpBubble();
    });
    widget.commands?.addListener(_onCommand);
  }

  /// Opens the trip the 旅途 panel asked for as the map's floating records
  /// panel (and fits it on the map) — the same panel a cluster tap opens.
  void _onCommand() {
    final tripId = widget.commands?.openTripId;
    if (tripId == null) return;
    final points = [
      for (final e in context.read<AppState>().entriesForTrip(tripId))
        if (e.location != null) e.location!.latLng,
    ];
    _openTripPanel(tripId, points);
  }

  /// Opens the map settings dialog: base-map style, place-name visibility and
  /// the route-line style. The dialog writes straight back through these
  /// setters so the map updates live while it's open.
  void _openSettings() {
    showDialog<void>(
      context: context,
      builder: (_) => _MapSettingsDialog(
        styles: _mapStyles,
        styleIndex: _styleIndex,
        labelsHidden: _labelsHidden,
        curveStyle: _curveStyle,
        onStyle: (i) => setState(() => _styleIndex = i),
        onLabels: (hidden) => setState(() => _labelsHidden = hidden),
        onCurve: (curve) => setState(() => _curveStyle = curve),
      ),
    );
  }

  /// Pre-compiles the first-frame CanvasKit work that opening a record bubble
  /// triggers, so the *first* record tap doesn't stutter (it's smooth on the
  /// second because these are cached after the first paint).
  ///
  /// On CanvasKit/web the costly one-offs are: rasterizing a colour emoji — the
  /// marker glyphs (⛩️/📷/✍️/🎨/🌙) and 📍 — which compiles a dedicated emoji
  /// shader and seeds the colour-glyph atlas; text shaping; and the bubble's
  /// rounded-rect anti-aliased clip. The map draws none of these before a record
  /// is opened, so the first bubble pays all of it at once. Rendering them once
  /// offscreen here moves that cost to startup.
  ///
  /// [Picture.toImageSync] rasterizes into the same shared GPU context the map
  /// uses, so the compiled programs and glyph atlas are cache hits when the real
  /// bubble draws. Best-effort: any failure just forgoes the warm-up.
  void _warmUpBubble() {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      // Rounded-rect AA clip, matching the bubble's ClipRRect.
      canvas.clipRRect(RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 80, 80), const Radius.circular(8)));
      // Colour emoji + latin + CJK, matching the glyph + title/body text.
      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 20))
        ..addText('📍⛩️📷✍️🎨🌙 记录 Ag');
      final paragraph = builder.build()
        ..layout(const ui.ParagraphConstraints(width: 200));
      canvas.drawParagraph(paragraph, Offset.zero);
      final picture = recorder.endRecording();
      picture.toImageSync(80, 80).dispose();
      picture.dispose();
    } catch (_) {
      // Warm-up is a pure optimization; never let it break the screen.
    }
  }

  /// Warms the glyphs each loaded record's bubble will paint — its marker glyph,
  /// title, place name and body text (CJK included) — so the *first* tap on a
  /// given record doesn't stall while CanvasKit shapes and rasterizes those
  /// glyphs onto the atlas for the first time (which is why the same record is
  /// smooth on the second tap, but every *new* record stutters once).
  ///
  /// Runs in small batches chained across frames so it never blocks startup, and
  /// records each warmed id so a record is only ever warmed once. Best-effort.
  void _scheduleEntryTextWarmup(List<Entry> entries) {
    final batch = <Entry>[];
    for (final e in entries) {
      if (_warmedTextIds.add(e.id)) batch.add(e);
      if (batch.length >= 8) break; // cap per frame to keep startup smooth
    }
    if (batch.isEmpty) {
      _textWarmupRunning = false;
      return;
    }
    _textWarmupRunning = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _textWarmupRunning = false;
        return;
      }
      _rasterizeEntryText(batch);
      // Continue with any remaining (or newly-added) records next frame.
      _scheduleEntryTextWarmup(entries);
    });
  }

  /// Rasterizes one batch of records' bubble text offscreen, stacking each into
  /// a single picture so every glyph actually paints (and thus warms the atlas).
  void _rasterizeEntryText(List<Entry> batch) {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      // The bubble caps the body at 5 lines; ~200px covers glyph + title + place
      // + those lines at the bubble's inner width.
      const slot = 200.0;
      const width = 226.0;
      var y = 0.0;
      for (final e in batch) {
        final place = e.location?.placeName ?? '';
        // Match the sizes the real bubble paints at — the glyph atlas is keyed
        // by font size, so warming at a single size wouldn't cache them.
        final pb = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 14))
          ..pushStyle(ui.TextStyle(fontSize: 20)) // marker glyph
          ..addText('${e.markerGlyph} ')
          ..pop()
          ..pushStyle(ui.TextStyle(fontSize: 14)) // title
          ..addText('${e.displayTitle}\n')
          ..pop();
        if (place.isNotEmpty) {
          pb
            ..pushStyle(ui.TextStyle(fontSize: 12)) // place name
            ..addText('📍 $place\n')
            ..pop();
        }
        if (e.body.isNotEmpty) {
          pb
            ..pushStyle(ui.TextStyle(fontSize: 14)) // body
            ..addText(e.body)
            ..pop();
        }
        final paragraph = pb.build()
          ..layout(const ui.ParagraphConstraints(width: width));
        canvas.drawParagraph(paragraph, Offset(0, y));
        y += slot;
      }
      final picture = recorder.endRecording();
      picture.toImageSync(width.ceil(), y.ceil().clamp(1, 4000)).dispose();
      picture.dispose();
    } catch (_) {
      // Warm-up is a pure optimization; never let it break the screen.
    }
  }

  @override
  void dispose() {
    widget.commands?.removeListener(_onCommand);
    _moveController?.dispose();
    _hover.dispose();
    _selectedN.dispose();
    super.dispose();
  }

  /// Smoothly zooms/pans to [dest] at [destZoom] by interpolating the camera —
  /// flutter_map's own [MapController.move] is instant. [onArrived] fires once
  /// the glide settles (used by the wheel handler to clear its pending target).
  void _animatedMove(
    LatLng dest,
    double destZoom, {
    Duration duration = const Duration(milliseconds: 300),
    VoidCallback? onArrived,
  }) {
    final startCenter = _map.camera.center;
    final startZoom = _map.camera.zoom;
    final latTween =
        Tween(begin: startCenter.latitude, end: dest.latitude);
    final lngTween =
        Tween(begin: startCenter.longitude, end: dest.longitude);
    final zoomTween = Tween(begin: startZoom, end: destZoom);

    _moveController?.dispose();
    final controller = AnimationController(vsync: this, duration: duration);
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
        onArrived?.call();
      }
    });
    controller.forward();
  }

  /// Handles a mouse-wheel / trackpad scroll as an *eased* zoom toward the
  /// cursor, giving the "slight inertia" glide that flutter_map's built-in
  /// (instant, per-notch) scroll-wheel zoom lacks. Successive notches build on
  /// [_wheelTargetZoom] so a fast scroll still zooms the full distance, and
  /// [MapCamera.focusedZoomCenter] keeps the point under the cursor pinned —
  /// same focal behaviour as the native handler we replaced.
  void _onWheelZoom(PointerScrollEvent event, double minZoom) {
    final base = _wheelTargetZoom ?? _map.camera.zoom;
    final target = (base - event.scrollDelta.dy * _wheelZoomPerScroll)
        .clamp(minZoom, _wheelMaxZoom)
        .toDouble();
    _wheelTargetZoom = target;
    final cursor = math.Point<double>(
        event.localPosition.dx, event.localPosition.dy);
    _animatedMove(
      _map.camera.focusedZoomCenter(cursor, target),
      target,
      duration: const Duration(milliseconds: 220),
      onArrived: () => _wheelTargetZoom = null,
    );
  }

  /// The entry whose preview popup is shown, if any. Held in a notifier (not
  /// plain setState) so selecting or closing a record rebuilds *only* the
  /// bubble overlay layer — not the whole FlutterMap subtree (tiles, lines and
  /// every marker), which is what made the first record tap stutter.
  final ValueNotifier<Entry?> _selectedN = ValueNotifier(null);

  /// Record ids whose bubble text has already been warmed into the glyph atlas
  /// (see [_scheduleEntryTextWarmup]), so each record is warmed only once.
  final Set<String> _warmedTextIds = {};

  /// True while a text-warmup batch chain is in flight, so [build] doesn't start
  /// a second overlapping chain.
  bool _textWarmupRunning = false;

  /// The point where a new-entry form popup is open, if any. Mutually exclusive
  /// with [_selectedN].
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
    _selectedN.value = null;
    setState(() => _addingPoint = point);
  }

  /// Centres the map on [entry] and expands its card. Shared by tapping a
  /// marker and by saving a new located record, so both give the same feedback.
  void _selectEntry(Entry entry) {
    // Selecting only flips the bubble-overlay notifier — no setState — so the
    // whole FlutterMap subtree isn't rebuilt on every record tap. Dismissing an
    // open add-popup is the one case that still needs a full rebuild.
    if (_addingPoint != null) setState(() => _addingPoint = null);
    _selectedN.value = entry;
    final loc = entry.location;
    if (loc != null) {
      _wheelTargetZoom = null;
      _animatedMove(loc.latLng, math.max(_zoom, _recordZoom + 4).toDouble());
    }
  }

  void _onSaved(Entry entry) {
    if (entry.location != null) {
      // A located record (e.g. a geotagged photo): zoom to it and expand its
      // card so the just-saved entry is front-and-centre.
      _selectEntry(entry);
    } else {
      _selectedN.value = null;
      setState(() => _addingPoint = null);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('记录已保存')),
    );
  }

  /// Tapping a trip cluster zooms the map to fit that trip's records, which
  /// crosses [_recordZoom] and expands them back into individual bubbles.
  void _fitTrip(List<LatLng> points) {
    _selectedN.value = null;
    setState(() => _addingPoint = null);
    // A trip whose records carry no location: open its panel but leave the
    // camera where it is (there's nothing to fit).
    if (points.isEmpty) return;
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
      _selectedN.value = null;
      setState(() {
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

    // Warm each loaded record's bubble glyphs ahead of the first tap. Kicks off
    // once here (and again when new records appear); the chain de-dupes per id.
    if (!_textWarmupRunning &&
        entries.any((e) => !_warmedTextIds.contains(e.id))) {
      _scheduleEntryTextWarmup(entries);
    }

    // A panel pointing at a since-deleted trip falls back to closed.
    if (_panelTripId != null &&
        !appState.trips.any((t) => t.id == _panelTripId)) {
      _panelTripId = null;
    }

    // If the selected entry was deleted/filtered out, drop the popup. The
    // notifier write is deferred out of build (mutating it here would mark the
    // overlay layer dirty mid-build).
    final selected = _selectedN.value;
    if (selected != null && !entries.any((e) => e.id == selected.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedN.value?.id == selected.id) {
          _selectedN.value = null;
        }
      });
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
      final located = [for (final e in list) e.location!.latLng];
      polylines.add(Polyline(
        // A flowing curve through the records rather than raw straight hops, so
        // a trip's path reads as one continuous journey. The shape depends on
        // the chosen [_curveStyle]: a centripetal spline through the points, or
        // true great-circle arcs between them.
        points: _curveStyle == _CurveStyle.greatCircle
            ? _greatCircleCurve(located)
            : _centripetalCurve(located),
        // A thin dark-grey dashed line for every trip — a quiet route hint that
        // doesn't compete with the records themselves (trips are still told
        // apart by their cluster colour when zoomed out).
        color: Colors.grey.shade700,
        strokeWidth: 1.5,
        pattern: StrokePattern.dashed(segments: const [7, 6]),
      ));
    });

    final style = _mapStyles[_styleIndex];
    final map = LayoutBuilder(

      builder: (context, constraints) {
        // Web Mercator draws the whole world 256 * 2^zoom px tall, so keeping it
        // covering the viewport height — no grey band above or below — means the
        // zoom can't drop below log2(viewportHeight / 256). Recomputed on resize.
        final h = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : 600.0;
        final minZoom = math.max(0.0, math.log(h / 256) / math.ln2);
        return Listener(
          // Scroll wheel / trackpad zoom, eased for a slight inertia glide.
          onPointerSignal: (signal) {
            if (signal is PointerScrollEvent && signal.scrollDelta.dy != 0) {
              _onWheelZoom(signal, minZoom);
            }
          },
          child: MouseRegion(
          onHover: (e) {
            _hover.value = (_zoom >= _addZoom &&
                    _selectedN.value == null &&
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
                // Can't zoom out past the point where the map fills the window
                // vertically (top & bottom edges flush with the page).
                minZoom: minZoom,
                interactionOptions: const InteractionOptions(
                  // Drop the built-in scroll-wheel zoom (instant, per-notch);
                  // it's replaced below with an eased, cursor-focused glide.
                  flags: InteractiveFlag.all & ~InteractiveFlag.scrollWheelZoom,
                  // Race the multi-finger gestures so a two-finger pinch that
                  // crosses the zoom threshold *wins* and locks out rotation —
                  // no more accidental spin while zooming. (Fling inertia stays
                  // on via InteractiveFlag.flingAnimation, at its defaults.)
                  enableMultiFingerGestureRace: true,
                ),
                onTap: (_, point) {
                  // An open popup (preview or add form) gets dismissed first.
                  if (_selectedN.value != null || _addingPoint != null) {
                    _selectedN.value = null;
                    if (_addingPoint != null) {
                      setState(() => _addingPoint = null);
                    }
                  } else if (_zoom < _addZoom) {
                    // Not zoomed in enough to place a record precisely — zoom
                    // (animated) toward the tapped point instead of adding.
                    _wheelTargetZoom = null;
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
                  // Only rebuild when we truly must. The selected entry's bubble
                  // is a Marker inside MarkerLayer, so flutter_map already keeps
                  // it pinned as the camera moves — rebuilding the whole screen
                  // for it every frame just makes panning heavier (and turns the
                  // first-run shader/texture compile into a visible stutter). The
                  // add-entry popup, by contrast, is a Positioned outside the map
                  // and does need per-frame repositioning.
                  if (crossed || _addingPoint != null) {
                    setState(() {});
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: style.urlTemplate,
                  subdomains: style.subdomains,
                  maxNativeZoom: style.maxNativeZoom,
                  userAgentPackageName: 'com.example.travel_log',
                  tileProvider: widget.tileProvider,
                ),
                // Transparent place-name overlay for styles that ship one, sat
                // above the base map but below the trip lines and markers. The
                // "hide labels" toggle simply drops this layer.
                if (style.labelsUrlTemplate != null && !_labelsHidden)
                  TileLayer(
                    urlTemplate: style.labelsUrlTemplate!,
                    subdomains: style.subdomains,
                    maxNativeZoom: style.maxNativeZoom,
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
                      // Zoomed in: individual record pins. The selected one keeps
                      // its pin (the expanded bubble, a separate layer below, sits
                      // on top of it) so this list never rebuilds on selection.
                      for (final e in entries)
                        Marker(
                          point: e.location!.latLng,
                          width: 30,
                          height: 40,
                          // Bottom-centre (the teardrop tip) sits on the point.
                          alignment: Alignment.topCenter,
                          child: _HoverBounce(
                            alignment: Alignment.bottomCenter,
                            child: _EntryMarker(
                              onTap: () => _selectEntry(e),
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
                  ],
                ),
                // The selected entry's expanded bubble, in its own layer driven
                // by _selectedN. Selecting/closing a record rebuilds only this
                // ValueListenableBuilder — not the tiles, lines or marker list —
                // so the first tap no longer stutters on a full-map rebuild.
                ValueListenableBuilder<Entry?>(
                  valueListenable: _selectedN,
                  builder: (context, selected, _) {
                    // Only in the records (zoomed-in) view.
                    if (_collapsed || selected?.location == null) {
                      return const MarkerLayer(markers: []);
                    }
                    return MarkerLayer(
                      markers: [
                        Marker(
                          point: selected!.location!.latLng,
                          width: 250,
                          height: 280,
                          alignment: Alignment.topCenter,
                          child: _ExpandedBubble(
                            entry: selected,
                            onClose: () => _selectedN.value = null,
                          ),
                        ),
                      ],
                    );
                  },
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
            // Map settings button (bottom-left) — opens a dialog gathering the
            // base-map style, the place-name toggle and the route-line style.
            Positioned(
              left: 16,
              bottom: 16,
              child: _MapSettingsButton(onTap: _openSettings),
            ),
            Positioned(
              right: 8,
              bottom: 6,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(style.attribution,
                        style: const TextStyle(
                            fontSize: 9, color: Colors.black54)),
                  ),
                ),
              ),
            ),
          ],
          ),
          ),
        );
      },
    );

    // Wide window with a trip selected: the map keeps the whole window and the
    // trip's records float over it as a rounded card on the right — no docked
    // pane or divider line. Tapping a record zooms the map to its location.
    // Otherwise the map fills the view on its own.
    final wide = MediaQuery.sizeOf(context).width >= _panelBreakpoint;
    if (!wide || _panelTripId == null) return map;

    return Stack(
      children: [
        Positioned.fill(child: map),
        Positioned(
          top: 20,
          right: 20,
          bottom: 20,
          width: 360,
          child: Material(
            elevation: 6,
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            // Rebuild only the panel (not the map) when the map selection
            // changes, so the expanded record shows highlighted in the list.
            child: ValueListenableBuilder<Entry?>(
              valueListenable: _selectedN,
              builder: (context, selected, _) => TripRecordsPanel(
                tripId: _panelTripId!,
                onClose: () => setState(() => _panelTripId = null),
                onRecordTap: _selectEntry,
                selectedEntryId: selected?.id,
              ),
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
        // Same frosted-white glass material as the map's other labels, blurring
        // the map behind the hint instead of a solid black chip.
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.68),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
              ),
              child: const Text('点击此处添加记录',
                  style: TextStyle(color: Colors.black87, fontSize: 11)),
            ),
          ),
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

/// Densifies [pts] into a **centripetal** Catmull-Rom spline (the α=0.5
/// parameterization) so flutter_map draws the trip path as a flowing curve
/// instead of straight point-to-point segments.
///
/// Unlike the plain *uniform* Catmull-Rom, the knot spacing follows the square
/// root of each chord length. That removes the overshoot and self-intersecting
/// loops uniform Catmull-Rom produces when records are unevenly spaced — a tight
/// cluster of records inside one city sitting next to a long hop to the next,
/// which is exactly how trips look. The spline still passes *through* every
/// original record, so the line visibly connects each place; [samples]
/// interpolated points per span set how smooth each bend is. Two points (or
/// fewer) have no curvature to add, so they're returned unchanged.
List<LatLng> _centripetalCurve(List<LatLng> pts, {int samples = 18}) {
  if (pts.length < 3) return pts;
  const alpha = 0.5;
  // Duplicate the extremes so the curve starts/ends exactly on the first/last
  // record (the end spans have no outer neighbour otherwise).
  final p = [pts.first, ...pts, pts.last];
  final out = <LatLng>[pts.first];

  double knot(double t, LatLng a, LatLng b) {
    final dx = a.latitude - b.latitude, dy = a.longitude - b.longitude;
    // max() guards against coincident records collapsing a knot interval to
    // zero (which would divide by zero below).
    return t + math.pow(math.max(math.sqrt(dx * dx + dy * dy), 1e-9), alpha);
  }

  for (var i = 1; i < p.length - 2; i++) {
    final p0 = p[i - 1], p1 = p[i], p2 = p[i + 1], p3 = p[i + 2];
    const t0 = 0.0;
    final t1 = knot(t0, p0, p1);
    final t2 = knot(t1, p1, p2);
    final t3 = knot(t2, p2, p3);
    for (var s = 1; s <= samples; s++) {
      final t = t1 + (t2 - t1) * s / samples;
      // Barry–Goldman pyramidal evaluation, per axis. Over the short spans
      // between records lat/lng behaves flat enough to interpolate directly.
      double axis(double a, double b, double c, double d) {
        final a1 = (t1 - t) / (t1 - t0) * a + (t - t0) / (t1 - t0) * b;
        final a2 = (t2 - t) / (t2 - t1) * b + (t - t1) / (t2 - t1) * c;
        final a3 = (t3 - t) / (t3 - t2) * c + (t - t2) / (t3 - t2) * d;
        final b1 = (t2 - t) / (t2 - t0) * a1 + (t - t0) / (t2 - t0) * a2;
        final b2 = (t3 - t) / (t3 - t1) * a2 + (t - t1) / (t3 - t1) * a3;
        return (t2 - t) / (t2 - t1) * b1 + (t - t1) / (t2 - t1) * b2;
      }

      out.add(LatLng(
        axis(p0.latitude, p1.latitude, p2.latitude, p3.latitude),
        axis(p0.longitude, p1.longitude, p2.longitude, p3.longitude),
      ));
    }
  }
  return out;
}

/// Connects [pts] with gently bowed "flight-path" arcs — the aviation-map look.
///
/// A *true* great-circle geodesic is the honest answer, but over the short
/// distances a travel log usually spans it is visually indistinguishable from a
/// straight line on Web Mercator (it only bows perceptibly across continental,
/// mostly east–west hops), so it renders dead straight for real trips. Instead,
/// each segment is drawn as a shallow arc that bows a fixed [bulge] fraction of
/// its length to one consistent side, so it reads as a curve at *any* scale.
///
/// The bow is computed in a local equirectangular frame (longitude scaled by
/// cos(latitude)) so it looks perpendicular to the segment *on screen* instead
/// of being skewed by longitude degrees shrinking away from the equator. Very
/// short or coincident spans collapse to a straight join; fewer than two points
/// have nothing to connect. [samples] sets each arc's smoothness.
List<LatLng> _greatCircleCurve(List<LatLng> pts,
    {int samples = 24, double bulge = 0.18}) {
  if (pts.length < 2) return pts;
  const deg2rad = math.pi / 180;
  final out = <LatLng>[pts.first];
  for (var i = 0; i < pts.length - 1; i++) {
    final a = pts[i], b = pts[i + 1];
    // Local longitude scale, so a degree of longitude and a degree of latitude
    // cover comparable screen distance around this segment.
    final cosLat =
        math.cos((a.latitude + b.latitude) / 2 * deg2rad).abs();
    final k = cosLat < 1e-6 ? 1e-6 : cosLat;
    // Planar coords: x is scaled longitude, y is latitude.
    final ax = a.longitude * k, ay = a.latitude;
    final bx = b.longitude * k, by = b.latitude;
    final dx = bx - ax, dy = by - ay;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-9) {
      out.add(b); // effectively the same point — nothing to bow.
      continue;
    }
    // Control point: segment midpoint pushed out along the left-hand normal, so
    // every segment bows the same way and none can come out perfectly straight.
    final cx = (ax + bx) / 2 + (-dy / len) * len * bulge;
    final cy = (ay + by) / 2 + (dx / len) * len * bulge;
    for (var s = 1; s <= samples; s++) {
      final t = s / samples, mt = 1 - t;
      // Quadratic Bézier a → control → b, in the planar frame.
      final px = mt * mt * ax + 2 * mt * t * cx + t * t * bx;
      final py = mt * mt * ay + 2 * mt * t * cy + t * t * by;
      out.add(LatLng(py, px / k)); // unscale longitude back to degrees
    }
  }
  return out;
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
      child: _FrostedBubble(
        tailHeight: 10,
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

/// A plain teardrop (map-pin) marker. Every record's pin is the same
/// translucent-white material — a uniform, quiet marker regardless of whether
/// the record carries an image.
class _EntryMarker extends StatelessWidget {
  final VoidCallback onTap;

  const _EntryMarker({required this.onTap});

  @override
  Widget build(BuildContext context) {
    // One shared look for all pins: a semi-transparent white fill (the map
    // shows faintly through) with a hairline grey rim to hold its edge.
    final fill = Colors.white.withValues(alpha: 0.7);
    final border = Colors.grey.shade400;

    return GestureDetector(
      onTap: onTap,
      // RepaintBoundary caches the painted teardrop as its own layer, so during
      // a map pan/zoom animation (or when the bubble appears) CanvasKit just
      // re-composites the cached texture instead of re-running the painter for
      // every visible pin each frame. Without it, N visible pins meant N
      // re-paints per frame — the source of the "many pins on screen = stutter"
      // behaviour.
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _TeardropPainter(fill: fill, border: border),
        ),
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

    _paintSoftShadow(canvas, path, spread: 2.4, alpha: 0.16);
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
      child: _FrostedBubble(
        tailHeight: tailHeight,
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

/// Builds the rounded-rectangle-with-downward-tail outline every map bubble
/// shares — the cluster label and the expanded record card. Kept in one place
/// so the shadow, the frosted-glass clip and the border all trace exactly the
/// same shape. The tail tip sits at the bottom-centre (the map location).
ui.Path _bubblePath(Size size, double tailHeight) {
  const r = 8.0;
  const tailW = 12.0;
  final w = size.width;
  final bodyH = size.height - tailHeight;
  final cx = w / 2;

  return ui.Path()
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
}

/// A translucent, frosted-glass bubble in the shared tailed shape: it blurs the
/// map showing through, tints it with a soft white, and rims it with a hairline
/// glass edge. Used for both the cluster label and the expanded record card so
/// every on-map label reads as the same material.
///
/// Layering: a soft drop shadow paints *behind* (so it isn't blurred away), the
/// blur + white tint fill the clipped shape, and the hairline border paints on
/// *top* as a foreground so it stays crisp over the frosted fill.
class _FrostedBubble extends StatelessWidget {
  final double tailHeight;
  final Widget child;

  const _FrostedBubble({required this.tailHeight, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BubbleShadowPainter(tailHeight: tailHeight),
      foregroundPainter: _BubbleBorderPainter(tailHeight: tailHeight),
      child: ClipPath(
        clipper: _BubbleClipper(tailHeight: tailHeight),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          // Slightly translucent white so the blurred map tints through — the
          // "毛玻璃" look — while text stays legible on top.
          child: ColoredBox(
            color: Colors.white.withValues(alpha: 0.68),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Clips a bubble's contents (blur + fill) to the shared tailed outline.
///
/// The clip type is spelled `ui.Path` explicitly: latlong2 also exports a
/// `Path` (a geographic path), so a bare `Path` here binds to the wrong type.
class _BubbleClipper extends CustomClipper<ui.Path> {
  final double tailHeight;

  _BubbleClipper({required this.tailHeight});

  @override
  ui.Path getClip(Size size) => _bubblePath(size, tailHeight);

  @override
  bool shouldReclip(_BubbleClipper old) => old.tailHeight != tailHeight;
}

/// Paints only the soft drop shadow of a bubble, behind its frosted fill — the
/// shadow is what lifts the translucent label off the map.
class _BubbleShadowPainter extends CustomPainter {
  final double tailHeight;

  _BubbleShadowPainter({required this.tailHeight});

  @override
  void paint(Canvas canvas, Size size) {
    _paintSoftShadow(canvas, _bubblePath(size, tailHeight),
        spread: 4.0, alpha: 0.14);
  }

  @override
  bool shouldRepaint(_BubbleShadowPainter old) =>
      old.tailHeight != tailHeight;
}

/// Paints the hairline glass rim on top of the frosted fill, so the label has a
/// defined edge against busy map tiles.
class _BubbleBorderPainter extends CustomPainter {
  final double tailHeight;

  _BubbleBorderPainter({required this.tailHeight});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      _bubblePath(size, tailHeight),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_BubbleBorderPainter old) =>
      old.tailHeight != tailHeight;
}

/// Draws a soft drop shadow for [path] by stacking a few downward-offset fills
/// of the same shape, fading with distance.
///
/// This deliberately avoids [Canvas.drawShadow]: that call compiles a dedicated
/// GPU shadow shader (plus, on CanvasKit/web, shadow geometry) lazily the first
/// time it rasterizes — which for the map's markers is the first time a record
/// is tapped, landing as a one-off stutter that's gone by the second tap. Plain
/// path fills reuse the shader the solid shape itself already uses, so there's
/// nothing new to compile and every tap is equally smooth. [spread] is the
/// furthest offset (in px); [alpha] is each layer's opacity, which stacks toward
/// the bottom for a graded edge.
void _paintSoftShadow(
  Canvas canvas,
  ui.Path path, {
  required double spread,
  required double alpha,
}) {
  final paint = Paint()..color = Colors.black.withValues(alpha: alpha);
  for (var i = 1; i <= 3; i++) {
    canvas.save();
    canvas.translate(0, spread * i / 3);
    canvas.drawPath(path, paint);
    canvas.restore();
  }
}

/// A selectable base-map tile style. All entries here are free and keyless; the
/// `attribution` string is the credit each provider's terms require on screen.
class _MapStyle {
  final String label;
  final String urlTemplate;

  /// A transparent labels-only overlay for this style, or null if the style
  /// bakes labels into its tiles (or has none). Its presence is what lets the
  /// place names be hidden independently of the base map.
  final String? labelsUrlTemplate;
  final List<String> subdomains;

  /// Highest zoom the provider actually ships tiles for; beyond it flutter_map
  /// upscales the last real tiles instead of requesting missing ones.
  final int maxNativeZoom;
  final String attribution;

  const _MapStyle({
    required this.label,
    required this.urlTemplate,
    this.labelsUrlTemplate,
    this.subdomains = const [],
    this.maxNativeZoom = 19,
    required this.attribution,
  });
}

/// The switchable base maps. URLs verified against each provider's current
/// keyless raster endpoint; order is the order shown in the picker.
const _mapStyles = <_MapStyle>[
  _MapStyle(
    label: '标准',
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    maxNativeZoom: 19,
    attribution: '© OpenStreetMap contributors',
  ),
  _MapStyle(
    label: '浅色',
    urlTemplate:
        'https://{s}.basemaps.cartocdn.com/light_nolabels/{z}/{x}/{y}.png',
    labelsUrlTemplate:
        'https://{s}.basemaps.cartocdn.com/light_only_labels/{z}/{x}/{y}.png',
    subdomains: ['a', 'b', 'c', 'd'],
    maxNativeZoom: 20,
    attribution: '© OpenStreetMap contributors © CARTO',
  ),
  _MapStyle(
    label: '深色',
    urlTemplate:
        'https://{s}.basemaps.cartocdn.com/dark_nolabels/{z}/{x}/{y}.png',
    labelsUrlTemplate:
        'https://{s}.basemaps.cartocdn.com/dark_only_labels/{z}/{x}/{y}.png',
    subdomains: ['a', 'b', 'c', 'd'],
    maxNativeZoom: 20,
    attribution: '© OpenStreetMap contributors © CARTO',
  ),
  _MapStyle(
    label: '彩色',
    urlTemplate:
        'https://{s}.basemaps.cartocdn.com/rastertiles/voyager_nolabels/{z}/{x}/{y}.png',
    labelsUrlTemplate:
        'https://{s}.basemaps.cartocdn.com/rastertiles/voyager_only_labels/{z}/{x}/{y}.png',
    subdomains: ['a', 'b', 'c', 'd'],
    maxNativeZoom: 20,
    attribution: '© OpenStreetMap contributors © CARTO',
  ),
  _MapStyle(
    label: '卫星',
    urlTemplate:
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    maxNativeZoom: 19,
    attribution: 'Tiles © Esri, Maxar, Earthstar Geographics',
  ),
  _MapStyle(
    label: '地形',
    urlTemplate: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
    subdomains: ['a', 'b', 'c'],
    maxNativeZoom: 17,
    attribution: '© OpenStreetMap · SRTM | © OpenTopoMap (CC-BY-SA)',
  ),
  _MapStyle(
    label: '骑行',
    urlTemplate:
        'https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png',
    subdomains: ['a', 'b', 'c'],
    maxNativeZoom: 20,
    attribution: '© OpenStreetMap contributors · CyclOSM',
  ),
];

/// The two mutually-exclusive route-line styles offered in the map settings.
/// Each carries its own picker label, one-line description and icon.
enum _CurveStyle {
  centripetal('向心曲线', '平滑穿过每个记录点，转弯自然、不打结', Icons.gesture),
  greatCircle('大圆弧', '以航线般的弧线相连，任何距离都清晰可见', Icons.public);

  const _CurveStyle(this.label, this.description, this.icon);

  final String label;
  final String description;
  final IconData icon;
}

/// The map settings button (bottom-left of the map). The style-swatch icon
/// reads as "map appearance"; tapping it opens the [_MapSettingsDialog].
class _MapSettingsButton extends StatelessWidget {
  final VoidCallback onTap;

  const _MapSettingsButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: '地图设置',
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 3,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(Icons.style_outlined,
                color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// The map settings popup: base-map style, the place-name toggle and the
/// route-line style, gathered in one dialog. It keeps a local copy of each
/// value so its own controls rebuild instantly, and forwards every change
/// straight through the callbacks so the map behind it updates live.
class _MapSettingsDialog extends StatefulWidget {
  final List<_MapStyle> styles;
  final int styleIndex;
  final bool labelsHidden;
  final _CurveStyle curveStyle;
  final ValueChanged<int> onStyle;
  final ValueChanged<bool> onLabels;
  final ValueChanged<_CurveStyle> onCurve;

  const _MapSettingsDialog({
    required this.styles,
    required this.styleIndex,
    required this.labelsHidden,
    required this.curveStyle,
    required this.onStyle,
    required this.onLabels,
    required this.onCurve,
  });

  @override
  State<_MapSettingsDialog> createState() => _MapSettingsDialogState();
}

class _MapSettingsDialogState extends State<_MapSettingsDialog> {
  late int _styleIndex = widget.styleIndex;
  late bool _labelsHidden = widget.labelsHidden;
  late _CurveStyle _curve = widget.curveStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Only the CARTO family ships a separate labels overlay that can be hidden;
    // baked-label styles disable the toggle.
    final labelsAvailable =
        widget.styles[_styleIndex].labelsUrlTemplate != null;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.style_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Text('地图设置', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel(theme, '底图样式'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < widget.styles.length; i++)
                          ChoiceChip(
                            label: Text(widget.styles[i].label),
                            selected: i == _styleIndex,
                            onSelected: (_) {
                              setState(() => _styleIndex = i);
                              widget.onStyle(i);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('隐藏地名'),
                      subtitle: Text(labelsAvailable
                          ? '不显示底图上的地名标注'
                          : '该底图无法单独隐藏地名'),
                      value: labelsAvailable && _labelsHidden,
                      onChanged: labelsAvailable
                          ? (v) {
                              setState(() => _labelsHidden = v);
                              widget.onLabels(v);
                            }
                          : null,
                    ),
                    const Divider(height: 28),
                    _sectionLabel(theme, '连线样式'),
                    const SizedBox(height: 10),
                    SegmentedButton<_CurveStyle>(
                      showSelectedIcon: false,
                      segments: [
                        for (final c in _CurveStyle.values)
                          ButtonSegment<_CurveStyle>(
                            value: c,
                            label: Text(c.label),
                            icon: Icon(c.icon),
                          ),
                      ],
                      selected: {_curve},
                      onSelectionChanged: (selection) {
                        setState(() => _curve = selection.first);
                        widget.onCurve(selection.first);
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _curve.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) => Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.4,
        ),
      );
}
