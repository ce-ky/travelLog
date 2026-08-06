import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/entry_type.dart';
import '../state/app_state.dart';
import '../widgets/entry_card.dart';

/// View 3: entries filtered by record type (place / photo / drawing /
/// story / essay) via toggle chips.
class TypeListScreen extends StatelessWidget {
  const TypeListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final entries = appState.filteredEntries;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final type in EntryType.values)
                FilterChip(
                  avatar: Icon(type.icon, size: 18),
                  label: Text(type.label),
                  selected: appState.typeFilter.contains(type),
                  onSelected: (_) => appState.toggleType(type),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('没有符合条件的记录'))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (_, i) => EntryCard(entry: entries[i]),
                ),
        ),
      ],
    );
  }
}
