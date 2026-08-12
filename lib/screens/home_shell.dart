import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'browse_screen.dart';
import 'map_screen.dart';
import 'new_entry_sheet.dart';
import 'new_trip_sheet.dart';
import 'trips_screen.dart';

/// Top-level shell. Desktop and phone are two different shells:
///
///  - **Phone** keeps the familiar Material app bar + bottom navigation.
///  - **Desktop** makes the map the whole window with no chrome; the two other
///    sections open as floating right-side panels from round bubble buttons over
///    the map.
class HomeShell extends StatefulWidget {
  /// Passed through to [MapScreen]; only widget tests set it.
  final TileProvider? mapTileProvider;

  /// Shows the exit action when there is a session (or a sample run) to leave.
  final VoidCallback? onSignOut;

  const HomeShell({super.key, this.mapTileProvider, this.onSignOut});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

/// Which floating section panel is open on desktop.
enum _Panel { none, trips, browse }

class _HomeShellState extends State<HomeShell> {
  /// Phone-only: the selected bottom-nav tab.
  int _index = 0;

  /// Desktop-only: the open right-side panel.
  _Panel _panel = _Panel.none;

  static const _titles = ['地图', '旅途', '浏览'];

  /// Below this width we treat the window as a phone.
  static const _desktopBreakpoint = 720.0;

  /// Desktop channel: lets the 旅途 panel open a trip on the map (as a floating
  /// records panel) instead of a full-screen page.
  final MapCommands _mapCommands = MapCommands();

  late final _screens = [
    MapScreen(tileProvider: widget.mapTileProvider, commands: _mapCommands),
    const TripsScreen(),
    const BrowseScreen(),
  ];

  @override
  void dispose() {
    _mapCommands.dispose();
    super.dispose();
  }

  void _select(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;
    return desktop ? _buildDesktop(context) : _buildMobile(context);
  }

  // ---- Desktop: fullscreen map + floating bubbles + right-side panel --------

  Widget _buildDesktop(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // ~450 wide, but never so wide it crowds a small desktop window.
    final panelWidth = size.width - 40 < 450 ? size.width - 40 : 450.0;

    return Scaffold(
      body: Stack(
        children: [
          // The map is the default view and fills the whole window, no chrome.
          Positioned.fill(child: _screens[0]),

          // Round bubbles for the two management sections (and exit), top-left.
          Positioned(
            left: 20,
            top: 20,
            child: Column(
              children: [
                _Bubble(
                  icon: Icons.list_alt,
                  tooltip: '旅途',
                  selected: _panel == _Panel.trips,
                  onTap: () => _togglePanel(_Panel.trips),
                ),
                const SizedBox(height: 14),
                _Bubble(
                  icon: Icons.explore,
                  tooltip: '浏览',
                  selected: _panel == _Panel.browse,
                  onTap: () => _togglePanel(_Panel.browse),
                ),
                if (widget.onSignOut != null) ...[
                  const SizedBox(height: 14),
                  _Bubble(
                    icon: Icons.logout,
                    tooltip: '退出',
                    small: true,
                    onTap: widget.onSignOut!,
                  ),
                ],
              ],
            ),
          ),

          // The selected section, as a floating right-side panel (~450 wide).
          if (_panel != _Panel.none)
            Positioned(
              top: 20,
              right: 20,
              bottom: 20,
              width: panelWidth,
              child: _SidePanel(
                title: _panel == _Panel.trips ? '旅途' : '浏览',
                onClose: () => setState(() => _panel = _Panel.none),
                child: _panel == _Panel.trips
                    ? TripsScreen(onTripSelected: _openTripOnMap)
                    : const BrowseScreen(),
              ),
            ),
        ],
      ),
    );
  }

  void _togglePanel(_Panel p) =>
      setState(() => _panel = _panel == p ? _Panel.none : p);

  /// A trip picked in the 旅途 panel: open its records as a floating panel over
  /// the map (record taps then zoom the map), and close the nav panel so the
  /// map — and that floating records card — are in view.
  void _openTripOnMap(String tripId) {
    _mapCommands.openTrip(tripId);
    setState(() => _panel = _Panel.none);
  }

  // ---- Phone: app bar + bottom navigation (unchanged) ----------------------

  Widget _buildMobile(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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
      body: IndexedStack(
        sizing: StackFit.expand,
        index: _index,
        children: _screens,
      ),
      // The trips tab creates trips from a row at the top of its list, so it
      // has no FAB. The map/browse tabs add a record — icon only, no label.
      floatingActionButton: _index == 1
          ? null
          : FloatingActionButton(
              tooltip: '新增记录',
              onPressed: _createEntry,
              child: const Icon(Icons.add),
            ),
      bottomNavigationBar: NavigationBar(
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

/// A round, floating button over the map — the desktop entry point to a section.
class _Bubble extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;
  final bool small;

  const _Bubble({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = small ? 44.0 : 56.0;
    final bg = selected ? scheme.primary : scheme.surface;
    final fg = selected ? scheme.onPrimary : scheme.onSurfaceVariant;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        elevation: 3,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: d,
            height: d,
            child: Icon(icon, color: fg, size: small ? 20 : 24),
          ),
        ),
      ),
    );
  }
}

/// The floating right-hand panel that hosts a section (trips / browse) on
/// desktop: a rounded card with a title bar, a close button, and the section
/// widget filling the rest.
class _SidePanel extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback onClose;

  const _SidePanel({
    required this.title,
    required this.child,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 6,
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
            child: Row(
              children: [
                Text(title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '关闭',
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          // A faint hairline, matching the map's floating records panel, so the
          // header reads as part of one clean surface rather than a boxed section.
          Divider(
            height: 1,
            thickness: 1,
            color: theme.dividerColor.withValues(alpha: 0.4),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
