import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/entry.dart';
import '../models/trip.dart';
import '../state/app_state.dart';
import 'entry_image.dart';

/// One [Entry] rendered in the default [图+文] format: its images (up to four)
/// above, then the body text, with the title shown only when one was set.
/// Reused by every list view.
class EntryCard extends StatelessWidget {
  final Entry entry;

  /// When set, tapping the card runs this (e.g. the map zooms to the record).
  /// Left null in the plain list views, where a card isn't itself tappable.
  final VoidCallback? onTap;

  /// Highlights the card as the one currently expanded on the map — mirrors the
  /// map selection into the floating records list so the two stay in sync.
  final bool selected;

  const EntryCard({
    super.key,
    required this.entry,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = context.read<AppState>();
    final trip = appState.tripById(entry.tripId);
    final dateStr = DateFormat('yyyy.MM.dd HH:mm').format(entry.timestamp);
    final title = entry.explicitTitle;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      // The selected record picks up the same tinted container the selected
      // trip card uses, plus a primary outline, so it clearly reads as active.
      color: selected ? theme.colorScheme.secondaryContainer : null,
      shape: selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.primary, width: 1.5),
            )
          : null,
      child: InkWell(
        // A null onTap leaves the card inert (no ripple) — the same look the
        // list views had before; only the map panel passes a handler.
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (entry.hasImage) ...[
                _ImageStrip(paths: entry.imagePaths, glyph: entry.markerGlyph),
                const SizedBox(height: 10),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title is optional — only shown when the user set one.
                        if (title != null) ...[
                          Text(title,
                              style: theme.textTheme.titleMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                        ],
                        if (entry.body.isNotEmpty)
                          Text(entry.body,
                              maxLines: 4, overflow: TextOverflow.ellipsis),
                        // With neither title nor body, keep the type as a heading
                        // so the row never reads as empty.
                        if (title == null && entry.body.isEmpty)
                          Text(entry.type.label,
                              style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        _MetaRow(entry: entry, trip: trip, dateStr: dateStr),
                      ],
                    ),
                  ),
                  _DeleteButton(
                    onConfirm: () =>
                        context.read<AppState>().removeEntry(entry.id),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The images above a card: a single wide banner for one image, or a row of
/// equal thumbnails for several.
class _ImageStrip extends StatelessWidget {
  final List<String> paths;
  final String glyph;

  const _ImageStrip({required this.paths, required this.glyph});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(10);

    if (paths.length == 1) {
      return EntryImage(
        imagePath: paths.first,
        height: 168,
        borderRadius: radius,
        fallback: _fallback(context, 168),
      );
    }

    return SizedBox(
      height: 92,
      child: Row(
        children: [
          for (var i = 0; i < paths.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: EntryImage(
                imagePath: paths[i],
                height: 92,
                borderRadius: radius,
                fallback: _fallback(context, 92),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fallback(BuildContext context, double height) {
    final theme = Theme.of(context);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(glyph, style: const TextStyle(fontSize: 26)),
    );
  }
}

/// The compact meta line(s) under a card: type, place, date · trip, companions.
class _MetaRow extends StatelessWidget {
  final Entry entry;
  final Trip trip;
  final String dateStr;

  const _MetaRow(
      {required this.entry, required this.trip, required this.dateStr});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(entry.type.icon, size: 14, color: Colors.grey),
            const SizedBox(width: 4),
            Text(entry.type.label, style: const TextStyle(fontSize: 12)),
            if (entry.location != null) ...[
              const SizedBox(width: 8),
              const Icon(Icons.place_outlined, size: 14, color: Colors.grey),
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
