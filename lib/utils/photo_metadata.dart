import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:latlong2/latlong.dart';

/// Location and capture time recovered from a photo's EXIF metadata.
///
/// iPhone (and most phone) photos embed where and when they were taken; pulling
/// that out lets a new record drop onto the map at the exact spot the picture
/// was shot, without the user placing the pin by hand.
class PhotoMetadata {
  final LatLng? location;
  final DateTime? capturedAt;

  const PhotoMetadata({this.location, this.capturedAt});

  bool get isEmpty => location == null && capturedAt == null;
}

/// Reads the GPS location and original capture time from a photo's EXIF tags.
///
/// Reading metadata is a best-effort convenience, never a gate on the upload:
/// an image with no EXIF, no GPS fix, or malformed tags yields an empty
/// [PhotoMetadata] rather than throwing, so a manual upload always proceeds.
Future<PhotoMetadata> readPhotoMetadata(Uint8List bytes) async {
  try {
    final tags = await readExifFromBytes(bytes);
    if (tags.isEmpty) return const PhotoMetadata();
    return PhotoMetadata(
      location: _gps(tags),
      capturedAt: _capturedAt(tags),
    );
  } catch (_) {
    // Corrupt or unexpected metadata must not break picking an image.
    return const PhotoMetadata();
  }
}

/// The photo's geotag as a [LatLng], or null when it carries no usable fix.
LatLng? _gps(Map<String, IfdTag> tags) {
  final lat = _degrees(tags['GPS GPSLatitude']);
  final lng = _degrees(tags['GPS GPSLongitude']);
  if (lat == null || lng == null) return null;

  // Refs are 'N'/'S' and 'E'/'W'; south and west are negative.
  final latRef = tags['GPS GPSLatitudeRef']?.printable.trim().toUpperCase();
  final lngRef = tags['GPS GPSLongitudeRef']?.printable.trim().toUpperCase();
  final signedLat = latRef == 'S' ? -lat : lat;
  final signedLng = lngRef == 'W' ? -lng : lng;

  // A camera with no fix often writes 0,0 — treat that as "no location".
  if (signedLat == 0 && signedLng == 0) return null;
  if (signedLat.abs() > 90 || signedLng.abs() > 180) return null;
  return LatLng(signedLat, signedLng);
}

/// Converts a GPS coordinate tag — degrees, minutes, seconds stored as three
/// rationals — into unsigned decimal degrees.
double? _degrees(IfdTag? tag) {
  if (tag == null) return null;
  final parts = tag.values.toList();
  if (parts.length < 3) return null;
  final d = _ratio(parts[0]);
  final m = _ratio(parts[1]);
  final s = _ratio(parts[2]);
  if (d == null || m == null || s == null) return null;
  return d + m / 60 + s / 3600;
}

double? _ratio(Object? value) {
  if (value is Ratio) {
    return value.denominator == 0 ? null : value.toDouble();
  }
  if (value is num) return value.toDouble();
  return null;
}

/// The moment the photo was taken, parsed from the EXIF "YYYY:MM:DD HH:MM:SS"
/// datetime (preferring the original-capture tag over the file's own).
DateTime? _capturedAt(Map<String, IfdTag> tags) {
  final raw = (tags['EXIF DateTimeOriginal'] ?? tags['Image DateTime'])
      ?.printable
      .trim();
  if (raw == null || raw.isEmpty) return null;
  final m =
      RegExp(r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})')
          .firstMatch(raw);
  if (m == null) return null;
  return DateTime(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6)!),
  );
}
