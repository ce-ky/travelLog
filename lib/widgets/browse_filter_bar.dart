import 'package:flutter/material.dart';

/// The browse view's filter row: borderless icon filters on the left, an
/// optional [trailing] control (the small mode toggle) on the right, and a
/// faint hairline underneath.
class BrowseFilterBar extends StatelessWidget {
  final List<Widget> filters;
  final Widget? trailing;

  const BrowseFilterBar({super.key, required this.filters, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Wrap(spacing: 4, runSpacing: 4, children: filters),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing!,
              ],
            ],
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: theme.dividerColor.withValues(alpha: 0.4),
        ),
      ],
    );
  }
}

/// A minimal filter: just an icon (or a companion's initial) in a round hit
/// area — no label, no border. The name lives in the tooltip. Selected, it
/// sits on a tinted disc and takes the primary colour.
class IconFilterButton extends StatelessWidget {
  /// Usually an [Icon] without an explicit colour, so it picks up the
  /// selected / unselected colour from here; or an [InitialDisc].
  final Widget child;
  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;

  static const double size = 36;

  const IconFilterButton({
    super.key,
    required this.child,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: selected ? scheme.secondaryContainer : Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            hoverColor: Colors.black.withValues(alpha: 0.05),
            child: SizedBox.square(
              dimension: size,
              child: Center(
                child: IconTheme.merge(
                  data: IconThemeData(
                    size: 20,
                    color: selected ? scheme.primary : Colors.grey,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A companion's initial in a small disc — their "icon" in the filter row.
class InitialDisc extends StatelessWidget {
  final String name;
  final bool selected;

  const InitialDisc({super.key, required this.name, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected
            ? scheme.primary
            : Colors.black.withValues(alpha: 0.07),
      ),
      child: Text(
        name.characters.isEmpty ? '' : name.characters.first,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
