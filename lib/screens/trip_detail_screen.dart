import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/entry.dart';
import '../models/entry_type.dart';
import '../models/trip.dart';
import '../state/app_state.dart';
import '../widgets/entry_card.dart';
import 'new_trip_sheet.dart';

/// Everything for one trip: its dates and companions in a header, then all of
/// its records, with an optional per-type filter.
class TripDetailScreen extends StatefulWidget {
  final String tripId;
  const TripDetailScreen({super.key, required this.tripId});

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  final Set<EntryType> _typeFilter = {};

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    // The trip may have been deleted (from here or elsewhere) — leave if so.
    final trip =
        appState.trips.where((t) => t.id == widget.tripId).firstOrNull;
    if (trip == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    var entries = appState.entriesForTrip(trip.id);
    if (_typeFilter.isNotEmpty) {
      entries = entries.where((e) => _typeFilter.contains(e.type)).toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(trip.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑旅途',
            onPressed: () => NewTripSheet.show(context, initial: trip),
          ),
        ],
      ),
      body: Column(
        children: [
          _TripHeader(trip: trip),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final type in EntryType.values)
                  FilterChip(
                    avatar: Icon(type.icon, size: 18),
                    label: Text(type.label),
                    selected: _typeFilter.contains(type),
                    onSelected: (on) => setState(() {
                      on ? _typeFilter.add(type) : _typeFilter.remove(type);
                    }),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: entries.isEmpty
                ? const Center(child: Text('这趟旅途还没有记录'))
                : _GroupedList(entries: entries),
          ),
        ],
      ),
    );
  }
}

class _TripHeader extends StatelessWidget {
  final Trip trip;
  const _TripHeader({required this.trip});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('yyyy.MM.dd');
    final dates = trip.endDate == null
        ? '${fmt.format(trip.startDate)} 起 · 进行中'
        : '${fmt.format(trip.startDate)} – ${fmt.format(trip.endDate!)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event, size: 16, color: theme.hintColor),
              const SizedBox(width: 6),
              Text(dates, style: TextStyle(color: theme.hintColor)),
            ],
          ),
          if (trip.companions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.people_outline, size: 16, color: theme.hintColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    trip.companions.map((p) => p.name).join('、'),
                    style: TextStyle(color: theme.hintColor),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Groups entries by "yyyy年M月" headers.
class _GroupedList extends StatelessWidget {
  final List<Entry> entries;
  const _GroupedList({required this.entries});

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

    return ListView(children: children);
  }
}
