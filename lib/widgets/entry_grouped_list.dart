import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/entry.dart';
import 'entry_card.dart';

/// A scrollable list of [EntryCard]s grouped under "yyyy年M月" month headers.
/// Shared by the trip detail screen and the trip-records side panel.
class EntryGroupedList extends StatelessWidget {
  final List<Entry> entries;
  final EdgeInsetsGeometry padding;

  const EntryGroupedList({
    super.key,
    required this.entries,
    this.padding = const EdgeInsets.only(bottom: 12),
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
      children.addAll(items.map((e) => EntryCard(entry: e)));
    });

    return ListView(padding: padding, children: children);
  }
}
