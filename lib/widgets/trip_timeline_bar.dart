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
/// answers "in what order did it happen" — every record of the trip laid out
/// left to right in time order, split by day, so a whole trip reads as one
/// sequence. It only exists while a trip is selected: closing the trip closes
/// the band with it.
///
/// Tapping a node reports it through [onNodeTap] (the map zooms to that record
/// and expands its bubble), and [selectedEntryId] keeps the band in step with
/// the map's own selection — the selected node is enlarged and scrolled into
/// view.
class TripTimelineBar extends StatefulWidget {
  final String tripId;

  /// The trip's route colour, so the band reads as part of that trip.
  final Color accent;

  /// The route-leg colour for a given day of the trip — passed in by the map so
  /// a day's nodes carry exactly the colour of that day's route line.
  final Color Function(int day, int lastDay) dayColor;

  /// Reports a tapped node (the map zooms to its location).
  final void Function(Entry entry)? onNodeTap;

  /// The record currently expanded on the map, if any.
  final String? selectedEntryId;

  /// False collapses the band to its header strip, freeing the map.
  final bool expanded;

  final VoidCallback? onToggleExpanded;

  /// Closes the trip (and with it this band).
  final VoidCallback? onClose;

  /// Band heights, exported so the map can lift its bottom-left controls and
  /// shorten the records panel by exactly as much as the band takes.
  static const double expandedHeight = 148;
  static const double collapsedHeight = 44;

  const TripTimelineBar({
    super.key,
    required this.tripId,
    required this.accent,
    required this.dayColor,
    this.onNodeTap,
    this.selectedEntryId,
    this.expanded = true,
    this.onToggleExpanded,
    this.onClose,
  });

  @override
  State<TripTimelineBar> createState() => _TripTimelineBarState();
}

class _TripTimelineBarState extends State<TripTimelineBar> {
  final ScrollController _scroll = ScrollController();

  /// One key per node, so the selected one can be scrolled into view.
  final Map<String, GlobalKey> _nodeKeys = {};

  @override
  void didUpdateWidget(TripTimelineBar old) {
    super.didUpdateWidget(old);
    // A record selected on the map (or in the side panel) scrolls its node into
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
          _header(theme, trip.title, entries.length),
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
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _cells(theme, entries, trip.startDate),
                        ),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _header(ThemeData theme, String title, int count) {
    return SizedBox(
      height: TripTimelineBar.collapsedHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 6, 0),
        child: Row(
          children: [
            Icon(Icons.timeline, size: 18, color: widget.accent),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '$title · 时间线',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            Text('$count 个节点',
                style: TextStyle(fontSize: 11, color: theme.hintColor)),
            const Spacer(),
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

  /// The band's contents as one flat row: a day marker in front of each day's
  /// nodes, and the rail drawn through every cell so the whole trip reads as a
  /// single line (open at neither end, closed at both).
  List<Widget> _cells(ThemeData theme, List<Entry> entries, DateTime start) {
    final groups = <int, List<Entry>>{};
    for (final e in entries) {
      groups.putIfAbsent(dayIndexInTrip(e.timestamp, start), () => []).add(e);
    }
    final days = groups.keys.toList()..sort();
    final lastDay = days.last;

    // Build the cells first, then hand each its position, so the rail can stop
    // at the first and last cell instead of running off both ends.
    final specs = <(int day, Entry? entry)>[];
    for (final day in days) {
      specs.add((day, null));
      for (final e in groups[day]!) {
        specs.add((day, e));
      }
    }

    return [
      for (var i = 0; i < specs.length; i++)
        if (specs[i].$2 == null)
          _dayCell(
            theme,
            day: specs[i].$1,
            date: groups[specs[i].$1]!.first.timestamp,
            color: widget.dayColor(specs[i].$1, lastDay),
            first: i == 0,
            last: i == specs.length - 1,
          )
        else
          _nodeCell(
            theme,
            entry: specs[i].$2!,
            color: widget.dayColor(specs[i].$1, lastDay),
            first: i == 0,
            last: i == specs.length - 1,
          ),
    ];
  }

  Widget _dayCell(
    ThemeData theme, {
    required int day,
    required DateTime date,
    required Color color,
    required bool first,
    required bool last,
  }) {
    return SizedBox(
      width: 78,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          _rail(
            first: first,
            last: last,
            color: color,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: color.withValues(alpha: 0.55)),
              ),
              child: Text('第$day天',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _readable(theme, color))),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 34,
            child: Text(DateFormat('M月d日').format(date),
                style: TextStyle(fontSize: 11, color: theme.hintColor)),
          ),
        ],
      ),
    );
  }

  Widget _nodeCell(
    ThemeData theme, {
    required Entry entry,
    required Color color,
    required bool first,
    required bool last,
  }) {
    final selected = entry.id == widget.selectedEntryId;
    final key = _nodeKeys.putIfAbsent(entry.id, GlobalKey.new);
    final d = selected ? 32.0 : 26.0;

    return SizedBox(
      key: key,
      width: 112,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: widget.onNodeTap == null ? null : () => widget.onNodeTap!(entry),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 16,
              child: Text(DateFormat('HH:mm').format(entry.timestamp),
                  style: TextStyle(fontSize: 11, color: theme.hintColor)),
            ),
            _rail(
              first: first,
              last: last,
              color: color,
              child: Container(
                width: d,
                height: d,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? theme.colorScheme.surface
                        : theme.colorScheme.surface.withValues(alpha: 0.9),
                    width: selected ? 3 : 2,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.5),
                            blurRadius: 8,
                            spreadRadius: 1,
                          )
                        ]
                      : null,
                ),
                child: Text(entry.markerGlyph,
                    style: TextStyle(fontSize: selected ? 15 : 12)),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 34,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  entry.displayTitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One cell's slice of the timeline rail: a hairline through the cell with
  /// [child] (a node dot or a day pill) sitting on it. The halves before the
  /// first cell's marker and after the last one's are left blank so the line
  /// starts and ends on a marker.
  Widget _rail({
    required bool first,
    required bool last,
    required Color color,
    required Widget child,
  }) {
    final line = color.withValues(alpha: 0.45);
    return SizedBox(
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: [
              Expanded(
                  child: Container(
                      height: 2, color: first ? Colors.transparent : line)),
              Expanded(
                  child: Container(
                      height: 2, color: last ? Colors.transparent : line)),
            ],
          ),
          child,
        ],
      ),
    );
  }

  /// The day colour is tuned for a route line on a map; darken the pale end of
  /// it so the day label stays readable as text on the panel's surface.
  Color _readable(ThemeData theme, Color color) {
    final hsl = HSLColor.fromColor(color);
    if (theme.brightness == Brightness.dark) return color;
    return hsl.lightness <= 0.45
        ? color
        : hsl.withLightness(0.35).toColor();
  }
}
