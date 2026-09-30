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
/// is one 24-hour span of equal width, that day's date pill sits on its
/// midnight, and each record is a small dot placed at its actual clock time —
/// so gaps in the day (and whole quiet days) read as real gaps. A dot's time
/// and title appear only in a tooltip while the pointer is on it.
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

  /// False collapses the band to its header strip, freeing the map.
  final bool expanded;

  final VoidCallback? onToggleExpanded;

  /// Closes the trip (and with it this band).
  final VoidCallback? onClose;

  /// Band heights, exported so the map can lift its bottom-left controls and
  /// shorten the records panel by exactly as much as the band takes.
  static const double expandedHeight = 186;
  static const double collapsedHeight = 47;

  const TripTimelineBar({
    super.key,
    required this.tripId,
    required this.dayColor,
    this.onNodeTap,
    this.onNodeHover,
    this.selectedEntryId,
    this.expanded = true,
    this.onToggleExpanded,
    this.onClose,
  });

  @override
  State<TripTimelineBar> createState() => _TripTimelineBarState();
}

class _TripTimelineBarState extends State<TripTimelineBar> {
  /// Width of one hour on the axis; a day is 24 of these.
  static const double _pxPerHour = 12;

  /// Room before the first midnight and after the last, so the end pills
  /// aren't clipped by the band's edges.
  static const double _pad = 44;

  /// Top of the marker row, and the rail's centre line within it.
  static const double _rowTop = 8;
  static const double _railY = _rowTop + 18;

  /// Hours that get a small tick (and label) on the rail.
  static const _tickHours = [6, 12, 18];

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
    if (!mounted || !widget.expanded) return;
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
          if (widget.expanded) ...[
            Divider(
                height: 1,
                thickness: 1,
                color: theme.dividerColor.withValues(alpha: 0.4)),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text('这趟旅途还没有记录',
                          style: TextStyle(color: theme.hintColor)))
                  : Listener(
                      onPointerSignal: _onPointerSignal,
                      child: SingleChildScrollView(
                        controller: _scroll,
                        scrollDirection: Axis.horizontal,
                        child: _track(theme, entries, trip.startDate,
                            trip.endDate),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  /// Just the band's controls: the trip's name and dates are already at the top
  /// of the records panel beside it.
  Widget _header() {
    return SizedBox(
      height: TripTimelineBar.collapsedHeight,
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (widget.onToggleExpanded != null)
              IconButton(
                icon: Icon(widget.expanded
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_up),
                tooltip: widget.expanded ? '收起时间线' : '展开时间线',
                visualDensity: VisualDensity.compact,
                onPressed: widget.onToggleExpanded,
              ),
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

  /// The whole axis as one fixed-width stack: a rail segment per day in that
  /// day's route colour, hour ticks, a date pill on every midnight, and a dot
  /// at each record's time.
  Widget _track(ThemeData theme, List<Entry> entries, DateTime start,
      DateTime? end) {
    const dayLen = 24 * _pxPerHour;
    double x(int day, [double hours = 0]) =>
        _pad + (day - 1) * dayLen + hours * _pxPerHour;

    // Colours follow the map: day 1 palest, the last day with records deepest.
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
    Color colorOf(int day) =>
        widget.dayColor(day > lastDay ? lastDay : day, lastDay);

    final surface = theme.colorScheme.surface;
    final children = <Widget>[];

    for (var d = 1; d <= totalDays; d++) {
      final c = colorOf(d);
      children.add(Positioned(
        left: x(d),
        top: _railY - 0.5,
        width: dayLen,
        height: 1,
        child: ColoredBox(color: c.withValues(alpha: 0.8)),
      ));
      for (final h in _tickHours) {
        children
          ..add(Positioned(
            left: x(d, h.toDouble()) - 0.5,
            top: _railY - 3,
            width: 1,
            height: 6,
            child: ColoredBox(color: c),
          ))
          ..add(Positioned(
            left: x(d, h.toDouble()) - 12,
            top: 6,
            width: 24,
            child: Text('$h',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 9, color: theme.hintColor)),
          ));
      }
    }

    for (var d = 1; d <= totalDays; d++) {
      final date = DateTime(start.year, start.month, start.day + d - 1);
      children.add(Positioned(
        left: x(d) - 40,
        top: _rowTop,
        width: 80,
        child: _dayMarker(theme, d, date, colorOf(d), surface),
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
          color: colorOf(day),
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

  /// A day's midnight: its date as an opaque pill sitting on the rail (so the
  /// rail doesn't show through it), and 第N天 beneath.
  Widget _dayMarker(
      ThemeData theme, int day, DateTime date, Color color, Color surface) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 36,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                // Pre-mixed onto the band's surface rather than translucent.
                color: Color.alphaBlend(color.withValues(alpha: 0.16), surface),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                    color: Color.alphaBlend(
                        color.withValues(alpha: 0.55), surface)),
              ),
              child: Text(DateFormat('MM-dd').format(date),
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: _readable(theme, color))),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text('第$day天',
            style: TextStyle(fontSize: 11, color: theme.hintColor)),
      ],
    );
  }

  /// The day colour is tuned for a route line on a map; darken the pale end of
  /// it so the date stays readable as text on the panel's surface.
  Color _readable(ThemeData theme, Color color) {
    final hsl = HSLColor.fromColor(color);
    if (theme.brightness == Brightness.dark) return color;
    return hsl.lightness <= 0.45
        ? color
        : hsl.withLightness(0.35).toColor();
  }
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
