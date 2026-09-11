import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/entry.dart';
import '../state/app_state.dart';
import 'entry_card.dart';

/// A scrollable list of [EntryCard]s grouped under "第N天" day-of-trip
/// headers (day 1 = [tripStart]), each day chronological and days ascending —
/// so the list reads as an itinerary. Shared by the trip detail screen and
/// the trip-records side panel.
class EntryGroupedList extends StatelessWidget {
  final List<Entry> entries;
  final DateTime tripStart;
  final EdgeInsetsGeometry padding;

  /// When set, each card becomes tappable and reports its entry (used by the
  /// map's records panel to zoom the map to that record).
  final void Function(Entry entry)? onEntryTap;

  /// The id of the record currently expanded on the map, if any — that card is
  /// shown highlighted so the list tracks the map's selection.
  final String? selectedEntryId;

  const EntryGroupedList({
    super.key,
    required this.entries,
    required this.tripStart,
    this.padding = const EdgeInsets.only(bottom: 12),
    this.onEntryTap,
    this.selectedEntryId,
  });

  @override
  Widget build(BuildContext context) {
    final groups = <int, List<Entry>>{};
    for (final e in entries) {
      final day = dayIndexInTrip(e.timestamp, tripStart);
      groups.putIfAbsent(day, () => []).add(e);
    }
    final days = groups.keys.toList()..sort();
    final fmt = DateFormat('M月d日');

    final children = <Widget>[];
    for (final day in days) {
      final items = groups[day]!..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text('第$day天 · ${fmt.format(items.first.timestamp)}',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.grey)),
      ));
      children.addAll(items.map((e) => EntryCard(
            key: ValueKey(e.id),
            entry: e,
            onTap: onEntryTap == null ? null : () => onEntryTap!(e),
            selected: e.id == selectedEntryId,
          )));
    }

    return ListView(padding: padding, children: children);
  }
}
