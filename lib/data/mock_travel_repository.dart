import 'dart:typed_data';

import '../models/entry.dart';
import '../models/person.dart';
import '../models/trip.dart';
import 'mock_data.dart';
import 'travel_repository.dart';

/// In-memory repository used by widget tests and by the app before sign-in,
/// so the three views stay explorable without a network or an account.
class MockTravelRepository implements TravelRepository {
  /// `seed: false` starts empty, standing in for a fresh account.
  MockTravelRepository({bool seed = true})
      : _trips = seed ? List.of(MockData.trips) : [],
        _entries = seed ? List.of(MockData.entries) : [];

  final List<Trip> _trips;
  final List<Entry> _entries;
  late final List<Person> _people = List.of(MockData.people);

  @override
  Future<TravelSnapshot> loadAll() async => TravelSnapshot(
        trips: List.of(_trips),
        people: List.of(_people),
        entries: List.of(_entries),
      );

  @override
  Future<void> deleteTrip(String tripId) async {
    _entries.removeWhere((e) => e.tripId == tripId);
    _trips.removeWhere((t) => t.id == tripId);
  }

  @override
  Future<void> savePerson(Person person) async {
    final i = _people.indexWhere((p) => p.id == person.id);
    if (i == -1) {
      _people.add(person);
    } else {
      _people[i] = person;
    }
  }

  @override
  Future<void> deletePerson(String personId) async {
    _people.removeWhere((p) => p.id == personId);
    // Drop the person from every trip's companion list.
    for (var i = 0; i < _trips.length; i++) {
      final t = _trips[i];
      if (t.companions.any((p) => p.id == personId)) {
        _trips[i] = Trip(
          id: t.id,
          title: t.title,
          startDate: t.startDate,
          endDate: t.endDate,
          coverImagePath: t.coverImagePath,
          companions:
              t.companions.where((p) => p.id != personId).toList(),
        );
      }
    }
  }

  @override
  Future<void> saveTrip(Trip trip) async {
    final i = _trips.indexWhere((t) => t.id == trip.id);
    if (i == -1) {
      _trips.add(trip);
    } else {
      _trips[i] = trip;
    }
  }

  @override
  Future<void> saveEntry(Entry entry) async {
    final i = _entries.indexWhere((e) => e.id == entry.id);
    if (i == -1) {
      _entries.add(entry);
    } else {
      _entries[i] = entry;
    }
  }

  @override
  Future<void> deleteEntry(String entryId) async {
    _entries.removeWhere((e) => e.id == entryId);
  }

  @override
  Future<String> uploadImage({
    required String tripId,
    required String entryId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async =>
      'mock://$tripId/$entryId.jpg';

  // Sample data has no real files behind it.
  @override
  Future<String?> imageUrl(String storagePath) async => null;
}
