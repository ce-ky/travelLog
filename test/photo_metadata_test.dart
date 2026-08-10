import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:travel_log/utils/photo_metadata.dart';

/// Builds a minimal little-endian TIFF carrying only a GPS IFD, which
/// `readExifFromBytes` reads the same way it reads the EXIF block inside a
/// JPEG. [lat]/[lng] are whole degrees; [latRef]/[lngRef] are 'N'/'S','E'/'W'.
Uint8List _tiffWithGps({
  required int lat,
  required int lng,
  required String latRef,
  required String lngRef,
}) {
  // Layout (offsets in bytes):
  //   0   TIFF header (II, 42, IFD0 @ 8)
  //   8   IFD0: one entry — GPS IFD pointer (0x8825) -> 26
  //   26  GPS IFD: 4 entries (lat, latRef, lng, lngRef)
  //   80  latitude rationals (deg/1, 0/1, 0/1)
  //   104 longitude rationals (deg/1, 0/1, 0/1)
  final b = ByteData(128);
  const le = Endian.little;

  // TIFF header.
  b.setUint8(0, 0x49); // 'I'
  b.setUint8(1, 0x49); // 'I'
  b.setUint16(2, 42, le);
  b.setUint32(4, 8, le); // IFD0 offset

  // IFD0: one entry pointing at the GPS IFD.
  b.setUint16(8, 1, le); // entry count
  b.setUint16(10, 0x8825, le); // GPSInfo tag
  b.setUint16(12, 4, le); // type LONG
  b.setUint32(14, 1, le); // count
  b.setUint32(18, 26, le); // -> GPS IFD
  b.setUint32(22, 0, le); // next IFD

  // GPS IFD: 4 entries.
  b.setUint16(26, 4, le); // entry count
  // 0x0001 GPSLatitudeRef (ASCII, inline).
  b.setUint16(28, 0x0001, le);
  b.setUint16(30, 2, le); // type ASCII
  b.setUint32(32, 2, le); // count
  b.setUint8(36, latRef.codeUnitAt(0));
  // 0x0002 GPSLatitude (3 rationals @ 80).
  b.setUint16(40, 0x0002, le);
  b.setUint16(42, 5, le); // type RATIONAL
  b.setUint32(44, 3, le);
  b.setUint32(48, 80, le);
  // 0x0003 GPSLongitudeRef (ASCII, inline).
  b.setUint16(52, 0x0003, le);
  b.setUint16(54, 2, le);
  b.setUint32(56, 2, le);
  b.setUint8(60, lngRef.codeUnitAt(0));
  // 0x0004 GPSLongitude (3 rationals @ 104).
  b.setUint16(64, 0x0004, le);
  b.setUint16(66, 5, le);
  b.setUint32(68, 3, le);
  b.setUint32(72, 104, le);
  b.setUint32(76, 0, le); // next IFD

  // Latitude: deg/1, 0/1, 0/1.
  b.setUint32(80, lat, le);
  b.setUint32(84, 1, le);
  b.setUint32(88, 0, le);
  b.setUint32(92, 1, le);
  b.setUint32(96, 0, le);
  b.setUint32(100, 1, le);
  // Longitude: deg/1, 0/1, 0/1.
  b.setUint32(104, lng, le);
  b.setUint32(108, 1, le);
  b.setUint32(112, 0, le);
  b.setUint32(116, 1, le);
  b.setUint32(120, 0, le);
  b.setUint32(124, 1, le);

  return b.buffer.asUint8List();
}

void main() {
  test('reads a northern/eastern geotag from EXIF GPS tags', () async {
    final meta = await readPhotoMetadata(
      _tiffWithGps(lat: 35, lng: 139, latRef: 'N', lngRef: 'E'),
    );
    expect(meta.location, isNotNull);
    expect(meta.location!.latitude, closeTo(35, 0.0001));
    expect(meta.location!.longitude, closeTo(139, 0.0001));
  });

  test('applies S/W refs as negative degrees', () async {
    final meta = await readPhotoMetadata(
      _tiffWithGps(lat: 33, lng: 70, latRef: 'S', lngRef: 'W'),
    );
    expect(meta.location!.latitude, closeTo(-33, 0.0001));
    expect(meta.location!.longitude, closeTo(-70, 0.0001));
  });

  test('a photo with no EXIF yields empty metadata, not an error', () async {
    // A 1x1 PNG — valid image, no EXIF/GPS.
    final png = Uint8List.fromList(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
      0x42, 0x60, 0x82,
    ]);
    final meta = await readPhotoMetadata(png);
    expect(meta.location, isNull);
    expect(meta.isEmpty, isTrue);
  });

  test('garbage bytes degrade to empty metadata', () async {
    final meta = await readPhotoMetadata(Uint8List.fromList([1, 2, 3, 4, 5]));
    expect(meta.isEmpty, isTrue);
  });
}
