# CLAUDE.md

Guidance for working in this repository. Read this first; it captures the
concepts that aren't obvious from any single file.

## What this is

**旅行日志 / TravelLog** — a cross-platform travel journal (iOS / Android /
Windows / Web from one Flutter codebase). You collect **records** (places,
photos, drawings, stories, essays) into **trips**, see them on a map, browse
them by type or by travel companion. Backend is **Supabase** (auth + Postgres +
Storage) with per-user data isolation via Row Level Security.

Status: early skeleton (`version: 0.1.0`). Much of the schema and several code
comments are written for a **local-first sync engine that does not exist yet** —
see "Design intent" below so you don't mistake groundwork for dead code.

## Architecture (the one thing to understand)

Data flows through a single seam so the storage backend can be swapped without
touching any screen:

```
Screens ──> AppState (ChangeNotifier) ──> TravelRepository (interface)
                                              ├── SupabaseTravelRepository  (real: Postgres/Storage)
                                              └── MockTravelRepository      (in-memory: tests + "sample" mode)
```

- **`lib/data/travel_repository.dart`** — the abstract interface. `AppState`
  talks *only* to this, never to Supabase directly. The planned local-first
  cache/sync engine is meant to slot in here as a third implementation.
- **`lib/state/app_state.dart`** — holds the loaded snapshot (trips / people /
  entries) plus the shared filters (type / trip / companion). Every mutation
  (`addEntry`, `removeTrip`, …) calls the repo then `refresh()` — a full reload,
  not an optimistic in-memory patch. Deliberately simple for now.
- **`lib/screens/auth_gate.dart`** — the *only* place the repository is chosen.
  Signed in → `SupabaseTravelRepository`; "browse sample" → `MockTravelRepository`.
  A `ValueKey` tied to the user id forces a fresh `AppState` (and reload) when
  identity changes. `main.dart` can also inject a repository directly, which
  bypasses the auth gate — that path is for widget tests only.

## Domain model (`lib/models/`)

- **Entry** — one record inside a trip. All three main views are just different
  queries over the entry collection. `type` is an `EntryType` enum
  (`place/photo/drawing/story/essay`). `drawing` is **not** an in-app canvas — it
  is a jpg upload through the same pipeline as `photo` (`isImageBacked`).
  `displayTitle` derives a heading (title → place name → body snippet → type
  label) because the entry form no longer collects a title.
- **Trip** — groups entries; carries `companions` (`List<Person>`).
- **Person** — a travel companion. **Companions live on the trip, not the
  entry** (changed in migration 0002 — see below). "Who you travelled with" is a
  property of the trip.
- **GeoPoint** — lat/lng + place name; `.latLng` bridges to `flutter_map`.

## Key behaviors worth knowing

- **Map (`map_screen.dart`)** collapses markers into per-trip **clusters** when
  zoomed out (below `_recordZoom`) and shows individual records when zoomed in.
  Tapping empty space at street zoom (`_addZoom`) starts a new record there;
  below that, a tap just zooms in. Record pins are a uniform translucent-white
  teardrop; trips are connected by a thin grey dashed route line and told apart
  by their cluster colour when zoomed out.
- **Auto-trip assignment (`entry_form.dart`)** — a new record with a location
  auto-selects the trip whose nearest existing record is within
  `_autoSelectKm = 50` km; trip chips are ordered nearest-first.
- **Browse (`browse_screen.dart`)** — two modes: by type, and by companion
  (places visited *together* — an entry matches if its trip lists that person).

## Backend & security (`supabase/`, `lib/config/`)

- **RLS is the security boundary, not the key.** The `publishableKey` in
  `supabase_config.dart` is a client key meant to ship in the app. **Never** put
  the `service_role` key (which bypasses RLS) anywhere in this repo or client
  code. Both values can be overridden at build time:
  `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...`.
- **Migrations run in order** in the Supabase SQL Editor. `0001_init.sql` is the
  base schema; `0002_trip_companions.sql` moved companions from per-entry
  (`entry_companions`, dropped) to per-trip (`trip_companions`).
- **`is_trip_member(trip_id)`** is a `SECURITY DEFINER` function used by nearly
  every policy; it's defined that way on purpose to avoid RLS recursion.
- **Storage**: private `travel-media` bucket. Path convention
  `{trip_id}/{entry_id}/{filename}.jpg` is **load-bearing** — storage policies
  read the first segment to reuse the trip-membership rule. Display needs a
  time-limited signed URL (`imageUrl`), cached per path in `AppState`.

## Design intent (groundwork for features not yet built)

Don't "clean these up" — they're intentional:

- **Soft deletes**: `deleted_at` instead of row removal, so a deletion is a
  syncable fact. RLS deliberately does **not** filter `deleted_at`; the
  *client* filters soft-deleted rows in `SupabaseTravelRepository.loadAll()`.
  The future sync engine needs to see the tombstones.
- **Client-generated UUIDs** (`uuid` package): records have a stable identity
  before ever reaching the server, so offline creation works.
- **`updated_at`** (kept honest by a trigger) is there to drive incremental
  "give me everything newer than X" pulls.
- **`trip_members`** table + `is_trip_member` allow for sharing a trip with
  other users later; today only the owner path is exercised.
- **PostGIS** `location` column (generated from lat/lng) + GiST index exist for
  future viewport queries; the app currently loads all entries and filters in
  Dart.

## Conventions

- **Code comments and identifiers are in English; all user-facing strings are in
  Chinese** (e.g. `'新增记录'`, nav titles `['地图','旅途','浏览']`). Match this —
  don't translate UI strings to English or comments to Chinese.
- Material 3, seed color `0xFF3D8D7A`. `HomeShell` switches between a phone
  layout and a compact desktop layout at a 720px breakpoint.
- Widget tests inject `MockTravelRepository` and an offline `TileProvider` so
  they never touch the network or Supabase. Follow that pattern for new tests.

## Commands

```bash
flutter pub get
flutter run -d chrome        # web
flutter run -d windows       # desktop
flutter run                  # connected device / emulator

flutter analyze              # lint (CI gate)
flutter test                 # widget tests (CI gate)
```

CI (`.github/workflows/ci.yml`) runs `flutter analyze` + `flutter test` on every
push/PR (Flutter 3.44.7, stable). `deploy-pages.yml` publishes a web preview to
GitHub Pages; `keepalive.yml` pings Supabase daily so the free-tier project
isn't auto-paused (~7 days idle).

## Directory map

```
lib/
├── config/   Supabase connection (publishable key + build-time overrides)
├── data/     TravelRepository interface + Supabase / mock impls + mock_data
├── models/   Entry, EntryType, Trip, Person, GeoPoint
├── screens/  auth_gate, home_shell, map / trips / browse, entry & trip forms, pickers
├── state/    AppState (ChangeNotifier)
└── widgets/  entry_card, entry_image (reusable pieces)
supabase/migrations/   0001 base schema + RLS, 0002 companions → trip level
scripts/   supabase_keepalive.ps1 (local equivalent of the keepalive workflow)
```
