import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/entry.dart';
import '../state/app_state.dart';
import 'entry_image.dart';

/// A compact list row for one [Entry], reused by both list views.
class EntryCard extends StatelessWidget {
  final Entry entry;
  const EntryCard({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final trip = appState.tripById(entry.tripId);
    final dateStr = DateFormat('yyyy.MM.dd HH:mm').format(entry.timestamp);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: EntryImage(
          imagePath: entry.imagePath,
          width: 48,
          height: 48,
          borderRadius: BorderRadius.circular(8),
          fallback: CircleAvatar(
            child: Text(entry.markerGlyph,
                style: const TextStyle(fontSize: 18)),
          ),
        ),
        title: Text(entry.displayTitle,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(entry.type.icon, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(entry.type.label,
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                if (entry.location != null) ...[
                  const Icon(Icons.place_outlined,
                      size: 14, color: Colors.grey),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(entry.location!.placeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text('$dateStr · ${trip.title}',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            if (trip.companions.isNotEmpty)
              Text('与 ${trip.companions.map((p) => p.name).join('、')}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        isThreeLine: true,
        trailing: _DeleteButton(
          onConfirm: () => context.read<AppState>().removeEntry(entry.id),
        ),
      ),
    );
  }
}

/// A delete control that asks for confirmation in place: the first tap turns it
/// into "确认？", the second tap deletes. It reverts itself after a few seconds
/// so a stray first tap doesn't leave it armed.
class _DeleteButton extends StatefulWidget {
  final Future<void> Function() onConfirm;
  const _DeleteButton({required this.onConfirm});

  @override
  State<_DeleteButton> createState() => _DeleteButtonState();
}

class _DeleteButtonState extends State<_DeleteButton> {
  bool _confirming = false;
  bool _busy = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _arm() {
    setState(() => _confirming = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _confirming = false);
    });
  }

  Future<void> _confirm() async {
    _resetTimer?.cancel();
    setState(() => _busy = true);
    try {
      await widget.onConfirm();
      // On success this card is removed by the list refresh, so no reset needed.
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _confirming = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (!_confirming) {
      return IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: '删除',
        onPressed: _arm,
      );
    }
    return TextButton(
      onPressed: _confirm,
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.error,
      ),
      child: const Text('是否确认？'),
    );
  }
}
