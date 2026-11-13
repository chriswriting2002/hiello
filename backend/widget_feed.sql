-- Hiello: the widget's feed leaves out your own hi's, so your own recent posts can't crowd out everyone else's.
-- Paste into Supabase > SQL Editor > New query > Run. Safe to run again.
drop function if exists public.hi_widget_feed(uuid, text);
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
                       order by coalesce(shown_at, created_at) desc limit 12) p), '[]'),
    'replies', coalesce((select jsonb_agg(hi_reply_json(r) order by r.created_at desc)
                 from (select * from replies where family_id = p_fid and (p_member is null or member_id is distinct from p_member)
                       order by created_at desc limit 6) r), '[]'));
end $$;
grant execute on function public.hi_widget_feed(uuid, text, uuid) to anon, authenticated;
