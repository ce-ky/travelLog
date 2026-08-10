import 'package:flutter_test/flutter_test.dart';
import 'package:travel_log/models/entry.dart';
import 'package:travel_log/models/entry_type.dart';

Entry _entry({List<String> images = const [], String title = ''}) => Entry(
      id: 'e',
      tripId: 't',
      type: EntryType.photo,
      title: title,
      timestamp: DateTime(2025, 1, 1),
      imagePaths: images,
    );

void main() {
  test('imagePath returns the first image, or null when there are none', () {
    expect(_entry(images: const ['a.jpg', 'b.jpg']).imagePath, 'a.jpg');
    expect(_entry().imagePath, isNull);
  });

  test('hasImage reflects whether any image is attached', () {
    expect(_entry(images: const ['a.jpg']).hasImage, isTrue);
    expect(_entry().hasImage, isFalse);
  });

  test('a record can carry up to four images', () {
    final e = _entry(images: const ['1', '2', '3', '4']);
    expect(e.imagePaths.length, 4);
  });

  test('explicitTitle is null unless a non-blank title was set', () {
    expect(_entry(title: '').explicitTitle, isNull);
    expect(_entry(title: '   ').explicitTitle, isNull);
    expect(_entry(title: '鸭川边的午后').explicitTitle, '鸭川边的午后');
  });
}
