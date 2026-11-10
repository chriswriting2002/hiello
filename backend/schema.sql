-- Hiello Family backend (Supabase). Paste this whole file into Supabase > SQL Editor > New query > Run.
-- Safe to run again: it only creates what's missing and replaces the functions.
--
-- Security model: there are no passwords. Each family has a long random secret (48 hex chars).
-- A phone gets the secret only by entering a 6-digit family code that expires after 7 days.
-- The app's public key can do nothing on its own: tables are locked (row-level security on, no policies),
-- and every read/write goes through the functions below, which all check the family secret first.
-- Photos live in a private storage bucket, in a folder named after the family secret.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.families (
  id          uuid primary key default gen_random_uuid(),
  secret      text not null unique default encode(extensions.gen_random_bytes(24), 'hex'),
  gp_name     text not null default 'Grandpa',
  created_at  timestamptz not null default now()
);

create table if not exists public.members (
  id          uuid primary key default gen_random_uuid(),
  family_id   uuid not null references public.families(id) on delete cascade,
  name        text not null,
  role        text not null check (role in ('gp','family')),
  push_token  text,
  created_at  timestamptz not null default now(),
  last_seen   timestamptz
);

create table if not exists public.codes (
  code        text primary key,
  family_id   uuid not null references public.families(id) on delete cascade,
  role        text not null check (role in ('gp','family')),
  expires_at  timestamptz not null
);

create table if not exists public.posts (
  id          uuid primary key default gen_random_uuid(),
  family_id   uuid not null references public.families(id) on delete cascade,
  member_id   uuid references public.members(id) on delete set null,
  from_name   text not null default '',
  note        text not null default '',
  caption     text not null default '',
  tpl         text not null default 'polaroid',
  sx          real not null default 50,
  sy          real not null default 80,
  kind        text not null default 'everyday',
  title       text not null default '',
  when_at     text not null default '',
  media_kind  text,
  media_path  text,
  thumb_path  text,
  created_at  timestamptz not null default now(),
  watched_at  timestamptz,
  hearts      int not null default 0,
  rsvp        text,
  gp_note     text,
  gp_note_at  timestamptz
);
create index if not exists posts_family_time on public.posts (family_id, created_at desc);

create table if not exists public.replies (
  id          uuid primary key default gen_random_uuid(),
  family_id   uuid not null references public.families(id) on delete cascade,
  member_id   uuid references public.members(id) on delete set null,
  from_name   text not null default '',
  note        text not null default '',
  media_kind  text,
  media_path  text,
  thumb_path  text,
  reply_to    uuid references public.posts(id) on delete set null,
  created_at  timestamptz not null default now(),
  seen_by     uuid[] not null default '{}'
);
create index if not exists replies_family_time on public.replies (family_id, created_at desc);

-- Lock every table: the public key can't read or write them directly.
alter table public.families enable row level security;
alter table public.members  enable row level security;
alter table public.codes    enable row level security;
alter table public.posts    enable row level security;
alter table public.replies  enable row level security;

-- ---------- helpers ----------
create or replace function public.hi_family(p_fid uuid, p_sec text) returns uuid
language plpgsql security definer set search_path = public as $$
declare f uuid;
begin
  select id into f from families where id = p_fid and secret = p_sec;
  if f is null then raise exception 'not a member of this family' using errcode = '42501'; end if;
  return f;
end $$;

create or replace function public.hi_new_code(p_fid uuid, p_role text) returns text
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  delete from codes where expires_at < now();
  loop
    c := lpad((floor(random() * 1000000))::int::text, 6, '0');
    exit when not exists (select 1 from codes where code = c);
  end loop;
  insert into codes(code, family_id, role, expires_at) values (c, p_fid, p_role, now() + interval '7 days');
  return c;
end $$;

-- storage policy helper: is this folder name a real family secret?
create or replace function public.hi_is_family_folder(p_folder text) returns boolean
language sql security definer set search_path = public stable as $$
  select exists (select 1 from families where secret = p_folder);
$$;

create or replace function public.hi_post_json(p posts) returns jsonb language sql stable as $$
  select jsonb_build_object('id',p.id,'member_id',p.member_id,'from_name',p.from_name,'note',p.note,'caption',p.caption,'tpl',p.tpl,
    'sx',p.sx,'sy',p.sy,'kind',p.kind,'title',p.title,'when_at',p.when_at,'media_kind',p.media_kind,'media_path',p.media_path,
    'thumb_path',p.thumb_path,'created_at',p.created_at,'watched_at',p.watched_at,'hearts',p.hearts,'rsvp',p.rsvp,
    'gp_note',p.gp_note,'gp_note_at',p.gp_note_at);
$$;

create or replace function public.hi_reply_json(r replies) returns jsonb language sql stable as $$
  select jsonb_build_object('id',r.id,'member_id',r.member_id,'from_name',r.from_name,'note',r.note,'media_kind',r.media_kind,
    'media_path',r.media_path,'thumb_path',r.thumb_path,'reply_to',r.reply_to,'created_at',r.created_at,'seen_by',r.seen_by);
$$;

-- ---------- starting and joining a family ----------
create or replace function public.hi_create_family(p_gp_name text, p_my_name text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f families; m uuid;
begin
  insert into families(gp_name) values (coalesce(nullif(trim(p_gp_name),''),'Grandpa')) returning * into f;
  insert into members(family_id, name, role) values (f.id, coalesce(nullif(trim(p_my_name),''),'Family'), 'family') returning id into m;
  return jsonb_build_object('family_id', f.id, 'secret', f.secret, 'member_id', m, 'role', 'family', 'gp_name', f.gp_name,
    'gp_code', hi_new_code(f.id, 'gp'), 'family_code', hi_new_code(f.id, 'family'));
end $$;

create table if not exists public.join_attempts (ip text not null, at timestamptz not null default now());
alter table public.join_attempts enable row level security;
create index if not exists join_attempts_ip on public.join_attempts (ip, at);

-- Wrong codes are counted per connection: 10 misses in 15 minutes and that connection has to wait.
-- (Errors are returned, not raised, so the miss is still recorded.)
create or replace function public.hi_join_family(p_code text, p_name text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c codes; f families; m uuid; nm text; v_ip text; tries int;
begin
  v_ip := coalesce(split_part(current_setting('request.headers', true)::json->>'x-forwarded-for', ',', 1), 'unknown');
  delete from join_attempts where at < now() - interval '1 day';
  select count(*) into tries from join_attempts where join_attempts.ip = v_ip and at > now() - interval '15 minutes';
  if tries >= 10 then return jsonb_build_object('error', 'Too many tries. Please wait 15 minutes and try again.'); end if;
  select * into c from codes where code = regexp_replace(p_code, '\D', '', 'g') and expires_at > now();
  if c.code is null then
    insert into join_attempts(ip) values (v_ip);
    return jsonb_build_object('error', 'That code didn''t work. Check the numbers or ask for a new code.');
  end if;
  select * into f from families where id = c.family_id;
  nm := coalesce(nullif(trim(p_name),''), case when c.role = 'gp' then f.gp_name else 'Family' end);
  insert into members(family_id, name, role) values (f.id, nm, c.role) returning id into m;
  return jsonb_build_object('family_id', f.id, 'secret', f.secret, 'member_id', m, 'role', c.role, 'gp_name', f.gp_name, 'name', nm);
end $$;

create or replace function public.hi_make_code(p_fid uuid, p_sec text, p_role text) returns text
language plpgsql security definer set search_path = public as $$
begin
  perform hi_family(p_fid, p_sec);
  if p_role not in ('gp','family') then raise exception 'bad role'; end if;
  return hi_new_code(p_fid, p_role);
end $$;

create or replace function public.hi_set_gp_name(p_fid uuid, p_sec text, p_name text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform hi_family(p_fid, p_sec);
  update families set gp_name = coalesce(nullif(trim(p_name),''), gp_name) where id = p_fid;
end $$;

-- ---------- reading ----------
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
    'posts',   coalesce((select jsonb_agg(hi_post_json(p) order by p.created_at desc) from (select * from posts where family_id = p_fid order by created_at desc limit 200) p), '[]'),
    'replies', coalesce((select jsonb_agg(hi_reply_json(r) order by r.created_at desc) from (select * from replies where family_id = p_fid order by created_at desc limit 100) r), '[]'));
end $$;

-- a lighter feed for the home screen widget
create or replace function public.hi_widget_feed(p_fid uuid, p_sec text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f families;
begin
  perform hi_family(p_fid, p_sec);
  select * into f from families where id = p_fid;
  return jsonb_build_object(
    'gp_name', f.gp_name,
    'posts',   coalesce((select jsonb_agg(hi_post_json(p) order by p.created_at desc) from (select * from posts where family_id = p_fid order by created_at desc limit 12) p), '[]'),
    'replies', coalesce((select jsonb_agg(hi_reply_json(r) order by r.created_at desc) from (select * from replies where family_id = p_fid order by created_at desc limit 6) r), '[]'));
end $$;

-- ---------- writing ----------
create or replace function public.hi_add_post(p_fid uuid, p_sec text, p_member uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare row posts; nm text;
begin
  perform hi_family(p_fid, p_sec);
  select name into nm from members where id = p_member and family_id = p_fid;
  insert into posts(family_id, member_id, from_name, note, caption, tpl, sx, sy, kind, title, when_at, media_kind, media_path, thumb_path)
  values (p_fid, p_member, coalesce(nm, p->>'from_name', ''), left(coalesce(p->>'note',''), 80), left(coalesce(p->>'caption',''), 400),
          coalesce(p->>'tpl','polaroid'), coalesce((p->>'sx')::real, 50), coalesce((p->>'sy')::real, 80), coalesce(p->>'kind','everyday'),
          left(coalesce(p->>'title',''), 80), coalesce(p->>'when_at',''), p->>'media_kind', p->>'media_path', p->>'thumb_path')
  returning * into row;
  return hi_post_json(row);
end $$;

create or replace function public.hi_watched(p_fid uuid, p_sec text, p_post uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform hi_family(p_fid, p_sec);
  update posts set watched_at = coalesce(watched_at, now()) where id = p_post and family_id = p_fid;
end $$;

create or replace function public.hi_heart(p_fid uuid, p_sec text, p_post uuid) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  perform hi_family(p_fid, p_sec);
  update posts set hearts = hearts + 1, watched_at = coalesce(watched_at, now()) where id = p_post and family_id = p_fid returning hearts into n;
  return coalesce(n, 0);
end $$;

create or replace function public.hi_note(p_fid uuid, p_sec text, p_post uuid, p_text text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform hi_family(p_fid, p_sec);
  update posts set gp_note = nullif(left(trim(p_text), 40), ''), gp_note_at = now(), watched_at = coalesce(watched_at, now())
  where id = p_post and family_id = p_fid;
end $$;

create or replace function public.hi_rsvp(p_fid uuid, p_sec text, p_post uuid, p_ans text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform hi_family(p_fid, p_sec);
  update posts set rsvp = case when p_ans in ('yes','recap') then p_ans else null end where id = p_post and family_id = p_fid;
end $$;

create or replace function public.hi_add_reply(p_fid uuid, p_sec text, p_member uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare row replies; nm text;
begin
  perform hi_family(p_fid, p_sec);
  select name into nm from members where id = p_member and family_id = p_fid;
  insert into replies(family_id, member_id, from_name, note, media_kind, media_path, thumb_path, reply_to)
  values (p_fid, p_member, coalesce(nm, p->>'from_name', ''), left(coalesce(p->>'note',''), 80), p->>'media_kind', p->>'media_path', p->>'thumb_path',
          nullif(p->>'reply_to','')::uuid)
  returning * into row;
  return hi_reply_json(row);
end $$;

create or replace function public.hi_replies_seen(p_fid uuid, p_sec text, p_member uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform hi_family(p_fid, p_sec);
  update replies set seen_by = array_append(seen_by, p_member) where family_id = p_fid and not (p_member = any(seen_by));
end $$;

create or replace function public.hi_set_push(p_fid uuid, p_sec text, p_member uuid, p_token text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform hi_family(p_fid, p_sec);
  update members set push_token = p_token where id = p_member and family_id = p_fid;
end $$;

create or replace function public.hi_leave(p_fid uuid, p_sec text, p_member uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform hi_family(p_fid, p_sec);
  delete from members where id = p_member and family_id = p_fid;
end $$;

-- Only these entry points are callable with the app's public key.
revoke all on function public.hi_family(uuid,text), public.hi_new_code(uuid,text), public.hi_post_json(posts), public.hi_reply_json(replies) from public, anon, authenticated;
grant execute on function
  public.hi_create_family(text,text), public.hi_join_family(text,text), public.hi_make_code(uuid,text,text),
  public.hi_set_gp_name(uuid,text,text), public.hi_feed(uuid,text,uuid), public.hi_widget_feed(uuid,text),
  public.hi_add_post(uuid,text,uuid,jsonb), public.hi_watched(uuid,text,uuid), public.hi_heart(uuid,text,uuid),
  public.hi_note(uuid,text,uuid,text), public.hi_rsvp(uuid,text,uuid,text), public.hi_add_reply(uuid,text,uuid,jsonb),
  public.hi_replies_seen(uuid,text,uuid), public.hi_set_push(uuid,text,uuid,text), public.hi_leave(uuid,text,uuid),
  public.hi_is_family_folder(text)
to anon, authenticated;

-- ---------- private photo storage ----------
insert into storage.buckets (id, name, public, file_size_limit)
values ('media', 'media', false, 62914560)
on conflict (id) do nothing;

drop policy if exists "hiello read family media" on storage.objects;
create policy "hiello read family media" on storage.objects for select to anon, authenticated
  using (bucket_id = 'media' and public.hi_is_family_folder((storage.foldername(name))[1]));

drop policy if exists "hiello add family media" on storage.objects;
create policy "hiello add family media" on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'media' and public.hi_is_family_folder((storage.foldername(name))[1]));
