-- Hiello: keeping Circles safe (App Store Guideline 1.2).
-- Paste this whole file into Supabase > SQL Editor > New query > Run. Run it after schema.sql and circle.sql.
-- Safe to run again.
--
--   reports          : every "Report this hi" lands here. Check it once a day (Table Editor > reports).
--   blocks           : "Hide this person" — their hi's and replies stop showing on that one phone and its widget.
--   blocked_words    : words that can't be posted in notes, captions or replies. Add rows to add words.
--   hi_report        : report a hi or a reply
--   hi_block         : hide / unhide a person (on your phone only)
--   hi_remove_member : the person who started the Circle removes someone (their hi's and replies go too)
--   hi_feed, hi_widget_feed, hi_add_post, hi_add_reply : same as before, now with hiding and the word filter

create table if not exists public.reports (
  id          uuid primary key default gen_random_uuid(),
  family_id   uuid not null references public.families(id) on delete cascade,
  member_id   uuid references public.members(id) on delete set null,
  reported_member uuid references public.members(id) on delete set null,
  post_id     uuid references public.posts(id) on delete set null,
  reply_id    uuid references public.replies(id) on delete set null,
  reason      text not null default '',
  created_at  timestamptz not null default now(),
  handled_at  timestamptz
);
alter table public.reports enable row level security;

create table if not exists public.blocks (
  member_id   uuid not null references public.members(id) on delete cascade,
  blocked_id  uuid not null references public.members(id) on delete cascade,
  family_id   uuid not null references public.families(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (member_id, blocked_id)
);
alter table public.blocks enable row level security;

create table if not exists public.blocked_words (word text primary key);
alter table public.blocked_words enable row level security;
insert into public.blocked_words(word) values
  ('fuck'),('fucking'),('motherfucker'),('shit'),('bitch'),('cunt'),('whore'),('slut'),('dick'),('pussy'),('cock'),
  ('porn'),('nude'),('nudes'),('kys'),('kill yourself'),('retard')
on conflict do nothing;

-- true when the text contains a blocked word (whole words, any case)
create or replace function public.hi_is_unkind(p_text text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from blocked_words w
                 where lower(coalesce(p_text,'')) ~ ('(^|[^a-z])' || regexp_replace(lower(w.word), '([.*+?^${}()|\[\]\\])', '\\\1', 'g') || '($|[^a-z])'));
$$;

create or replace function public.hi_report(p_fid uuid, p_sec text, p_member uuid, p_post uuid, p_reply uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare who uuid;
begin
  perform hi_family(p_fid, p_sec);
  if p_post is not null then select member_id into who from posts where id = p_post and family_id = p_fid; end if;
  if who is null and p_reply is not null then select member_id into who from replies where id = p_reply and family_id = p_fid; end if;
  insert into reports(family_id, member_id, reported_member, post_id, reply_id, reason)
  values (p_fid, p_member, who, p_post, p_reply, left(coalesce(p_reason,''), 200));
end $$;

create or replace function public.hi_block(p_fid uuid, p_sec text, p_member uuid, p_target uuid, p_on boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform hi_family(p_fid, p_sec);
  if p_target = p_member then return; end if;
  if p_on then
    insert into blocks(member_id, blocked_id, family_id) values (p_member, p_target, p_fid) on conflict do nothing;
  else
    delete from blocks where member_id = p_member and blocked_id = p_target;
  end if;
end $$;

-- Only the person who started the Circle (its first member) can remove someone.
-- Returns the removed person's photo files so the app can delete them from storage.
create or replace function public.hi_remove_member(p_fid uuid, p_sec text, p_member uuid, p_target uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare owner uuid; files text[];
begin
  perform hi_family(p_fid, p_sec);
  select id into owner from members where family_id = p_fid order by created_at limit 1;
  if owner is distinct from p_member then raise exception 'Only the person who started the Circle can remove someone.' using errcode = '42501'; end if;
  if p_target = p_member then raise exception 'You can''t remove yourself. Use Leave this Circle.'; end if;
  select coalesce(array_agg(x), '{}') into files from (
    select unnest(array[media_path, thumb_path]) x from posts   where family_id = p_fid and member_id = p_target
    union all
    select unnest(array[media_path, thumb_path]) x from replies where family_id = p_fid and member_id = p_target) t where x is not null;
  delete from replies where family_id = p_fid and member_id = p_target;
  delete from posts   where family_id = p_fid and member_id = p_target;
  delete from members where family_id = p_fid and id = p_target;
  return jsonb_build_object('files', to_jsonb(files));
end $$;

-- ---------- the feeds, now leaving out people you've hidden ----------
create or replace function public.hi_feed(p_fid uuid, p_sec text, p_member uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f families;
begin
  perform hi_family(p_fid, p_sec);
  update members set last_seen = now() where id = p_member and family_id = p_fid;
  select * into f from families where id = p_fid;
  return jsonb_build_object(
    'gp_name', f.gp_name,
    'members', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'role',role,'last_seen',last_seen) order by created_at) from members where family_id = p_fid), '[]'),
    'hidden',  coalesce((select jsonb_agg(blocked_id) from blocks where member_id = p_member), '[]'),
    'posts',   coalesce((select jsonb_agg(hi_post_json(p) order by p.created_at desc) from (
                 select * from posts where family_id = p_fid
                   and (member_id is null or member_id not in (select blocked_id from blocks where member_id = p_member))
                 order by created_at desc limit 200) p), '[]'),
    'replies', coalesce((select jsonb_agg(hi_reply_json(r) order by r.created_at desc) from (
                 select * from replies where family_id = p_fid
                   and (member_id is null or member_id not in (select blocked_id from blocks where member_id = p_member))
                 order by created_at desc limit 100) r), '[]'));
end $$;

create or replace function public.hi_widget_feed(p_fid uuid, p_sec text, p_member uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f families;
begin
  perform hi_family(p_fid, p_sec);
  select * into f from families where id = p_fid;
  return jsonb_build_object(
    'gp_name', f.gp_name,
    'posts',   coalesce((select jsonb_agg(hi_post_json(p) order by coalesce(p.shown_at, p.created_at) desc)
                 from (select * from posts where family_id = p_fid and (p_member is null or member_id is distinct from p_member)
                         and (p_member is null or member_id is null or member_id not in (select blocked_id from blocks where member_id = p_member))
                       order by coalesce(shown_at, created_at) desc limit 12) p), '[]'),
    'replies', coalesce((select jsonb_agg(hi_reply_json(r) order by r.created_at desc)
                 from (select * from replies where family_id = p_fid and (p_member is null or member_id is distinct from p_member)
                         and (p_member is null or member_id is null or member_id not in (select blocked_id from blocks where member_id = p_member))
                       order by created_at desc limit 6) r), '[]'));
end $$;

-- ---------- posting, now with the word filter ----------
create or replace function public.hi_add_post(p_fid uuid, p_sec text, p_member uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare row posts; nm text;
begin
  perform hi_family(p_fid, p_sec);
  if hi_is_unkind(p->>'note') or hi_is_unkind(p->>'caption') or hi_is_unkind(p->>'title') then
    raise exception 'unkind: Let''s keep it kind. Try different words.' using errcode = 'P0001';
  end if;
  select name into nm from members where id = p_member and family_id = p_fid;
  insert into posts(family_id, member_id, from_name, note, caption, tpl, sx, sy, kind, title, when_at, media_kind, media_path, thumb_path)
  values (p_fid, p_member, coalesce(nm, p->>'from_name', ''), left(coalesce(p->>'note',''), 80), left(coalesce(p->>'caption',''), 400),
          coalesce(p->>'tpl','polaroid'), coalesce((p->>'sx')::real, 50), coalesce((p->>'sy')::real, 80), coalesce(p->>'kind','everyday'),
          left(coalesce(p->>'title',''), 80), coalesce(p->>'when_at',''), p->>'media_kind', p->>'media_path', p->>'thumb_path')
  returning * into row;
  return hi_post_json(row);
end $$;

create or replace function public.hi_add_reply(p_fid uuid, p_sec text, p_member uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare row replies; nm text;
begin
  perform hi_family(p_fid, p_sec);
  if hi_is_unkind(p->>'note') then
    raise exception 'unkind: Let''s keep it kind. Try different words.' using errcode = 'P0001';
  end if;
  select name into nm from members where id = p_member and family_id = p_fid;
  insert into replies(family_id, member_id, from_name, note, media_kind, media_path, thumb_path, reply_to)
  values (p_fid, p_member, coalesce(nm, p->>'from_name', ''), left(coalesce(p->>'note',''), 80), p->>'media_kind', p->>'media_path', p->>'thumb_path',
          nullif(p->>'reply_to','')::uuid)
  returning * into row;
  return hi_reply_json(row);
end $$;

grant execute on function public.hi_report(uuid,text,uuid,uuid,uuid,text) to anon, authenticated;
grant execute on function public.hi_block(uuid,text,uuid,uuid,boolean) to anon, authenticated;
grant execute on function public.hi_remove_member(uuid,text,uuid,uuid) to anon, authenticated;
grant execute on function public.hi_feed(uuid,text,uuid) to anon, authenticated;
grant execute on function public.hi_widget_feed(uuid,text,uuid) to anon, authenticated;
grant execute on function public.hi_add_post(uuid,text,uuid,jsonb) to anon, authenticated;
grant execute on function public.hi_add_reply(uuid,text,uuid,jsonb) to anon, authenticated;
revoke execute on function public.hi_is_unkind(text) from anon, authenticated;
