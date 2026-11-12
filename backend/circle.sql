-- Hiello: your hi's and your name. Paste this whole file into Supabase > SQL Editor > New query > Run.
-- Run it after schema.sql. Safe to run again.
--
--   hi_show_again : put one of your own hi's back on everyone's widget
--   hi_delete_post: delete one of your own hi's (the app then removes its photo files)
--   hi_set_name   : change your name; your past hi's and replies get the new name too
-- It also turns every old Easy-mode (grandparent) member into a regular member, since Easy mode is off.

alter table public.posts add column if not exists shown_at timestamptz;

create or replace function public.hi_post_json(p posts) returns jsonb language sql stable as $$
  select jsonb_build_object('id',p.id,'member_id',p.member_id,'from_name',p.from_name,'note',p.note,'caption',p.caption,'tpl',p.tpl,
    'sx',p.sx,'sy',p.sy,'kind',p.kind,'title',p.title,'when_at',p.when_at,'media_kind',p.media_kind,'media_path',p.media_path,
    'thumb_path',p.thumb_path,'created_at',p.created_at,'watched_at',p.watched_at,'hearts',p.hearts,'rsvp',p.rsvp,
    'gp_note',p.gp_note,'gp_note_at',p.gp_note_at,'shown_at',p.shown_at);
$$;

-- the widget's feed: a hi put back on the widget counts as new
create or replace function public.hi_widget_feed(p_fid uuid, p_sec text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f families;
begin
  perform hi_family(p_fid, p_sec);
  select * into f from families where id = p_fid;
  return jsonb_build_object(
    'gp_name', f.gp_name,
    'posts',   coalesce((select jsonb_agg(hi_post_json(p) order by coalesce(p.shown_at, p.created_at) desc)
                 from (select * from posts where family_id = p_fid order by coalesce(shown_at, created_at) desc limit 12) p), '[]'),
    'replies', coalesce((select jsonb_agg(hi_reply_json(r) order by r.created_at desc)
                 from (select * from replies where family_id = p_fid order by created_at desc limit 6) r), '[]'));
end $$;

create or replace function public.hi_show_again(p_fid uuid, p_sec text, p_member uuid, p_post uuid) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  perform hi_family(p_fid, p_sec);
  update posts set shown_at = now() where id = p_post and family_id = p_fid and member_id = p_member;
  return found;
end $$;

create or replace function public.hi_delete_post(p_fid uuid, p_sec text, p_member uuid, p_post uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare files jsonb;
begin
  perform hi_family(p_fid, p_sec);
  select coalesce(jsonb_agg(x), '[]'::jsonb) into files from (
    select media_path as x from posts where id = p_post and family_id = p_fid and member_id = p_member and media_path is not null
    union select thumb_path from posts where id = p_post and family_id = p_fid and member_id = p_member and thumb_path is not null) f;
  delete from posts where id = p_post and family_id = p_fid and member_id = p_member;
  return jsonb_build_object('deleted', found, 'files', files);
end $$;

create or replace function public.hi_set_name(p_fid uuid, p_sec text, p_member uuid, p_name text) returns text
language plpgsql security definer set search_path = public as $$
declare nm text := left(trim(coalesce(p_name, '')), 20);
begin
  perform hi_family(p_fid, p_sec);
  if nm = '' then return null; end if;
  update members set name = nm where id = p_member and family_id = p_fid;
  update posts   set from_name = nm where member_id = p_member and family_id = p_fid;
  update replies set from_name = nm where member_id = p_member and family_id = p_fid;
  return nm;
end $$;

grant execute on function public.hi_show_again(uuid,text,uuid,uuid), public.hi_delete_post(uuid,text,uuid,uuid),
  public.hi_set_name(uuid,text,uuid,text) to anon, authenticated;

-- Easy mode is off: everyone is a regular member now
update public.members set role = 'family' where role = 'gp';
