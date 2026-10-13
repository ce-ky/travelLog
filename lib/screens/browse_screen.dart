import 'package:flutter/material.dart';

import 'companions_view.dart';
import 'type_list_screen.dart';

/// View 3: browse records two ways — by record type, or by companion. The mode
/// is a small toggle at the right end of each mode's filter row, so the two
/// share one compact line instead of a separate segmented bar.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

enum _Mode { type, companion }

class _BrowseScreenState extends State<BrowseScreen> {
  _Mode _mode = _Mode.type;

  @override
  Widget build(BuildContext context) {
    final toggle = _ModeToggle(
      mode: _mode,
      onChanged: (m) => setState(() => _mode = m),
    );
    return _mode == _Mode.type
        ? TypeListScreen(trailing: toggle)
        : CompanionsView(trailing: toggle);
  }
}

/// A minimal two-way text toggle (类型 / 同行人): a faint pill track with the
/// selected side lifted onto a white chip.
class _ModeToggle extends StatelessWidget {
  final _Mode mode;
  final ValueChanged<_Mode> onChanged;

  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(context, _Mode.type, '类型'),
          _segment(context, _Mode.companion, '同行人'),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, _Mode value, String label) {
    final theme = Theme.of(context);
    final on = mode == value;
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(value),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? theme.colorScheme.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              boxShadow: on
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: on ? FontWeight.w500 : FontWeight.normal,
                color: on ? theme.colorScheme.onSurface : theme.hintColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
