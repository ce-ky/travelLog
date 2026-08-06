import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/entry.dart';
import '../state/app_state.dart';
import '../widgets/entry_card.dart';
import 'new_trip_sheet.dart';

/// View 2: a list of entries filtered by time / trip / companion,
/// grouped by month.
class FilterListScreen extends StatelessWidget {
  const FilterListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    if (appState.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (appState.error != null) {
      return _ErrorState(
        error: appState.error!,
        onRetry: appState.refresh,
      );
    }
    // A brand new account has no trips at all — say where to start rather than
    // showing an empty list that looks broken.
    if (appState.trips.isEmpty) {
      return const _NoTripsState();
    }

    final entries = appState.filteredEntries;

    return Column(
      children: [
        _FilterBar(appState: appState),
        const Divider(height: 1),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('没有符合条件的记录'))
              : _GroupedList(entries: entries),
        ),
      ],
    );
  }
}

class _NoTripsState extends StatelessWidget {
  const _NoTripsState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.luggage_outlined, size: 56, color: theme.hintColor),
            const SizedBox(height: 16),
            Text('还没有旅途', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '每条记录都要归属于一趟旅途，\n先创建一趟再开始记录吧。',
              textAlign: TextAlign.center,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => NewTripSheet.show(context),
              icon: const Icon(Icons.add),
              label: const Text('新建旅途'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: theme.hintColor),
            const SizedBox(height: 14),
            Text('加载失败', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final AppState appState;
  const _FilterBar({required this.appState});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Trip filter
          _Dropdown<String?>(
            hint: '旅途',
            value: appState.tripFilter,
            items: [
              const DropdownMenuItem(value: null, child: Text('全部旅途')),
              for (final t in appState.trips)
                DropdownMenuItem(value: t.id, child: Text(t.title)),
            ],
            onChanged: appState.setTripFilter,
          ),
          const SizedBox(width: 8),
          // Companion filter
          _Dropdown<String?>(
            hint: '同行人',
            value: appState.companionFilter,
            items: [
              const DropdownMenuItem(value: null, child: Text('所有人')),
              for (final p in appState.people)
                DropdownMenuItem(value: p.id, child: Text(p.name)),
            ],
            onChanged: appState.setCompanionFilter,
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: appState.clearFilters,
            icon: const Icon(Icons.clear, size: 16),
            label: const Text('清除'),
          ),
        ],
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  final String hint;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _Dropdown({
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(20),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint),
          items: items,
          onChanged: onChanged,
        ),
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
