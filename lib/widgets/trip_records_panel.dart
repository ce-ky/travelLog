import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/entry.dart';
import '../state/app_state.dart';
import 'entry_grouped_list.dart';

/// A self-contained panel that lists every record of one trip, newest first.
///
/// It's the right-hand pane of the two-pane trips view and the side panel the
/// map opens when a trip bubble is tapped — clicking a trip shows only that
/// trip's records here, in place, without a full-screen navigation.
class TripRecordsPanel extends StatelessWidget {
  final String tripId;

  /// When provided, a close button is shown in the header.
  final VoidCallback? onClose;

  /// When provided, tapping a record reports it (the map zooms to its location).
  final void Function(Entry entry)? onRecordTap;

  const TripRecordsPanel({
    super.key,
    required this.tripId,
    this.onClose,
    this.onRecordTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = context.watch<AppState>();

    final trip = appState.trips.where((t) => t.id == tripId).firstOrNull;
    if (trip == null) {
      return _centeredHint(theme, Icons.inbox_outlined, '这趟旅途已不存在');
    }

    final entries = appState.entriesForTrip(tripId);
    final fmt = DateFormat('yyyy.MM.dd');
    final dates = trip.endDate == null
        ? '${fmt.format(trip.startDate)} 起 · 进行中'
        : '${fmt.format(trip.startDate)} – ${fmt.format(trip.endDate!)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(trip.title, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text('$dates · ${entries.length} 条记录',
                        style: TextStyle(
                            fontSize: 12, color: theme.hintColor)),
                  ],
                ),
              ),
              if (onClose != null)
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '关闭',
                  onPressed: onClose,
                ),
            ],
          ),
        ),
        // A faint hairline instead of a full-strength divider, so the header
        // reads as part of one clean surface rather than a boxed-off section.
        Divider(height: 1, thickness: 1, color: theme.dividerColor.withValues(alpha: 0.4)),
        Expanded(
          child: entries.isEmpty
              ? _centeredHint(theme, Icons.notes_outlined, '这趟旅途还没有记录')
              : EntryGroupedList(entries: entries, onEntryTap: onRecordTap),
        ),
      ],
    );
  }

  Widget _centeredHint(ThemeData theme, IconData icon, String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: theme.hintColor),
          const SizedBox(height: 10),
          Text(text, style: TextStyle(color: theme.hintColor)),
        ],
      ),
    );
  }
}
