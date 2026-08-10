-- ---------------------------------------------------------------------------
-- 0003 — multiple images per entry
--
-- A record's default format is now [image + text] with up to four images, so
-- entries need a list of image paths rather than a single one. We add an
-- `image_paths` array and backfill it from the existing `image_path`.
--
-- The old `image_path` column is kept (not dropped): the client keeps writing
-- the first image into it too, so any reader still on the old schema — or a
-- half-migrated device — continues to see a cover image. It can be dropped in a
-- later migration once nothing reads it.
-- ---------------------------------------------------------------------------

alter table public.entries
  add column if not exists image_paths text[] not null default '{}';

-- Backfill: existing single-image rows become one-element arrays.
update public.entries
   set image_paths = array[image_path]
 where image_path is not null
   and (image_paths is null or image_paths = '{}');
