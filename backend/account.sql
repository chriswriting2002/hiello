-- Hiello: delete your account. Paste this whole file into Supabase > SQL Editor > New query > Run.
-- Run it after schema.sql. Safe to run again.
--
-- Deleting works in two steps so the photo files really go away:
--   1. hi_my_files lists the storage files that belong to you (or to the whole Circle if you're the last one).
--      The app deletes those files from storage (allowed by the policy below).
--   2. hi_delete_me removes your photos, replies and membership. If nobody is left, the Circle itself is deleted.

create or replace function public.hi_my_files(p_fid uuid, p_sec text, p_member uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare last_one boolean; files jsonb;
begin
  perform hi_family(p_fid, p_sec);
  select not exists (select 1 from members where family_id = p_fid and id <> p_member) into last_one;
  select coalesce(jsonb_agg(path), '[]'::jsonb) into files from (
    select media_path as path from posts where family_id = p_fid and (last_one or member_id = p_member) and media_path is not null
    union select thumb_path from posts where family_id = p_fid and (last_one or member_id = p_member) and thumb_path is not null
    union select media_path from replies where family_id = p_fid and (last_one or member_id = p_member) and media_path is not null
    union select thumb_path from replies where family_id = p_fid and (last_one or member_id = p_member) and thumb_path is not null
  ) f;
  return jsonb_build_object('files', files, 'last_one', last_one);
end $$;

create or replace function public.hi_delete_me(p_fid uuid, p_sec text, p_member uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare last_one boolean;
begin
  perform hi_family(p_fid, p_sec);
  delete from posts where family_id = p_fid and member_id = p_member;
  delete from replies where family_id = p_fid and member_id = p_member;
  delete from members where family_id = p_fid and id = p_member;
  select not exists (select 1 from members where family_id = p_fid) into last_one;
  if last_one then delete from families where id = p_fid; end if;   -- everything else in the Circle goes with it
  return jsonb_build_object('deleted', true, 'circle_deleted', last_one);
end $$;

grant execute on function public.hi_my_files(uuid,text,uuid), public.hi_delete_me(uuid,text,uuid) to anon, authenticated;

-- let the app remove files in its own Circle's folder (the folder name is the Circle's private secret)
drop policy if exists "hiello delete family media" on storage.objects;
create policy "hiello delete family media" on storage.objects for delete to anon, authenticated
  using (bucket_id = 'media' and public.hi_is_family_folder((storage.foldername(name))[1]));
