-- Hiello: a join code for Apple's reviewers that lasts a year (normal codes stop working after 7 days).
-- Step 1 — run this to see your Circles and who's in each:
--   select f.id, f.created_at::date, (select string_agg(name, ', ' order by created_at) from members m where m.family_id = f.id) as people,
--          (select count(*) from posts p where p.family_id = f.id) as hi_count
--   from families f order by hi_count desc;
-- Step 2 — copy the id of YOUR Circle (the one with your name and the most hi's), paste it below, and run:
insert into public.codes (code, family_id, role, expires_at)
values ('418726', 'PASTE-YOUR-CIRCLE-ID-HERE', 'family', now() + interval '365 days')
on conflict (code) do update set family_id = excluded.family_id, expires_at = excluded.expires_at;
-- Reviewers then tap "I have a code" and type 418 726. Delete this row after the app is approved:
--   delete from public.codes where code = '418726';
