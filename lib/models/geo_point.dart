import 'package:latlong2/latlong.dart';

/// A location attached to an [Entry].
class GeoPoint {
  final double lat;
  final double lng;
  final String placeName;

  const GeoPoint({
    required this.lat,
    required this.lng,
    required this.placeName,
  });

  LatLng get latLng => LatLng(lat, lng);
}
