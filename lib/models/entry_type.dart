import 'package:flutter/material.dart';

/// The kind of record an [Entry] holds.
///
/// Note: `drawing` is not an in-app canvas — it is a jpg image upload,
/// handled through the same pipeline as `photo`.
enum EntryType {
  place,
  photo,
  drawing,
  story,
  essay;

  String get label {
    switch (this) {
      case EntryType.place:
        return '地点';
      case EntryType.photo:
        return '照片';
      case EntryType.drawing:
        return '画';
      case EntryType.story:
        return '故事';
      case EntryType.essay:
        return '随笔';
    }
  }

  IconData get icon {
    switch (this) {
      case EntryType.place:
        return Icons.place_outlined;
      case EntryType.photo:
        return Icons.photo_camera_outlined;
      case EntryType.drawing:
        return Icons.brush_outlined;
      case EntryType.story:
        return Icons.auto_stories_outlined;
      case EntryType.essay:
        return Icons.edit_note_outlined;
    }
  }

  /// Whether this entry type is backed by an uploaded image file (jpg).
  bool get isImageBacked => this == EntryType.photo || this == EntryType.drawing;
}
