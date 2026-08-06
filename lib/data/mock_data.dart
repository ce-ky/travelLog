import '../models/entry.dart';
import '../models/entry_type.dart';
import '../models/geo_point.dart';
import '../models/person.dart';
import '../models/trip.dart';

/// In-memory sample data so the skeleton renders something before a real
/// backend (Firebase / Supabase) is wired in.
class MockData {
  static const people = <Person>[
    Person(id: 'p1', name: '小林'),
    Person(id: 'p2', name: '阿宽'),
    Person(id: 'p3', name: '妈妈'),
  ];

  static final trips = <Trip>[
    Trip(
      id: 't1',
      title: '京都之旅',
      startDate: DateTime(2025, 4, 3),
      endDate: DateTime(2025, 4, 8),
      companions: [people[0], people[1]],
    ),
    Trip(
      id: 't2',
      title: '云南漫游',
      startDate: DateTime(2024, 10, 1),
      endDate: DateTime(2024, 10, 7),
      companions: [people[2]],
    ),
  ];

  static final entries = <Entry>[
    Entry(
      id: 'e1',
      tripId: 't1',
      type: EntryType.place,
      title: '伏见稻荷大社',
      body: '千本鸟居，清晨人少的时候最好看。',
      timestamp: DateTime(2025, 4, 3, 9, 30),
      location: const GeoPoint(
          lat: 34.9671, lng: 135.7727, placeName: '伏见稻荷大社'),
      tags: ['神社', '徒步'],
      markerGlyph: '⛩️',
    ),
    Entry(
      id: 'e2',
      tripId: 't1',
      type: EntryType.photo,
      title: '鸭川边的午后',
      timestamp: DateTime(2025, 4, 4, 15, 10),
      location:
          const GeoPoint(lat: 35.0116, lng: 135.7681, placeName: '鸭川'),
      tags: ['河边'],
      imagePath: 'mock://kamo.jpg',
      markerGlyph: '📷',
    ),
    Entry(
      id: 'e3',
      tripId: 't1',
      type: EntryType.essay,
      title: '关于旅行的意义',
      body: '走得越远，越明白自己想留下的其实是那些说不清的瞬间……',
      timestamp: DateTime(2025, 4, 5, 21, 0),
      location:
          const GeoPoint(lat: 35.0036, lng: 135.7780, placeName: '祇园'),
      tags: ['随想'],
      markerGlyph: '✍️',
    ),
    Entry(
      id: 'e4',
      tripId: 't2',
      type: EntryType.drawing,
      title: '洱海速写',
      timestamp: DateTime(2024, 10, 2, 17, 45),
      location:
          const GeoPoint(lat: 25.7860, lng: 100.1910, placeName: '洱海'),
      tags: ['速写', '湖'],
      imagePath: 'mock://erhai.jpg',
      markerGlyph: '🎨',
    ),
    Entry(
      id: 'e5',
      tripId: 't2',
      type: EntryType.story,
      title: '在古城迷路的那晚',
      body: '误打误撞走进一家小酒馆，老板弹着吉他，我们聊到打烊。',
      timestamp: DateTime(2024, 10, 3, 20, 30),
      location:
          const GeoPoint(lat: 26.8721, lng: 100.2299, placeName: '丽江古城'),
      tags: ['夜晚', '音乐'],
      markerGlyph: '🌙',
    ),
  ];
}
