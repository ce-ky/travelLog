import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/entry.dart';
import 'entry_card.dart';

/// A scrollable list of [EntryCard]s grouped under "yyyy年M月" month headers.
/// Shared by the trip detail screen and the trip-records side panel.
class EntryGroupedList extends StatelessWidget {
  final List<Entry> entries;
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
    this.padding = const EdgeInsets.only(bottom: 12),
    this.onEntryTap,
    this.selectedEntryId,
  });

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Entry>>{};
    for (final e in entries) {
      final key = DateFormat('yyyy年M月').format(e.timestamp);
      groups.putIfAbsent(key, () => []).add(e);
    }

    final children = <Widget>[];
    groups.forEach((month, items) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(month,
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.grey)),
      ));
      children.addAll(items.map((e) => EntryCard(
            entry: e,
            onTap: onEntryTap == null ? null : () => onEntryTap!(e),
            selected: e.id == selectedEntryId,
          )));
    });

    return ListView(padding: padding, children: children);
  }
}
