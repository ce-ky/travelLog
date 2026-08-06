import 'package:flutter/material.dart';

import 'companions_view.dart';
import 'type_list_screen.dart';

/// View 3: browse records two ways — by record type, or by companion. A
/// broader home than the old type-only tab.
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: SegmentedButton<_Mode>(
            segments: const [
              ButtonSegment(
                value: _Mode.type,
                icon: Icon(Icons.category_outlined),
                label: Text('按类型'),
              ),
              ButtonSegment(
                value: _Mode.companion,
                icon: Icon(Icons.people_outline),
                label: Text('按同行人'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
            showSelectedIcon: false,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _mode == _Mode.type
              ? const TypeListScreen()
              : const CompanionsView(),
        ),
      ],
    );
  }
}
