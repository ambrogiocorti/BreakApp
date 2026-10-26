-- BreakApp 10: attestazione server per il contesto Super Admin nella UI.
-- Un booleano non conferisce privilegi; tutte le funzioni amministrative
-- globali richiederanno comunque controllo server su app_private.platform_admins.
begin;
create or replace function public.is_current_platform_admin()
returns boolean language sql stable security definer set search_path=''
as $platform_identity$
  select (select auth.uid()) is not null
    and (select auth.jwt()->>'aal')='aal2'
    and exists (
      select 1 from app_private.platform_admins p
      where p.user_id=(select auth.uid())
    );
$platform_identity$;
revoke all on function public.is_current_platform_admin() from public,anon,authenticated;
grant execute on function public.is_current_platform_admin() to authenticated;
commit;
