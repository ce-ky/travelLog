import 'geo_point.dart';
import 'entry_type.dart';

/// A single record within a trip: a place, photo, drawing, story or essay.
///
/// All three main views (map / filter list / type list) are just different
/// queries over a collection of [Entry] objects. Companions live on the [Trip],
/// not here — who you travelled with is a property of the trip.
class Entry {
  final String id;
  final String tripId;
  final EntryType type;
  final String title;

  /// Free text for story/essay; caption for photo/drawing/place.
  final String body;

  final DateTime timestamp;
  final GeoPoint? location;
  final List<String> tags;

  /// Storage paths / URLs of the uploaded jpgs for photo & drawing entries —
  /// up to four per record. Ordered as the user arranged them.
  final List<String> imagePaths;

  /// Emoji or asset key used to render this entry's custom-shaped map marker.
  final String markerGlyph;

  const Entry({
    required this.id,
    required this.tripId,
    required this.type,
    this.title = '',
    this.body = '',
    required this.timestamp,
    this.location,
    this.tags = const [],
    this.imagePaths = const [],
    this.markerGlyph = '📍',
  });

  /// The first image, for spots that show a single thumbnail (map markers, the
  /// list-row leading avatar).
  String? get imagePath => imagePaths.isEmpty ? null : imagePaths.first;

  /// Whether the record carries at least one image.
  bool get hasImage => imagePaths.isNotEmpty;

  /// The user-entered title, or null when none was set. The [图+文] card shows a
  /// title row only when this is non-null — a title is optional, never forced.
  String? get explicitTitle => title.trim().isEmpty ? null : title.trim();

  /// What to show as the record's heading. The form no longer collects a title,
  /// so fall back to the place name, then a snippet of the body, then the type.
  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    final place = location?.placeName.trim() ?? '';
    if (place.isNotEmpty) return place;
    final firstLine = body.trim().split('\n').first.trim();
    if (firstLine.isNotEmpty) {
      return firstLine.length > 30 ? '${firstLine.substring(0, 30)}…' : firstLine;
    }
    return type.label;
  }
}
