-- Travel log — initial schema.
--
-- Three rules applied to every table here, because retrofitting them later is
-- painful once devices hold local copies:
--   1. Primary keys are client-generated UUIDs, so a record created offline has
--      a stable identity before it ever reaches the server.
--   2. `updated_at` drives incremental pull ("give me everything newer than X").
--   3. `deleted_at` soft-deletes, so a deletion is a syncable fact rather than
--      an absence other devices cannot observe.

create extension if not exists postgis;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Keeps `updated_at` honest regardless of what the client sends.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- trips
-- ---------------------------------------------------------------------------

create table public.trips (
  id            uuid primary key,
  owner_id      uuid not null references auth.users (id) on delete cascade,
  title         text not null,
  start_date    date not null,
  end_date      date,
  cover_path    text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

create index trips_owner_idx on public.trips (owner_id);
create index trips_updated_idx on public.trips (updated_at);

-- ---------------------------------------------------------------------------
-- trip_members — the seam for sharing a trip with other people later
-- ---------------------------------------------------------------------------

create table public.trip_members (
  trip_id     uuid not null references public.trips (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  role        text not null default 'viewer' check (role in ('viewer', 'editor')),
  created_at  timestamptz not null default now(),
  primary key (trip_id, user_id)
);

create index trip_members_user_idx on public.trip_members (user_id);

-- ---------------------------------------------------------------------------
-- people — travel companions, owned by the user who created them
-- ---------------------------------------------------------------------------

create table public.people (
  id          uuid primary key,
  owner_id    uuid not null references auth.users (id) on delete cascade,
  name        text not null,
  avatar_path text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

create index people_owner_idx on public.people (owner_id);
create index people_updated_idx on public.people (updated_at);

-- ---------------------------------------------------------------------------
-- entries — the one table all three views query, just filtered differently
-- ---------------------------------------------------------------------------

create table public.entries (
  id           uuid primary key,
  trip_id      uuid not null references public.trips (id) on delete cascade,
  author_id    uuid not null references auth.users (id) on delete cascade,

  -- text, not an enum: adding a record type later is a one-line constraint
  -- change instead of an ALTER TYPE dance.
  type         text not null
                 check (type in ('place', 'photo', 'drawing', 'story', 'essay')),

  title        text not null default '',
  body         text not null default '',
  occurred_at  timestamptz not null,

  place_name   text,
  lat          double precision,
  lng          double precision,
  -- Derived, so clients only ever write plain lat/lng. Gives PostGIS a real
  -- spatial index for "entries inside the current map viewport".
  location     geography(point, 4326)
                 generated always as (
                   case
                     when lat is null or lng is null then null
                     else st_point(lng, lat)::geography
                   end
                 ) stored,

  image_path   text,
  marker_glyph text not null default '📍',
  tags         text[] not null default '{}',

  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);

create index entries_trip_idx on public.entries (trip_id);
create index entries_occurred_idx on public.entries (occurred_at desc);
create index entries_type_idx on public.entries (type);
create index entries_updated_idx on public.entries (updated_at);
create index entries_location_idx on public.entries using gist (location);
create index entries_tags_idx on public.entries using gin (tags);

-- ---------------------------------------------------------------------------
-- entry_companions — many-to-many: who was with you on each record
-- ---------------------------------------------------------------------------

create table public.entry_companions (
  entry_id   uuid not null references public.entries (id) on delete cascade,
  person_id  uuid not null references public.people (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (entry_id, person_id)
);

create index entry_companions_person_idx on public.entry_companions (person_id);

-- ---------------------------------------------------------------------------
-- Membership test used by nearly every policy below.
--
-- Defined here, after the tables: a `language sql` body is validated the moment
-- the function is created, so it cannot mention tables that do not exist yet.
--
-- SECURITY DEFINER on purpose: it bypasses RLS on `trips`/`trip_members`, which
-- is what stops the policies from recursing into themselves (a trips policy that
-- queried trips under RLS would re-trigger the same policy forever).
-- ---------------------------------------------------------------------------

create or replace function public.is_trip_member(p_trip_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.trips t
    where t.id = p_trip_id and t.owner_id = auth.uid()
  ) or exists (
    select 1 from public.trip_members m
    where m.trip_id = p_trip_id and m.user_id = auth.uid()
  );
$$;

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------------

create trigger trips_touch    before update on public.trips
  for each row execute function public.touch_updated_at();
create trigger people_touch   before update on public.people
  for each row execute function public.touch_updated_at();
create trigger entries_touch  before update on public.entries
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Row level security
--
-- Enabled on every table in the same breath as the table itself. A table with
-- RLS off is readable and writable by anyone holding the public anon key.
--
-- Note: no policy filters on `deleted_at`. The sync engine must be able to SEE
-- soft-deleted rows in order to replicate the deletion; hiding them here would
-- make deletes invisible to other devices. The UI filters them out locally.
-- ---------------------------------------------------------------------------

alter table public.trips            enable row level security;
alter table public.trip_members     enable row level security;
alter table public.people           enable row level security;
alter table public.entries          enable row level security;
alter table public.entry_companions enable row level security;

-- trips ---------------------------------------------------------------------

create policy trips_select on public.trips
  for select using (owner_id = auth.uid() or public.is_trip_member(id));

create policy trips_insert on public.trips
  for insert with check (owner_id = auth.uid());

create policy trips_update on public.trips
  for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy trips_delete on public.trips
  for delete using (owner_id = auth.uid());

-- trip_members --------------------------------------------------------------

create policy trip_members_select on public.trip_members
  for select using (
    user_id = auth.uid()
    or exists (select 1 from public.trips t
               where t.id = trip_id and t.owner_id = auth.uid())
  );

-- Only the trip owner hands out access.
create policy trip_members_write on public.trip_members
  for all using (
    exists (select 1 from public.trips t
            where t.id = trip_id and t.owner_id = auth.uid())
  ) with check (
    exists (select 1 from public.trips t
            where t.id = trip_id and t.owner_id = auth.uid())
  );

-- people --------------------------------------------------------------------

create policy people_all on public.people
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- entries -------------------------------------------------------------------

create policy entries_select on public.entries
  for select using (public.is_trip_member(trip_id));

create policy entries_insert on public.entries
  for insert with check (author_id = auth.uid() and public.is_trip_member(trip_id));

create policy entries_update on public.entries
  for update using (public.is_trip_member(trip_id))
  with check (public.is_trip_member(trip_id));

create policy entries_delete on public.entries
  for delete using (public.is_trip_member(trip_id));

-- entry_companions ----------------------------------------------------------

create policy entry_companions_all on public.entry_companions
  for all using (
    exists (select 1 from public.entries e
            where e.id = entry_id and public.is_trip_member(e.trip_id))
  ) with check (
    exists (select 1 from public.entries e
            where e.id = entry_id and public.is_trip_member(e.trip_id))
  );

-- ---------------------------------------------------------------------------
-- Storage: photos and drawings
--
-- Path convention is `{trip_id}/{entry_id}/{filename}.jpg`, which lets the same
-- trip-membership rule govern file access without a second permission model.
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('travel-media', 'travel-media', false)
on conflict (id) do nothing;

create policy travel_media_read on storage.objects
  for select using (
    bucket_id = 'travel-media'
    and public.is_trip_member(((storage.foldername(name))[1])::uuid)
  );

create policy travel_media_write on storage.objects
  for insert with check (
    bucket_id = 'travel-media'
    and public.is_trip_member(((storage.foldername(name))[1])::uuid)
  );

create policy travel_media_delete on storage.objects
  for delete using (
    bucket_id = 'travel-media'
    and public.is_trip_member(((storage.foldername(name))[1])::uuid)
  );
