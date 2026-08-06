-- Companions move from the entry level to the trip level.
--
-- Rationale: a travel companion is "who you were travelling with", which is a
-- property of the trip, not of each individual photo/note. This replaces the
-- per-entry entry_companions link with a per-trip trip_companions link.
--
-- Safe to drop entry_companions outright: the app never shipped with real data
-- in it, and no other table references it.

drop table if exists public.entry_companions;

-- ---------------------------------------------------------------------------
-- trip_companions — many-to-many: which people were on a trip
-- ---------------------------------------------------------------------------

create table public.trip_companions (
  trip_id    uuid not null references public.trips (id) on delete cascade,
  person_id  uuid not null references public.people (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (trip_id, person_id)
);

create index trip_companions_person_idx on public.trip_companions (person_id);

alter table public.trip_companions enable row level security;

-- Anyone who can see the trip can see who was on it.
create policy trip_companions_select on public.trip_companions
  for select using (public.is_trip_member(trip_id));

-- Only the trip owner edits the companion list (people are owner-scoped, so the
-- owner is the only one who can reference their own people rows anyway).
create policy trip_companions_write on public.trip_companions
  for all using (
    exists (select 1 from public.trips t
            where t.id = trip_id and t.owner_id = auth.uid())
  ) with check (
    exists (select 1 from public.trips t
            where t.id = trip_id and t.owner_id = auth.uid())
  );
