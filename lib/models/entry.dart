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

  /// Local path / remote URL of the uploaded jpg for photo & drawing entries.
  final String? imagePath;

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
    this.imagePath,
    this.markerGlyph = '📍',
  });

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
