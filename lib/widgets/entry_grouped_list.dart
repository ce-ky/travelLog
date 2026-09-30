import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/entry.dart';
import '../state/app_state.dart';
import 'entry_card.dart';

/// A scrollable list of one trip's [EntryCard]s grouped under "DAY n"
/// day-of-trip headers (day 1 = [tripStart]), each day chronological and days
/// ascending — so the list reads as an itinerary. Shared by the trip detail
/// screen and the trip-records side panel; the cards leave out what those
/// headers already say (see [EntryCard.showTripContext]).
class EntryGroupedList extends StatefulWidget {
  final List<Entry> entries;
  final DateTime tripStart;
  final EdgeInsetsGeometry padding;

  /// When set, each card becomes tappable and reports its entry (used by the
  /// map's records panel to zoom the map to that record).
  final void Function(Entry entry)? onEntryTap;

  /// The id of the record currently expanded on the map, if any — that card is
  /// shown highlighted so the list tracks the map's selection.
  final String? selectedEntryId;

  /// When set, each id it reports scrolls that record's card to the middle of
  /// the list (the map drives this from the timeline). Every card is then
  /// built up front, so an off-screen one can still be scrolled to.
  final ValueListenable<String?>? reveal;

  const EntryGroupedList({
    super.key,
    required this.entries,
    required this.tripStart,
    this.padding = const EdgeInsets.only(bottom: 12),
    this.onEntryTap,
    this.selectedEntryId,
    this.reveal,
  });

  @override
  State<EntryGroupedList> createState() => _EntryGroupedListState();
}

class _EntryGroupedListState extends State<EntryGroupedList> {
  final Map<String, GlobalKey> _cardKeys = {};

  @override
  void initState() {
    super.initState();
    widget.reveal?.addListener(_onReveal);
  }

  @override
  void didUpdateWidget(EntryGroupedList old) {
    super.didUpdateWidget(old);
    if (old.reveal != widget.reveal) {
      old.reveal?.removeListener(_onReveal);
      widget.reveal?.addListener(_onReveal);
    }
  }

  @override
  void dispose() {
    widget.reveal?.removeListener(_onReveal);
    super.dispose();
  }

  void _onReveal() {
    final id = widget.reveal?.value;
    final ctx = id == null ? null : _cardKeys[id]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = <int, List<Entry>>{};
    for (final e in widget.entries) {
      final day = dayIndexInTrip(e.timestamp, widget.tripStart);
      groups.putIfAbsent(day, () => []).add(e);
    }
    final days = groups.keys.toList()..sort();

    final children = <Widget>[];
    for (final day in days) {
      final items = groups[day]!..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text('DAY $day',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.grey)),
      ));
      children.addAll(items.map((e) => EntryCard(
            key: widget.reveal == null
                ? ValueKey(e.id)
                : _cardKeys.putIfAbsent(e.id, GlobalKey.new),
            entry: e,
            onTap: widget.onEntryTap == null
                ? null
                : () => widget.onEntryTap!(e),
            selected: e.id == widget.selectedEntryId,
            showTripContext: false,
          )));
    }

    if (widget.reveal == null) {
      return ListView(padding: widget.padding, children: children);
    }
    return SingleChildScrollView(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
