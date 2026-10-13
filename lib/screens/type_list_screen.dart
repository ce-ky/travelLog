import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/entry_type.dart';
import '../state/app_state.dart';
import '../widgets/browse_filter_bar.dart';
import '../widgets/entry_card.dart';

/// View 3: entries filtered by record type (place / photo / drawing /
/// story / essay) via icon-only toggle filters.
class TypeListScreen extends StatelessWidget {
  /// Shown at the right end of the filter row (the browse mode toggle).
  final Widget? trailing;

  const TypeListScreen({super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final entries = appState.filteredEntries;

    return Column(
      children: [
        BrowseFilterBar(
          filters: [
            for (final type in EntryType.values)
              IconFilterButton(
                tooltip: type.label,
                selected: appState.typeFilter.contains(type),
                onPressed: () => appState.toggleType(type),
                child: Icon(type.icon),
              ),
          ],
          trailing: trailing,
        ),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('没有符合条件的记录'))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (_, i) => EntryCard(
                    key: ValueKey(entries[i].id),
                    entry: entries[i],
                  ),
                ),
        ),
      ],
    );
  }
}
