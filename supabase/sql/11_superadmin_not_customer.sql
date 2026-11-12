-- BreakApp 11: i Super Admin sono operatori globali, mai clienti del bar.
-- Il guard opera sul server e blocca anche INSERT diretti con privilegi elevati.
-- Nessun ordine esistente viene eliminato o modificato.
begin;

create or replace function app_private.prevent_platform_admin_customer_orders()
returns trigger
language plpgsql security definer set search_path=''
as $block_superadmin_customer$
begin
  if exists (
    select 1 from app_private.platform_admins p
    where p.user_id=new.customer_id
  ) then
    raise exception 'Il Super Admin non può effettuare ordini come Cliente'
      using errcode='42501';
  end if;
  return new;
end;
$block_superadmin_customer$;

revoke all on function app_private.prevent_platform_admin_customer_orders()
from public,anon,authenticated;

drop trigger if exists orders_block_superadmin_customer on public.orders;
create trigger orders_block_superadmin_customer
before insert or update of customer_id on public.orders
for each row execute function app_private.prevent_platform_admin_customer_orders();

commit;
