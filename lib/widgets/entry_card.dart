import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/entry.dart';
import '../models/trip.dart';
import '../screens/entry_form.dart';
import '../state/app_state.dart';
import 'entry_image.dart';

/// One [Entry] rendered in the default [图+文] format: its images (up to four)
/// above, then the body text, with the title shown only when one was set.
/// Reused by every list view.
///
/// Tapping "编辑" swaps this display for [EntryForm] in place, prefilled from
/// the entry and laid out per its field type; saving swaps back in the
/// updated record.
class EntryCard extends StatefulWidget {
  final Entry entry;

  /// When set, tapping the card runs this (e.g. the map zooms to the record).
  /// Left null in the plain list views, where a card isn't itself tappable.
  final VoidCallback? onTap;

  /// Highlights the card as the one currently expanded on the map — mirrors the
  /// map selection into the floating records list so the two stay in sync.
  final bool selected;

  /// False inside a single trip's list (the trip-records panel, the trip
  /// page), where the trip, its companions and each day are already given by
  /// the surrounding headers: the card then drops the record type, the
  /// "time · trip" line and the companions, keeping only the place.
  final bool showTripContext;

  const EntryCard({
    super.key,
    required this.entry,
    this.onTap,
    this.selected = false,
    this.showTripContext = true,
  });

  @override
  State<EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<EntryCard> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      // The selected record picks up the same tinted container the selected
      // trip card uses, plus a primary outline, so it clearly reads as active.
      color: widget.selected ? theme.colorScheme.secondaryContainer : null,
      shape: widget.selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.primary, width: 1.5),
            )
          : null,
      child: _editing ? _buildEditor() : _buildDisplay(context, theme),
    );
  }

  Widget _buildEditor() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: EntryForm(
        initialEntry: widget.entry,
        onSaved: (_) => setState(() => _editing = false),
        onClose: () => setState(() => _editing = false),
      ),
    );
  }

  Widget _buildDisplay(BuildContext context, ThemeData theme) {
    final entry = widget.entry;
    final appState = context.read<AppState>();
    final trip = appState.tripById(entry.tripId);
    final dateStr = DateFormat('yyyy.MM.dd HH:mm').format(entry.timestamp);
    final title = entry.explicitTitle;

    return InkWell(
      // A null onTap leaves the card inert (no ripple) — the same look the
      // list views had before; only the map panel passes a handler.
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.hasImage) ...[
              _ImageStrip(paths: entry.imagePaths),
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
                      // With neither title nor body, keep a heading so the row
                      // never reads as empty.
                      if (title == null && entry.body.isEmpty)
                        Text(
                            widget.showTripContext
                                ? entry.type.label
                                : '记录',
                            style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      _MetaRow(
                        entry: entry,
                        trip: trip,
                        dateStr: dateStr,
                        showTripContext: widget.showTripContext,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: '编辑',
                  onPressed: () => setState(() => _editing = true),
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
    );
  }
}

/// The images above a card: a single wide banner for one image, or a row of
/// equal thumbnails for several.
class _ImageStrip extends StatelessWidget {
  final List<String> paths;

  const _ImageStrip({required this.paths});

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
      child: Icon(Icons.image_outlined, size: 26, color: theme.hintColor),
    );
  }
}

/// The compact meta line(s) under a card: type, place, date · trip, companions
/// — or just the place, inside a single trip's list (see
/// [EntryCard.showTripContext]).
class _MetaRow extends StatelessWidget {
  final Entry entry;
  final Trip trip;
  final String dateStr;
  final bool showTripContext;

  const _MetaRow({
    required this.entry,
    required this.trip,
    required this.dateStr,
    required this.showTripContext,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (showTripContext) ...[
              Icon(entry.type.icon, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(entry.type.label, style: const TextStyle(fontSize: 12)),
            ],
            if (entry.location != null) ...[
              if (showTripContext) const SizedBox(width: 8),
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
        if (showTripContext) ...[
          const SizedBox(height: 2),
          Text('$dateStr · ${trip.title}',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          if (trip.companions.isNotEmpty)
            Text('与 ${trip.companions.map((p) => p.name).join('、')}',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
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
