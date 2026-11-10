-- Hiello photo notifications. Paste this whole file into Supabase > SQL Editor > New query > Run.
-- Run it AFTER schema.sql. Safe to run again.
--
-- What it does: whenever something happens in a family (a new Hiello, Grandpa's heart, note, RSVP or
-- "seen", or a hi sent back), the database quietly asks the "hiello-push" Edge Function to send a
-- notification, with the photo in it, to everyone else in that family who allowed notifications.
-- Nothing here is visible to the app's public key.

create extension if not exists pg_net with schema extensions;

-- a private shared secret, so only this database can ask the Edge Function to send notifications
create table if not exists public.hi_private (
  key   text primary key,
  value text not null
);
alter table public.hi_private enable row level security;
revoke all on public.hi_private from public, anon, authenticated;
insert into public.hi_private(key, value)
values ('push_hook', encode(extensions.gen_random_bytes(24), 'hex'))
on conflict (key) do nothing;

create or replace function public.hi_push_send(p_kind text, p_id uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare hook text;
begin
  select value into hook from hi_private where key = 'push_hook';
  perform net.http_post(
    url     := 'https://zhscyfqolceqnlyhffoc.supabase.co/functions/v1/hiello-push',
    body    := jsonb_build_object('kind', p_kind, 'id', p_id, 'hook', hook),
    headers := '{"Content-Type":"application/json"}'::jsonb,
    timeout_milliseconds := 8000
  );
exception when others then
  null;  -- a notification must never stop a Hiello from being saved
end $$;
revoke all on function public.hi_push_send(text, uuid) from public, anon, authenticated;

create or replace function public.hi_push_posts() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform hi_push_send('post', new.id);
  elsif new.gp_note is not null and new.gp_note is distinct from old.gp_note then
    perform hi_push_send('note', new.id);
  elsif new.hearts > old.hearts then
    perform hi_push_send('heart', new.id);
  elsif new.rsvp is not null and new.rsvp is distinct from old.rsvp then
    perform hi_push_send('rsvp', new.id);
  elsif new.watched_at is not null and old.watched_at is null then
    perform hi_push_send('seen', new.id);
  end if;
  return null;
end $$;

drop trigger if exists hi_push_posts on public.posts;
create trigger hi_push_posts after insert or update on public.posts
  for each row execute function public.hi_push_posts();

create or replace function public.hi_push_replies() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform hi_push_send('reply', new.id);
  return null;
end $$;

drop trigger if exists hi_push_replies on public.replies;
create trigger hi_push_replies after insert on public.replies
  for each row execute function public.hi_push_replies();
