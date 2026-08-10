import 'package:flutter/foundation.dart';

import '../data/travel_repository.dart';
import '../models/entry.dart';
import '../models/entry_type.dart';
import '../models/person.dart';
import '../models/trip.dart';

/// Holds the app's data and the active filters shared across views.
///
/// It knows nothing about Supabase — only about [TravelRepository]. That is what
/// lets the local-first cache land later without touching any screen.
class AppState extends ChangeNotifier {
  final TravelRepository _repo;

  AppState(this._repo) {
    refresh();
  }

  List<Trip> trips = const [];
  List<Person> people = const [];
  List<Entry> _entries = const [];

  bool _loading = true;
  Object? _error;

  bool get loading => _loading;
  Object? get error => _error;

  /// Pulls a fresh snapshot. Safe to call again after sign-in or a sync.
  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final snap = await _repo.loadAll();
      trips = snap.trips;
      people = snap.people;
      _entries = snap.entries;
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ---- Filters (shared by the two list views) ----
  final Set<EntryType> _typeFilter = {};
  String? _tripFilter;
  String? _companionFilter;

  Set<EntryType> get typeFilter => _typeFilter;
  String? get tripFilter => _tripFilter;
  String? get companionFilter => _companionFilter;

  List<Entry> get allEntries => List.unmodifiable(_entries);

  Trip tripById(String id) => trips.firstWhere((t) => t.id == id);

  void toggleType(EntryType type) {
    if (!_typeFilter.remove(type)) _typeFilter.add(type);
    notifyListeners();
  }

  void setTripFilter(String? tripId) {
    _tripFilter = tripId;
    notifyListeners();
  }

  void setCompanionFilter(String? personId) {
    _companionFilter = personId;
    notifyListeners();
  }

  void clearFilters() {
    _typeFilter.clear();
    _tripFilter = null;
    _companionFilter = null;
    notifyListeners();
  }

  /// Entries after applying the shared filters, newest first.
  ///
  /// Companion filtering is by trip now: an entry matches if the trip it belongs
  /// to lists that companion.
  List<Entry> get filteredEntries {
    final tripsById = {for (final t in trips) t.id: t};

    final list = _entries.where((e) {
      if (_typeFilter.isNotEmpty && !_typeFilter.contains(e.type)) {
        return false;
      }
      if (_tripFilter != null && e.tripId != _tripFilter) return false;
      if (_companionFilter != null) {
        final trip = tripsById[e.tripId];
        if (trip == null ||
            !trip.companions.any((p) => p.id == _companionFilter)) {
          return false;
        }
      }
      return true;
    }).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  /// Entries that carry a location — used by the map view.
  List<Entry> get locatedEntries =>
      filteredEntries.where((e) => e.location != null).toList();

  Future<void> addEntry(Entry entry) async {
    await _repo.saveEntry(entry);
    await refresh();
  }

  Future<void> removeEntry(String entryId) async {
    await _repo.deleteEntry(entryId);
    await refresh();
  }

  /// Creates or updates a trip (the id decides which).
  Future<void> addTrip(Trip trip) async {
    await _repo.saveTrip(trip);
    await refresh();
  }

  Future<void> removeTrip(String tripId) async {
    await _repo.deleteTrip(tripId);
    await refresh();
  }

  /// This trip's entries, newest first — for the trip detail view.
  List<Entry> entriesForTrip(String tripId) {
    final list = _entries.where((e) => e.tripId == tripId).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  int entryCountForTrip(String tripId) =>
      _entries.where((e) => e.tripId == tripId).length;

  /// Creates or renames a companion (the id decides which).
  Future<void> addPerson(Person person) async {
    await _repo.savePerson(person);
    await refresh();
  }

  Future<void> removePerson(String personId) async {
    await _repo.deletePerson(personId);
    await refresh();
  }

  /// The trips a person was on.
  List<Trip> tripsWithPerson(String personId) =>
      trips.where((t) => t.companions.any((p) => p.id == personId)).toList();

  /// All records from trips this person was on, newest first — the places you
  /// went together.
  List<Entry> entriesWithPerson(String personId) {
    final tripIds = tripsWithPerson(personId).map((t) => t.id).toSet();
    final list = _entries.where((e) => tripIds.contains(e.tripId)).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  // Signing a URL is a network round trip; cache the Future per path so a list
  // that rebuilds many times doesn't re-sign the same image over and over.
  final Map<String, Future<String?>> _imageUrls = {};

  /// A displayable URL for a stored image path (cached for the session).
  Future<String?> imageUrl(String storagePath) =>
      _imageUrls.putIfAbsent(storagePath, () => _repo.imageUrl(storagePath));

  /// Uploads a jpg and returns its storage path, for entries that carry one.
  /// [index] disambiguates the several images one record can hold.
  Future<String> uploadImage({
    required String tripId,
    required String entryId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
    int index = 0,
  }) =>
      _repo.uploadImage(
        tripId: tripId,
        entryId: entryId,
        bytes: bytes,
        contentType: contentType,
        index: index,
      );
}
