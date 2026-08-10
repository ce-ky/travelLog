import 'dart:typed_data';

import '../models/entry.dart';
import '../models/person.dart';
import '../models/trip.dart';

/// Everything the three views need, fetched in one go.
class TravelSnapshot {
  final List<Trip> trips;
  final List<Person> people;
  final List<Entry> entries;

  const TravelSnapshot({
    this.trips = const [],
    this.people = const [],
    this.entries = const [],
  });
}

/// The seam between the UI and wherever the data actually lives.
///
/// [AppState] talks only to this interface, so the local-first cache we add
/// later slots in as another implementation rather than a rewrite: the sync
/// engine becomes the thing behind this door, and the screens never notice.
abstract class TravelRepository {
  Future<TravelSnapshot> loadAll();

  /// Insert or update — the trip's client-generated id decides which.
  Future<void> saveTrip(Trip trip);

  /// Soft-deletes a trip and all of its entries.
  Future<void> deleteTrip(String tripId);

  /// Insert or update — the entry's client-generated id decides which.
  Future<void> saveEntry(Entry entry);

  /// Insert or update a companion.
  Future<void> savePerson(Person person);

  /// Soft-deletes a companion and removes them from every trip.
  Future<void> deletePerson(String personId);

  /// Soft delete, so other devices can observe the removal.
  Future<void> deleteEntry(String entryId);

  /// Uploads a jpg for a photo/drawing entry and returns its storage path.
  ///
  /// [index] disambiguates the several images a single record can carry, so
  /// their storage paths never collide.
  Future<String> uploadImage({
    required String tripId,
    required String entryId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
    int index = 0,
  });

  /// A displayable URL for a stored image path, or null if it can't be shown
  /// (e.g. the sample data has no real files behind it).
  Future<String?> imageUrl(String storagePath);
}
