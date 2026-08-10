import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// The bytes and content type to upload for a picked image.
class PreparedUpload {
  final Uint8List bytes;
  final String contentType;

  const PreparedUpload(this.bytes, this.contentType);
}

/// Longest edge (px) an uploaded image is scaled down to.
const int _maxUploadEdge = 2400;

/// Downscales an over-large image in-Dart for upload.
///
/// The photo is picked at full resolution so its EXIF (GPS + capture time)
/// survives — on web, `image_picker`'s own resize re-encodes through a canvas
/// and strips that metadata. We therefore shrink here instead, only when the
/// image is actually larger than [_maxUploadEdge]. Anything we can't decode
/// (e.g. HEIC) or that's already small is uploaded unchanged.
PreparedUpload prepareUpload(Uint8List original, String fileName) {
  final fallbackType = contentTypeFor(fileName);
  try {
    final decoded = img.decodeImage(original);
    if (decoded == null) return PreparedUpload(original, fallbackType);

    final longest =
        decoded.width > decoded.height ? decoded.width : decoded.height;
    if (longest <= _maxUploadEdge) {
      return PreparedUpload(original, fallbackType);
    }

    final resized = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: _maxUploadEdge)
        : img.copyResize(decoded, height: _maxUploadEdge);
    final jpg = img.encodeJpg(resized, quality: 85);
    return PreparedUpload(jpg, 'image/jpeg');
  } catch (_) {
    // Never let compression block a save — upload what we were given.
    return PreparedUpload(original, fallbackType);
  }
}

/// Best-guess MIME type from a file name's extension.
String contentTypeFor(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.heic') || n.endsWith('.heif')) return 'image/heic';
  return 'image/jpeg';
}
