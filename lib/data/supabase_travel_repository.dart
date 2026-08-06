import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/entry.dart';
import '../models/entry_type.dart';
import '../models/geo_point.dart';
import '../models/person.dart';
import '../models/trip.dart';
import 'travel_repository.dart';

/// Talks to Postgres over PostgREST.
///
/// Every read filters out soft-deleted rows *here*, in the client — deliberately
/// not in the RLS policies, which must keep exposing `deleted_at` rows so the
/// future sync engine can replicate deletions to other devices.
class SupabaseTravelRepository implements TravelRepository {
  final SupabaseClient _db;

  SupabaseTravelRepository([SupabaseClient? client])
      : _db = client ?? Supabase.instance.client;

  static const _bucket = 'travel-media';

  @override
  Future<TravelSnapshot> loadAll() async {
    final tripRows = await _db
        .from('trips')
        .select()
        .isFilter('deleted_at', null)
        .order('start_date', ascending: false);

    final peopleRows = await _db
        .from('people')
        .select()
        .isFilter('deleted_at', null)
        .order('name');

    final entryRows = await _db
        .from('entries')
        .select()
        .isFilter('deleted_at', null)
        .order('occurred_at', ascending: false);

    // The trip↔companion links, in one shot — the join Firestore couldn't do.
    final companionRows =
        await _db.from('trip_companions').select('trip_id, person_id');

    final people = peopleRows.map(_personFrom).toList();
    final peopleById = {for (final p in people) p.id: p};

    // Group companions by trip so each Trip can be built with its own list.
    final companionsByTrip = <String, List<Person>>{};
    for (final row in companionRows) {
      final person = peopleById[row['person_id'] as String];
      if (person == null) continue;
      (companionsByTrip[row['trip_id'] as String] ??= []).add(person);
    }

    return TravelSnapshot(
      trips: tripRows.map((r) => _tripFrom(r, companionsByTrip)).toList(),
      people: people,
      entries: entryRows.map(_entryFrom).toList(),
    );
  }

  @override
  Future<void> saveTrip(Trip trip) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Not signed in — cannot save a trip.');
    }

    await _db.from('trips').upsert({
      'id': trip.id,
      'owner_id': userId,
      'title': trip.title,
      // date columns, not timestamps — send the calendar day only.
      'start_date': _dateOnly(trip.startDate),
      'end_date': trip.endDate == null ? null : _dateOnly(trip.endDate!),
      'cover_path': trip.coverImagePath,
    });

    // Replace the companion set wholesale: simpler than diffing, table is tiny.
    await _db.from('trip_companions').delete().eq('trip_id', trip.id);
    if (trip.companions.isNotEmpty) {
      await _db.from('trip_companions').insert([
        for (final p in trip.companions)
          {'trip_id': trip.id, 'person_id': p.id},
      ]);
    }
  }

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Future<void> saveEntry(Entry entry) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Not signed in — cannot save an entry.');
    }

    await _db.from('entries').upsert({
      'id': entry.id,
      'trip_id': entry.tripId,
      'author_id': userId,
      'type': entry.type.name,
      'title': entry.title,
      'body': entry.body,
      'occurred_at': entry.timestamp.toUtc().toIso8601String(),
      'place_name': entry.location?.placeName,
      'lat': entry.location?.lat,
      'lng': entry.location?.lng,
      'image_path': entry.imagePath,
      'marker_glyph': entry.markerGlyph,
      'tags': entry.tags,
    });
  }

  @override
  Future<void> deleteTrip(String tripId) async {
    // Soft delete, so other devices can replicate the removal. Cascade to the
    // trip's entries too, otherwise they'd be orphaned (their trip is gone).
    final ts = DateTime.now().toUtc().toIso8601String();
    await _db.from('entries').update({'deleted_at': ts}).eq('trip_id', tripId);
    await _db.from('trips').update({'deleted_at': ts}).eq('id', tripId);
  }

  @override
  Future<void> savePerson(Person person) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Not signed in — cannot save a person.');
    }

    await _db.from('people').upsert({
      'id': person.id,
      'owner_id': userId,
      'name': person.name,
      'avatar_path': person.avatarPath,
    });
  }

  @override
  Future<void> deletePerson(String personId) async {
    // Remove the person from every trip, then soft-delete the person.
    await _db.from('trip_companions').delete().eq('person_id', personId);
    await _db.from('people').update({
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', personId);
  }

  @override
  Future<void> deleteEntry(String entryId) async {
    await _db
        .from('entries')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', entryId);
  }

  @override
  Future<String> uploadImage({
    required String tripId,
    required String entryId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    // `{trip_id}/...` first segment is load-bearing: the storage policies read
    // it to decide access, reusing the same trip-membership rule as the tables.
    final path = '$tripId/$entryId/${DateTime.now().millisecondsSinceEpoch}.jpg';

    await _db.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );

    return path;
  }

  @override
  Future<String?> imageUrl(String storagePath) async {
    // The bucket is private, so a time-limited signed URL is the only way to
    // display the file in an <img>/Image.network.
    try {
      return await _db.storage
          .from(_bucket)
          .createSignedUrl(storagePath, const Duration(hours: 1).inSeconds);
    } catch (_) {
      return null;
    }
  }

  // ---- row → model ----------------------------------------------------------

  Person _personFrom(Map<String, dynamic> r) => Person(
        id: r['id'] as String,
        name: r['name'] as String,
        avatarPath: r['avatar_path'] as String?,
      );

  Trip _tripFrom(
          Map<String, dynamic> r, Map<String, List<Person>> companionsByTrip) =>
      Trip(
        id: r['id'] as String,
        title: r['title'] as String,
        startDate: DateTime.parse(r['start_date'] as String),
        endDate: r['end_date'] == null
            ? null
            : DateTime.parse(r['end_date'] as String),
        coverImagePath: r['cover_path'] as String?,
        companions: companionsByTrip[r['id'] as String] ?? const [],
      );

  Entry _entryFrom(Map<String, dynamic> r) {
    final lat = (r['lat'] as num?)?.toDouble();
    final lng = (r['lng'] as num?)?.toDouble();

    return Entry(
      id: r['id'] as String,
      tripId: r['trip_id'] as String,
      type: EntryType.values.byName(r['type'] as String),
      title: r['title'] as String? ?? '',
      body: r['body'] as String? ?? '',
      timestamp: DateTime.parse(r['occurred_at'] as String).toLocal(),
      location: (lat == null || lng == null)
          ? null
          : GeoPoint(
              lat: lat,
              lng: lng,
              placeName: r['place_name'] as String? ?? '',
            ),
      tags: List<String>.from(r['tags'] as List? ?? const []),
      imagePath: r['image_path'] as String?,
      markerGlyph: r['marker_glyph'] as String? ?? '📍',
    );
  }
}
