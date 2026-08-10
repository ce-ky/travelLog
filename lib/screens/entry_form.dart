import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/entry.dart';
import '../models/entry_type.dart';
import '../models/geo_point.dart';
import '../models/trip.dart';
import '../state/app_state.dart';
import '../utils/image_upload.dart';
import '../utils/photo_metadata.dart';
import 'location_picker_screen.dart';

/// The new-entry form itself, independent of how it's presented. It's hosted
/// both by the bottom sheet (from the FAB) and by the map's location popup —
/// so it closes via callbacks rather than Navigator, and never assumes a sheet.
class EntryForm extends StatefulWidget {
  final String? initialTripId;
  final LatLng? initialPoint;

  /// Called after the entry is saved successfully, with the created entry.
  final ValueChanged<Entry> onSaved;

  /// Called when the user dismisses the form without saving.
  final VoidCallback onClose;

  /// Popup mode: tighter padding, a smaller image area, and a close button in
  /// the header instead of a drag handle.
  final bool compact;

  const EntryForm({
    super.key,
    this.initialTripId,
    this.initialPoint,
    required this.onSaved,
    required this.onClose,
    this.compact = false,
  });

  @override
  State<EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends State<EntryForm> {
  final _formKey = GlobalKey<FormState>();
  final _body = TextEditingController();
  final _placeName = TextEditingController();

  // Fixed up front so the image can be uploaded under this entry's storage path
  // before the row itself is saved.
  final _entryId = const Uuid().v4();

  String? _tripId;
  EntryType _type = EntryType.photo;
  DateTime _when = DateTime.now();

  LatLng? _point;

  /// Up to [_maxImages] picked images, in display order.
  final List<XFile> _pickedImages = [];

  /// Max images a single record can carry.
  static const int _maxImages = 4;

  /// Max characters allowed in the body text.
  static const int _maxBody = 5000;

  /// True while [_point] came from a picked photo's geotag rather than a
  /// manual map pick — drives the "位置来自照片" hint.
  bool _locationFromPhoto = false;

  /// Set once the user edits the time by hand, so photo metadata won't overwrite
  /// a deliberate choice.
  bool _whenTouched = false;

  /// Set once a photo's capture time has been applied, so a second photo in the
  /// same pick doesn't override the first one's time.
  bool _timeFromPhoto = false;

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _point = widget.initialPoint;
    // Prefer an explicit trip; otherwise, if adding at a point, auto-pick the
    // trip whose nearest record is within [_autoSelectKm].
    _tripId = widget.initialTripId ??
        _nearestTripId(context.read<AppState>(), widget.initialPoint);
  }

  /// Max distance for snapping a new record to an existing trip.
  static const double _autoSelectKm = 50;

  /// The trip of the closest located entry within [_autoSelectKm], or null.
  static String? _nearestTripId(AppState app, LatLng? point) {
    if (point == null) return null;
    const distance = Distance();
    String? best;
    var bestMeters = _autoSelectKm * 1000;
    for (final e in app.allEntries) {
      final loc = e.location;
      if (loc == null) continue;
      final d = distance.distance(point, loc.latLng); // metres
      if (d <= bestMeters) {
        bestMeters = d;
        best = e.tripId;
      }
    }
    return best;
  }

  /// The shortest distance (metres) from [point] to any of a trip's records.
  static double _tripDistance(AppState app, String tripId, LatLng point) {
    const distance = Distance();
    var best = double.infinity;
    for (final e in app.allEntries) {
      if (e.tripId != tripId) continue;
      final loc = e.location;
      if (loc == null) continue;
      final d = distance.distance(point, loc.latLng);
      if (d < best) best = d;
    }
    return best;
  }

  /// Trips ordered nearest-first when a point is known, else most recent first.
  List<Trip> _tripsByDistance(AppState app) {
    final trips = [...app.trips];
    final point = _point;
    if (point == null) {
      trips.sort((a, b) => b.startDate.compareTo(a.startDate));
    } else {
      trips.sort((a, b) => _tripDistance(app, a.id, point)
          .compareTo(_tripDistance(app, b.id, point)));
    }
    return trips;
  }

  @override
  void dispose() {
    _body.dispose();
    _placeName.dispose();
    super.dispose();
  }

  bool get _needsImage => _type.isImageBacked;

  int get _remainingImageSlots => _maxImages - _pickedImages.length;

  Future<void> _pickImages() async {
    if (_remainingImageSlots <= 0) return;
    // Pick at full resolution (no maxWidth/imageQuality) so each photo's EXIF —
    // its GPS geotag and capture time — survives; image_picker's own resize
    // re-encodes and strips that metadata. We downscale ourselves at upload.
    final picked = await ImagePicker().pickMultiImage(
      requestFullMetadata: true,
    );
    if (picked.isEmpty || !mounted) return;
    // Honour the four-image cap even if the user selected more.
    final added = picked.take(_remainingImageSlots).toList();
    setState(() => _pickedImages.addAll(added));
    if (picked.length > added.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        // _maxImages is a compile-time constant, so the whole SnackBar is const.
        const SnackBar(content: Text('最多 $_maxImages 张图，多余的已忽略')),
      );
    }
    await _applyPhotoMetadata(added);
  }

  void _removeImageAt(int index) {
    setState(() => _pickedImages.removeAt(index));
  }

  /// Pulls a geotag and capture time out of the newly-added photos' EXIF and
  /// fills them in — the location so the record lands on the map where the shot
  /// was taken, the time so the record is dated when it happened. Uses the first
  /// photo that carries each, and never overrides a value the user set by hand.
  Future<void> _applyPhotoMetadata(List<XFile> images) async {
    for (final image in images) {
      // Stop early once both are settled.
      if (_point != null && _timeFromPhoto) return;
      final bytes = await image.readAsBytes();
      final meta = await readPhotoMetadata(bytes);
      if (!mounted) return;
      setState(() {
        if (meta.location != null && _point == null) {
          _point = meta.location;
          _locationFromPhoto = true;
        }
        if (meta.capturedAt != null && !_whenTouched && !_timeFromPhoto) {
          _when = meta.capturedAt!;
          _timeFromPhoto = true;
        }
      });
    }
  }

  Future<void> _pickWhen() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    setState(() {
      _whenTouched = true;
      _when = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _when.hour,
        time?.minute ?? _when.minute,
      );
    });
  }

  /// Up to three nearest trips as chips; the selected trip is always shown even
  /// if it's not in the top three, and a "更多" chip opens the full list.
  Widget _buildTripChips(AppState appState) {
    final sorted = _tripsByDistance(appState);
    final shown = sorted.take(3).toList();
    if (_tripId != null && !shown.any((t) => t.id == _tripId)) {
      final sel = sorted.where((t) => t.id == _tripId).firstOrNull;
      if (sel != null) shown.insert(0, sel);
    }

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final t in shown)
          ChoiceChip(
            label: Text(t.title),
            selected: _tripId == t.id,
            onSelected: (_) => setState(() => _tripId = t.id),
          ),
        if (sorted.length > shown.length)
          ActionChip(
            avatar: const Icon(Icons.more_horiz, size: 18),
            label: const Text('更多'),
            onPressed: () => _pickTripFromAll(sorted),
          ),
      ],
    );
  }

  /// A bottom-sheet list of every trip (nearest first) to pick from.
  Future<void> _pickTripFromAll(List<Trip> trips) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择旅途', style: TextStyle(fontSize: 16)),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final t in trips)
                    ListTile(
                      leading: const Icon(Icons.luggage_outlined),
                      title: Text(t.title),
                      trailing: _tripId == t.id
                          ? const Icon(Icons.check, color: Colors.green)
                          : null,
                      onTap: () => Navigator.of(ctx).pop(t.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _tripId = picked);
  }

  Future<void> _pickLocation() async {
    final picked = await LocationPickerScreen.show(context, initialPoint: _point);
    if (picked != null) {
      setState(() {
        _point = picked;
        _locationFromPhoto = false; // a hand-picked point is no longer "from photo"
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_tripId == null) {
      setState(() => _error = '请选择所属旅途');
      return;
    }
    if (_needsImage && _pickedImages.isEmpty) {
      setState(() => _error = '这类记录需要至少选择一张图片');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final appState = context.read<AppState>();
    try {
      // Upload each picked image; keep them in the order the user arranged.
      final imagePaths = <String>[];
      for (var i = 0; i < _pickedImages.length; i++) {
        final image = _pickedImages[i];
        final original = await image.readAsBytes();
        final upload = prepareUpload(original, image.name);
        final path = await appState.uploadImage(
          tripId: _tripId!,
          entryId: _entryId,
          bytes: upload.bytes,
          contentType: upload.contentType,
          index: i,
        );
        imagePaths.add(path);
      }

      final entry = Entry(
        id: _entryId,
        tripId: _tripId!,
        type: _type,
        // No title field; the card leads with the images and body instead.
        title: '',
        body: _body.text.trim(),
        timestamp: _when,
        location: _point == null
            ? null
            : GeoPoint(
                lat: _point!.latitude,
                lng: _point!.longitude,
                placeName: _placeName.text.trim(),
              ),
        imagePaths: imagePaths,
      );
      await appState.addEntry(entry);

      if (mounted) widget.onSaved(entry);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = Theme.of(context);
    final fmt = DateFormat('yyyy年M月d日 HH:mm');

    return Form(
      key: _formKey,
      // Compact mode is laid out to fit without scrolling; the scroll view is a
      // safety net for very cramped popups rather than the normal interaction.
      child: widget.compact
          ? SingleChildScrollView(child: _compactBody(appState, theme, fmt))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(theme),
                  const SizedBox(height: 14),
                  _buildTripChips(appState),
                  const SizedBox(height: 14),
                  if (_needsImage) ...[
                    _ImageGalleryField(
                      images: _pickedImages,
                      maxImages: _maxImages,
                      tileSize: 96,
                      onAdd: _pickImages,
                      onRemoveAt: _removeImageAt,
                    ),
                    const SizedBox(height: 14),
                  ],
                  _bodyField(maxLines: 6),
                  const SizedBox(height: 14),
                  _timeField(fmt),
                  const SizedBox(height: 14),
                  _locationField(),
                  if (_locationFromPhoto) ...[
                    const SizedBox(height: 6),
                    _photoLocationBadge(theme),
                  ],
                  if (_point != null) ...[
                    const SizedBox(height: 10),
                    _placeNameField(),
                  ],
                  const SizedBox(height: 18),
                  _typeSection(theme),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    _errorBox(theme),
                  ],
                  const SizedBox(height: 20),
                  _saveButton(),
                ],
              ),
            ),
    );
  }

  /// Compact (map-popup) layout: image on the left, a small config strip on the
  /// right, sized to fit without scrolling.
  Widget _compactBody(AppState appState, ThemeData theme, DateFormat fmt) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(theme),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_needsImage) ...[
                SizedBox(
                  width: 140,
                  child: _ImageGalleryField(
                    images: _pickedImages,
                    maxImages: _maxImages,
                    tileSize: 62,
                    onAdd: _pickImages,
                    onRemoveAt: _removeImageAt,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(child: _configStrip(appState, theme, fmt)),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            _errorBox(theme),
          ],
          const SizedBox(height: 10),
          _saveButton(),
        ],
      ),
    );
  }

  /// The small, side-strip config controls used in compact mode.
  Widget _configStrip(AppState appState, ThemeData theme, DateFormat fmt) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _typeSection(theme, dense: true),
        const SizedBox(height: 8),
        _buildTripChips(appState),
        const SizedBox(height: 8),
        _bodyField(maxLines: 2, dense: true),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _timeField(fmt, dense: true)),
            const SizedBox(width: 6),
            Expanded(child: _locationField(dense: true)),
          ],
        ),
        if (_locationFromPhoto) ...[
          const SizedBox(height: 6),
          _photoLocationBadge(theme),
        ],
        if (_point != null) ...[
          const SizedBox(height: 8),
          _placeNameField(dense: true),
        ],
      ],
    );
  }

  Widget _typeSection(ThemeData theme, {bool dense = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('类型', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: dense ? 6 : 8,
          runSpacing: 4,
          children: [
            for (final t in EntryType.values)
              ChoiceChip(
                avatar: dense ? null : Icon(t.icon, size: 18),
                label: Text(t.label),
                selected: _type == t,
                onSelected: (_) => setState(() => _type = t),
                visualDensity: dense ? VisualDensity.compact : null,
                materialTapTargetSize:
                    dense ? MaterialTapTargetSize.shrinkWrap : null,
              ),
          ],
        ),
      ],
    );
  }

  Widget _bodyField({required int maxLines, bool dense = false}) {
    return TextFormField(
      controller: _body,
      minLines: 2,
      maxLines: maxLines,
      // Cap the body at 5000 chars (enforced by default when maxLength is set).
      maxLength: _maxBody,
      // Hide the character counter in the cramped compact/map-popup layout.
      buildCounter: dense
          ? (_, {required currentLength, required isFocused, maxLength}) => null
          : null,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        labelText: '说些什么：',
        alignLabelWithHint: true,
        isDense: true,
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _timeField(DateFormat fmt, {bool dense = false}) {
    return _TapField(
      label: '时间',
      icon: Icons.schedule,
      text: dense ? DateFormat('MM/dd HH:mm').format(_when) : fmt.format(_when),
      onTap: _pickWhen,
      dense: dense,
    );
  }

  Widget _locationField({bool dense = false}) {
    return _TapField(
      label: '位置',
      icon: Icons.map_outlined,
      text: _point == null
          ? (dense ? '选择' : '在地图上选择（可选）')
          : '${_point!.latitude.toStringAsFixed(dense ? 2 : 4)}, '
              '${_point!.longitude.toStringAsFixed(dense ? 2 : 4)}',
      onTap: _pickLocation,
      onClear: _point == null
          ? null
          : () => setState(() {
                _point = null;
                _locationFromPhoto = false;
              }),
      dense: dense,
    );
  }

  /// A small note shown under the location field when [_point] was auto-filled
  /// from the picked photo's geotag.
  Widget _photoLocationBadge(ThemeData theme) {
    return Row(
      children: [
        Icon(Icons.auto_awesome, size: 14, color: theme.colorScheme.primary),
        const SizedBox(width: 4),
        Expanded(
          child: Text('位置来自照片',
              style:
                  TextStyle(fontSize: 12, color: theme.colorScheme.primary)),
        ),
      ],
    );
  }

  Widget _placeNameField({bool dense = false}) {
    return TextFormField(
      controller: _placeName,
      decoration: InputDecoration(
        labelText: '地点名称',
        hintText: '例如：鸭川',
        prefixIcon: const Icon(Icons.place_outlined),
        isDense: dense,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _errorBox(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(_error!,
          style: TextStyle(
              color: theme.colorScheme.onErrorContainer, fontSize: 13)),
    );
  }

  Widget _saveButton() {
    return FilledButton(
      onPressed: _busy ? null : _save,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 15),
      ),
      child: _busy
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('保存'),
    );
  }

  Widget _header(ThemeData theme) {
    if (widget.compact) {
      return Row(
        children: [
          Expanded(
            child: Text('新增记录', style: theme.textTheme.titleMedium),
          ),
          InkWell(
            onTap: widget.onClose,
            customBorder: const CircleBorder(),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 20),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: theme.dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text('新增记录', style: theme.textTheme.titleLarge),
      ],
    );
  }
}

class _TapField extends StatelessWidget {
  final String label;
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final bool dense;

  const _TapField({
    required this.label,
    required this.icon,
    required this.text,
    required this.onTap,
    this.onClear,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: dense ? 18 : 24),
          isDense: dense,
          contentPadding: dense
              ? const EdgeInsets.symmetric(horizontal: 8, vertical: 12)
              : null,
          border: const OutlineInputBorder(),
          suffixIcon: onClear == null
              ? (dense ? null : const Icon(Icons.chevron_right))
              : IconButton(
                  icon: const Icon(Icons.clear, size: 18), onPressed: onClear),
        ),
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: dense ? 12 : 14)),
      ),
    );
  }
}

/// A small gallery for picking up to [maxImages] photos: each picked image is a
/// removable thumbnail, and an "add" tile appears while slots remain. Tiles wrap
/// so the field fits both the full sheet and the narrow map-popup strip.
class _ImageGalleryField extends StatelessWidget {
  final List<XFile> images;
  final int maxImages;
  final double tileSize;
  final VoidCallback onAdd;
  final void Function(int index) onRemoveAt;

  const _ImageGalleryField({
    required this.images,
    required this.maxImages,
    required this.tileSize,
    required this.onAdd,
    required this.onRemoveAt,
  });

  @override
  Widget build(BuildContext context) {
    final canAdd = images.length < maxImages;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < images.length; i++)
          _thumb(context, images[i], i),
        if (canAdd) _addTile(context),
      ],
    );
  }

  Widget _thumb(BuildContext context, XFile image, int index) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: tileSize,
        height: tileSize,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Image.memory works the same on web, desktop and mobile.
            FutureBuilder<Uint8List>(
              future: image.readAsBytes(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                return Image.memory(snap.data!, fit: BoxFit.cover);
              },
            ),
            Positioned(
              top: 2,
              right: 2,
              child: _ImageAction(
                icon: Icons.close,
                onTap: () => onRemoveAt(index),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addTile(BuildContext context) {
    final theme = Theme.of(context);
    final dense = tileSize < 80;
    return InkWell(
      onTap: onAdd,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: tileSize,
        height: tileSize,
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_outlined,
                size: dense ? 22 : 32, color: theme.colorScheme.primary),
            if (!dense) ...[
              const SizedBox(height: 4),
              Text('添加', style: TextStyle(color: theme.colorScheme.primary)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImageAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ImageAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}
