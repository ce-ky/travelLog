import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'browse_screen.dart';
import 'map_screen.dart';
import 'new_entry_sheet.dart';
import 'new_trip_sheet.dart';
import 'trips_screen.dart';

/// Top-level shell hosting the three main views.
///
/// On a wide (desktop) window it drops the tall app bar for a slim title strip
/// and uses a compact centred nav; on a narrow (phone) window it keeps the
/// standard Material app bar + navigation bar.
class HomeShell extends StatefulWidget {
  /// Passed through to [MapScreen]; only widget tests set it.
  final TileProvider? mapTileProvider;

  /// Shows the exit action when there is a session (or a sample run) to leave.
  final VoidCallback? onSignOut;

  const HomeShell({super.key, this.mapTileProvider, this.onSignOut});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _titles = ['地图', '旅途', '浏览'];

  /// Below this width we treat the window as a phone.
  static const _desktopBreakpoint = 720.0;

  late final _screens = [
    MapScreen(tileProvider: widget.mapTileProvider),
    const TripsScreen(),
    const BrowseScreen(),
  ];

  void _select(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;
    // expand: children that fill (the map's Stack, the trips ListView) collapse
    // to zero under IndexedStack's default loose constraints, so force them to
    // fill the body.
    final body = IndexedStack(
      sizing: StackFit.expand,
      index: _index,
      children: _screens,
    );

    return Scaffold(
      // Desktop swaps the tall Material app bar for a slim title strip, but
      // keeps the body as a plain IndexedStack so its children size normally.
      appBar: desktop
          ? PreferredSize(
              preferredSize: const Size.fromHeight(50),
              child: _DesktopHeader(
                section: _titles[_index],
                onSignOut: widget.onSignOut,
              ),
            )
          : AppBar(
              title: Text(_titles[_index]),
              centerTitle: true,
              actions: [
                if (widget.onSignOut != null)
                  IconButton(
                    icon: const Icon(Icons.logout),
                    tooltip: '退出',
                    onPressed: widget.onSignOut,
                  ),
              ],
            ),
      body: body,
      // The trips tab creates trips from a row at the top of its list, so it
      // has no FAB. The map/type tabs add a record — icon only, no label.
      floatingActionButton: _index == 1
          ? null
          : FloatingActionButton(
              tooltip: '新增记录',
              onPressed: _createEntry,
              child: const Icon(Icons.add),
            ),
      bottomNavigationBar: desktop
          ? _DesktopNavBar(index: _index, onSelect: _select)
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _select,
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.map_outlined),
                    selectedIcon: Icon(Icons.map),
                    label: '地图'),
                NavigationDestination(
                    icon: Icon(Icons.list_alt_outlined),
                    selectedIcon: Icon(Icons.list_alt),
                    label: '旅途'),
                NavigationDestination(
                    icon: Icon(Icons.explore_outlined),
                    selectedIcon: Icon(Icons.explore),
                    label: '浏览'),
              ],
            ),
    );
  }

  Future<void> _createEntry() async {
    // Every entry belongs to a trip; steer the user to make one first.
    if (context.read<AppState>().trips.isEmpty) {
      final created = await NewTripSheet.show(context);
      if (!created) return;
    }
    if (!mounted) return;

    final created = await NewEntrySheet.show(context);
    if (created && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('记录已保存')),
      );
    }
  }
}

/// Slim desktop title strip: app name + current section on the left, exit on
/// the right — a fraction of the height of a Material app bar.
class _DesktopHeader extends StatelessWidget {
  final String section;
  final VoidCallback? onSignOut;

  const _DesktopHeader({required this.section, this.onSignOut});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 10, 8),
      child: Row(
        children: [
          Text('旅行日志',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(width: 10),
          Text(section,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.hintColor)),
          const Spacer(),
          if (onSignOut != null)
            IconButton(
              icon: const Icon(Icons.logout, size: 20),
              tooltip: '退出',
              visualDensity: VisualDensity.compact,
              onPressed: onSignOut,
            ),
        ],
      ),
    );
  }
}

/// Compact, centred bottom nav for desktop — selected item shows a pill.
class _DesktopNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;

  const _DesktopNavBar({required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        // A fixed height so the bar doesn't greedily fill the window and starve
        // the body of vertical space.
        child: SizedBox(
          height: 56,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _item(context, 0, Icons.map_outlined, Icons.map, '地图'),
                  _item(context, 1, Icons.list_alt_outlined, Icons.list_alt,
                      '旅途'),
                  _item(context, 2, Icons.explore_outlined, Icons.explore,
                      '浏览'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, int i, IconData icon, IconData selectedIcon,
      String label) {
    final theme = Theme.of(context);
    final selected = i == index;
    final fg = selected
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => onSelect(i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: selected
            ? BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(20),
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? selectedIcon : icon, size: 20, color: fg),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: fg, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
