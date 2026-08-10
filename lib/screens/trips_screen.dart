import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/trip.dart';
import '../state/app_state.dart';
import '../widgets/trip_records_panel.dart';
import 'new_trip_sheet.dart';
import 'trip_detail_screen.dart';

/// View 2: trips as cards. On a wide window it's a two-pane master–detail —
/// clicking a trip on the left shows only that trip's records on the right, in
/// place. On a phone, tapping a trip opens its records full-screen instead.
class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  /// The trip whose records fill the right pane (wide layout only).
  String? _selectedTripId;

  /// Below this width there's no room for a side pane; tapping navigates.
  static const double _twoPaneBreakpoint = 720;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    if (appState.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (appState.error != null) {
      return _ErrorState(error: appState.error!, onRetry: appState.refresh);
    }
    if (appState.trips.isEmpty) {
      return const _NoTripsState();
    }

    final trips = [...appState.trips]
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
    final wide = MediaQuery.sizeOf(context).width >= _twoPaneBreakpoint;

    // A selection that points at a since-deleted trip should fall back to none.
    if (_selectedTripId != null &&
        !trips.any((t) => t.id == _selectedTripId)) {
      _selectedTripId = null;
    }

    final list = _tripList(trips, wide);
    if (!wide) return list;

    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 360, child: list),
        VerticalDivider(width: 1, color: theme.dividerColor),
        Expanded(
          child: _selectedTripId == null
              ? _pickPrompt(theme)
              : TripRecordsPanel(tripId: _selectedTripId!),
        ),
      ],
    );
  }

  Widget _tripList(List<Trip> trips, bool wide) {
    // Row 0 is the "new trip" affordance; the rest are the trip cards.
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: trips.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return const _NewTripRow();
        final trip = trips[i - 1];
        return _TripCard(
          trip: trip,
          selected: wide && trip.id == _selectedTripId,
          onTap: () => _openTrip(trip, wide),
        );
      },
    );
  }

  void _openTrip(Trip trip, bool wide) {
    if (wide) {
      setState(() => _selectedTripId = trip.id);
      return;
    }
    // Phone: no side pane, so open the trip's records full-screen.
    final appState = context.read<AppState>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: appState,
          child: TripDetailScreen(tripId: trip.id),
        ),
      ),
    );
  }

  Widget _pickPrompt(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app_outlined, size: 44, color: theme.hintColor),
          const SizedBox(height: 12),
          Text('点击左侧的旅途，查看它的全部记录',
              style: TextStyle(color: theme.hintColor)),
        ],
      ),
    );
  }
}

/// A card that reads as an empty slot: tap it to create a trip. Replaces the
/// old bottom-right FAB with an in-list affordance at the top of the list.
class _NewTripRow extends StatelessWidget {
  const _NewTripRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Material(
        color: accent.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => NewTripSheet.show(context),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, color: accent),
                const SizedBox(width: 8),
                Text('新建旅途',
                    style: TextStyle(
                        color: accent, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final Trip trip;
  final bool selected;
  final VoidCallback onTap;

  const _TripCard({
    required this.trip,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final theme = Theme.of(context);
    final fmt = DateFormat('yyyy.MM.dd');
    final count = appState.entryCountForTrip(trip.id);

    final dates = trip.endDate == null
        ? '${fmt.format(trip.startDate)} 起 · 进行中'
        : '${fmt.format(trip.startDate)} – ${fmt.format(trip.endDate!)}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      // Highlight the trip whose records fill the right pane.
      color: selected ? theme.colorScheme.secondaryContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(trip.title,
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    // Wrap (not Row) so the date + count metrics fall to a second
                    // line instead of overflowing in the narrow two-pane list.
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        _MetaChip(
                          icon: Icons.event,
                          text: dates,
                          color: theme.hintColor,
                        ),
                        _MetaChip(
                          icon: Icons.notes,
                          text: '$count 条记录',
                          color: theme.hintColor,
                        ),
                      ],
                    ),
                    if (trip.companions.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.people_outline,
                              size: 14, color: theme.hintColor),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              trip.companions.map((p) => p.name).join('、'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: theme.hintColor),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              _TripMenu(trip: trip),
            ],
          ),
        ),
      ),
    );
  }
}

enum _TripAction { rename, edit, delete }

class _TripMenu extends StatelessWidget {
  final Trip trip;
  const _TripMenu({required this.trip});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_TripAction>(
      icon: const Icon(Icons.more_vert),
      onSelected: (action) {
        switch (action) {
          case _TripAction.rename:
            _rename(context);
          case _TripAction.edit:
            NewTripSheet.show(context, initial: trip);
          case _TripAction.delete:
            _confirmDelete(context);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: _TripAction.rename,
          child: ListTile(
            leading: Icon(Icons.drive_file_rename_outline),
            title: Text('重命名'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _TripAction.edit,
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('编辑人和时间'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _TripAction.delete,
          child: ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('删除'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Future<void> _rename(BuildContext context) async {
    final appState = context.read<AppState>();
    final controller = TextEditingController(text: trip.title);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名旅途'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '旅途名称'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == trip.title) return;

    await appState.addTrip(Trip(
      id: trip.id,
      title: name,
      startDate: trip.startDate,
      endDate: trip.endDate,
      coverImagePath: trip.coverImagePath,
      companions: trip.companions,
    ));
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final appState = context.read<AppState>();
    final count = appState.entryCountForTrip(trip.id);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除旅途'),
        content: Text(count == 0
            ? '确定删除「${trip.title}」吗？'
            : '「${trip.title}」下的 $count 条记录也会一并删除，确定吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) await appState.removeTrip(trip.id);
  }
}

/// A single icon + label metric, kept intact as a unit inside a [Wrap] so it
/// never splits across a line break.
class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _MetaChip({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        // Flexible + ellipsis so a long label shrinks to the pane instead of
        // overflowing when the two-pane list is narrow.
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: color)),
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
            Text('$error',
                textAlign: TextAlign.center,
                style:
                    theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
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
