import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/entry.dart';
import '../state/app_state.dart';

/// A horizontal timeline of one trip's records, pinned to the bottom of the
/// wide (web / desktop) map while a trip is open.
///
/// The right-hand [TripRecordsPanel] answers "what is in this trip"; this band
/// answers "when did it happen". It is a true time axis: every day of the trip
/// is one 24-hour span of equal width with a tick per hour (6/12/18 labelled),
/// a light grey arc spans each day from 0h to 24h with "DAY n" at its centre,
/// and each record is a small dot placed at its actual clock time — so gaps in
/// the day (and whole quiet days) read as real gaps. The rail, ticks and arcs
/// stay a neutral light grey whatever the trip's colour. A dot's time and title
/// appear only in a tooltip while the pointer is on it.
///
/// Hovering a dot reports it through [onNodeHover] (the map pans to it and the
/// records panel scrolls to it); tapping reports it through [onNodeTap] (the
/// map zooms to it and expands its bubble). [selectedEntryId] keeps the band in
/// step with the map's own selection — the selected dot is enlarged and
/// scrolled into view.
class TripTimelineBar extends StatefulWidget {
  final String tripId;

  /// The route-leg colour for a given day of the trip — passed in by the map so
  /// a day's dots carry exactly the colour of that day's route line.
  final Color Function(int day, int lastDay) dayColor;

  /// Reports a tapped dot (the map zooms to its location).
  final void Function(Entry entry)? onNodeTap;

  /// Reports the dot under the pointer, or null once the pointer leaves it.
  final void Function(Entry? entry)? onNodeHover;

  /// The record currently expanded on the map, if any.
  final String? selectedEntryId;

  /// Closes the trip (and with it this band).
  final VoidCallback? onClose;

  /// The band's height, exported so the map can lift its bottom-left controls
  /// and shorten the records panel by exactly as much as the band takes.
  static const double height = 186;

  /// Height of the strip across the top that holds the close button.
  static const double headerHeight = 47;

  const TripTimelineBar({
    super.key,
    required this.tripId,
    required this.dayColor,
    this.onNodeTap,
    this.onNodeHover,
    this.selectedEntryId,
    this.onClose,
  });

  @override
  State<TripTimelineBar> createState() => _TripTimelineBarState();
}

class _TripTimelineBarState extends State<TripTimelineBar> {
  /// Width of one hour on the axis; a day is 24 of these.
  static const double _pxPerHour = 12;

  /// Room before the first midnight and after the last, so the end labels
  /// aren't clipped by the band's edges.
  static const double _pad = 44;

  /// The rail's centre line, measured from the top of the scrolling track.
  static const double _railY = 54;

  /// How far each day's arc dips below the rail at its centre.
  static const double _arcDepth = 30;

  /// The neutral greys of the axis: rail and arcs, then the hour ticks.
  static const Color _railColor = Color(0xFFD5DAD7);
  static const Color _tickColor = Color(0xFFC3C9C6);

  final ScrollController _scroll = ScrollController();

  /// One key per dot, so the selected one can be scrolled into view.
  final Map<String, GlobalKey> _nodeKeys = {};

  @override
  void didUpdateWidget(TripTimelineBar old) {
    super.didUpdateWidget(old);
    // A record selected on the map (or in the side panel) scrolls its dot into
    // the middle of the band, so the two views never disagree about where you
    // are in the trip.
    if (widget.selectedEntryId != old.selectedEntryId ||
        widget.tripId != old.tripId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
    }
  }

  void _revealSelected() {
    if (!mounted) return;
    final key = _nodeKeys[widget.selectedEntryId];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  /// A mouse wheel over the band scrolls it sideways. Flutter only maps a
  /// vertical wheel onto a vertical scrollable, which on the web would leave
  /// the timeline unscrollable for anyone without a trackpad.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (event.scrollDelta.dx != 0 || !_scroll.hasClients) return;
    final target = (_scroll.offset + event.scrollDelta.dy)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.jumpTo(target);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = context.watch<AppState>();

    final trip = appState.trips.where((t) => t.id == widget.tripId).firstOrNull;
    if (trip == null) return const SizedBox.shrink();

    // Oldest first: a timeline reads forwards, unlike the newest-first list.
    final entries = appState.entriesForTrip(widget.tripId).reversed.toList();

    return Material(
      elevation: 6,
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text('这趟旅途还没有记录',
                        style: TextStyle(color: theme.hintColor)))
                : Listener(
                    onPointerSignal: _onPointerSignal,
                    // A thin light-grey thumb in place of the platform
                    // scrollbar (no arrow buttons, whatever the theme).
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context)
                          .copyWith(scrollbars: false),
                      child: RawScrollbar(
                        controller: _scroll,
                        thumbColor: _railColor,
                        thickness: 6,
                        radius: const Radius.circular(3),
                        child: SingleChildScrollView(
                          controller: _scroll,
                          scrollDirection: Axis.horizontal,
                          child: _track(theme, entries, trip.startDate,
                              trip.endDate),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Just the close button: the trip's name and dates are already at the top
  /// of the records panel beside it.
  Widget _header() {
    return SizedBox(
      height: TripTimelineBar.headerHeight,
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (widget.onClose != null)
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: '关闭',
                visualDensity: VisualDensity.compact,
                onPressed: widget.onClose,
              ),
          ],
        ),
      ),
    );
  }

  /// The whole axis as one fixed-width stack: the grey rail with an hour tick
  /// every hour, a grey arc per day labelled "DAY n", and a dot at each
  /// record's time.
  Widget _track(ThemeData theme, List<Entry> entries, DateTime start,
      DateTime? end) {
    const dayLen = 24 * _pxPerHour;
    double x(int day, [double hours = 0]) =>
        _pad + (day - 1) * dayLen + hours * _pxPerHour;

    // Dot colours follow the map: the same per-day route colour.
    final lastDay =
        entries.map((e) => dayIndexInTrip(e.timestamp, start)).reduce(
              (a, b) => a > b ? a : b,
            );
    // Every day of the trip gets its span — quiet days included — out to the
    // trip's end (or its latest record, for a trip that's still running).
    final totalDays = end == null
        ? lastDay
        : (dayIndexInTrip(end, start) > lastDay
            ? dayIndexInTrip(end, start)
            : lastDay);

    final children = <Widget>[
      // Rail and day arcs, painted in one go under everything else.
      Positioned.fill(
        child: CustomPaint(
          painter: _AxisPainter(
            days: totalDays,
            x: x,
            railY: _railY,
            arcDepth: _arcDepth,
            rail: _railColor,
            tick: _tickColor,
          ),
        ),
      ),
    ];

    for (var d = 1; d <= totalDays; d++) {
      for (final h in const [6, 12, 18]) {
        children.add(Positioned(
          left: x(d, h.toDouble()) - 12,
          top: _railY - 22,
          width: 24,
          child: Text('$h',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9, color: theme.hintColor)),
        ));
      }
      // "DAY n" sits on the arc's lowest point, on a patch of surface so the
      // arc breaks around it.
      children.add(Positioned(
        left: x(d) + dayLen / 2 - 40,
        top: _railY + _arcDepth - 8,
        width: 80,
        height: 16,
        child: Center(
          child: Container(
            color: theme.colorScheme.surface,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text('DAY $d',
                style: TextStyle(
                    fontSize: 12, height: 1.3, color: theme.hintColor)),
          ),
        ),
      ));
    }

    const hit = _TimelineDot.hitSize;
    for (final e in entries) {
      final day = dayIndexInTrip(e.timestamp, start);
      final hours = e.timestamp.hour + e.timestamp.minute / 60;
      children.add(Positioned(
        key: _nodeKeys.putIfAbsent(e.id, GlobalKey.new),
        left: x(day, hours) - hit / 2,
        top: _railY - hit / 2,
        width: hit,
        height: hit,
        child: _TimelineDot(
          entry: e,
          color: widget.dayColor(day, lastDay),
          selected: e.id == widget.selectedEntryId,
          onTap: widget.onNodeTap == null ? null : () => widget.onNodeTap!(e),
          onHover: widget.onNodeHover,
        ),
      ));
    }

    return SizedBox(
      width: x(totalDays + 1) + _pad,
      child: Stack(clipBehavior: Clip.none, children: children),
    );
  }
}

/// Paints the time axis itself: the rail across every day, a tick per hour
/// (midnight and 6/12/18 longer), and one shallow arc per day from its 0h to
/// its 24h, dipping below the rail.
class _AxisPainter extends CustomPainter {
  final int days;
  final double Function(int day, [double hours]) x;
  final double railY;
  final double arcDepth;
  final Color rail;
  final Color tick;

  _AxisPainter({
    required this.days,
    required this.x,
    required this.railY,
    required this.arcDepth,
    required this.rail,
    required this.tick,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final railPaint = Paint()
      ..color = rail
      ..strokeWidth = 1;
    final tickPaint = Paint()
      ..color = tick
      ..strokeWidth = 1;
    final arcPaint = Paint()
      ..color = rail
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawLine(Offset(x(1), railY), Offset(x(days + 1), railY), railPaint);
    for (var d = 1; d <= days; d++) {
      for (var h = 0; h < 24; h++) {
        final major = h % 6 == 0;
        final half = major ? 3.5 : 2.0;
        final hx = x(d, h.toDouble());
        canvas.drawLine(
            Offset(hx, railY - half), Offset(hx, railY + half), tickPaint);
      }
      final x0 = x(d), x1 = x(d + 1);
      // A quadratic curve whose control point sits at twice the depth reaches
      // exactly [arcDepth] below the rail at its midpoint.
      canvas.drawPath(
        Path()
          ..moveTo(x0, railY)
          ..quadraticBezierTo((x0 + x1) / 2, railY + 2 * arcDepth, x1, railY),
        arcPaint,
      );
    }
    final end = x(days + 1);
    canvas.drawLine(
        Offset(end, railY - 3.5), Offset(end, railY + 3.5), tickPaint);
  }

  @override
  bool shouldRepaint(_AxisPainter old) =>
      old.days != days || old.rail != rail || old.tick != tick;
}

/// One record on the timeline: a tiny dot that springs up in size while the
/// pointer is on it (the hit area is a little wider than the dot itself) and
/// shows the record's time and title in a tooltip. Hovering the label area
/// does nothing — only the dot's own neighbourhood reacts.
class _TimelineDot extends StatefulWidget {
  static const double hitSize = 22;
  static const double size = 12;
  static const double selectedSize = 13;
  static const double hoverScale = 1.8;

  final Entry entry;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;
  final void Function(Entry? entry)? onHover;

  const _TimelineDot({
    required this.entry,
    required this.color,
    required this.selected,
    this.onTap,
    this.onHover,
  });

  @override
  State<_TimelineDot> createState() => _TimelineDotState();
}

class _TimelineDotState extends State<_TimelineDot> {
  bool _hovered = false;

  void _setHovered(bool on) {
    if (_hovered == on) return;
    setState(() => _hovered = on);
    widget.onHover?.call(on ? widget.entry : null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = widget.entry;
    final d = widget.selected ? _TimelineDot.selectedSize : _TimelineDot.size;

    return Tooltip(
      richMessage: TextSpan(children: [
        TextSpan(
          text: '${DateFormat('HH:mm').format(e.timestamp)}\n',
          style: TextStyle(fontSize: 11, color: theme.hintColor, height: 1.3),
        ),
        TextSpan(
          text: e.displayTitle,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
              height: 1.35),
        ),
      ]),
      preferBelow: false,
      verticalOffset: 14,
      waitDuration: Duration.zero,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Center(
            child: AnimatedScale(
              scale: _hovered ? _TimelineDot.hoverScale : 1,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutBack,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: d,
                height: d,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: widget.selected ? 1.5 : 1,
                  ),
                  boxShadow: widget.selected
                      ? [
                          BoxShadow(color: widget.color, spreadRadius: 1),
                          BoxShadow(
                            color: widget.color.withValues(alpha: 0.45),
                            blurRadius: 5,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
