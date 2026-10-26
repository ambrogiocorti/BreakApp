-- BreakApp 12: preparazione pilot via Super Admin AAL2.
-- Permessi sempre verificati sul server, nessun grant generalizzato su auth.users.
begin;

create table if not exists app_private.platform_staff_audit(
 id bigint generated always as identity primary key,
 actor_id uuid not null references auth.users(id) on delete restrict,
 target_id uuid not null references auth.users(id) on delete restrict,
 school_id uuid not null references public.schools(id) on delete restrict,
 role_code text not null check(role_code in ('school_admin','bartender','warehouse_manager')),
 action text not null check(action in ('role_assigned','role_revoked')),
 created_at timestamptz not null default now()
);
alter table app_private.platform_staff_audit enable row level security;
revoke all on app_private.platform_staff_audit from public,anon,authenticated;

create or replace function app_private.platform_approved()
returns boolean language sql stable security definer set search_path=''
as $check_platform$
 select (select auth.uid()) is not null and (select auth.jwt()->>'aal')='aal2'
 and exists(select 1 from app_private.platform_admins a where a.user_id=(select auth.uid()));
$check_platform$;
revoke all on function app_private.platform_approved() from public,anon,authenticated;

create or replace function public.platform_assign_school_staff(
 p_school_id uuid,p_email text,p_role text
) returns jsonb language plpgsql security definer set search_path=''
as $assign_staff$
declare v_target uuid;v_membership uuid;v_email text;
begin
 if not app_private.platform_approved() then raise exception 'Super Admin e 2FA richiesti';end if;
 if p_school_id is null or not exists(select 1 from public.schools where id=p_school_id and is_active)
 then raise exception 'Scuola inesistente o non attiva';end if;
 if p_role not in ('school_admin','bartender','warehouse_manager') or p_role is null
 then raise exception 'Ruolo personale non valido';end if;
 v_email:=lower(btrim(coalesce(p_email,'')));
 if length(v_email)>255 or v_email!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
 then raise exception 'Indirizzo email non valido';end if;
 select u.id into v_target from auth.users u
 where lower(u.email)=v_email and u.email_confirmed_at is not null;
 if not found then
  raise exception 'Utente non trovato: deve prima registrarsi e confermare la sua email';
 end if;
 if exists(select 1 from app_private.platform_admins pa where pa.user_id=v_target)
 then raise exception 'Un Super Admin non può ricevere ruoli scolastici';end if;

 insert into public.school_memberships(school_id,user_id,membership_status)
 values(p_school_id,v_target,'active')
 on conflict(school_id,user_id) do update set membership_status='active'
 returning id into v_membership;
 insert into public.role_assignments(membership_id,role_code)
 values(v_membership,p_role) on conflict(membership_id,role_code) do nothing;
 insert into app_private.platform_staff_audit(actor_id,target_id,school_id,role_code,action)
 values(auth.uid(),v_target,p_school_id,p_role,'role_assigned');
 return jsonb_build_object('email',v_email,'role',p_role,'school_id',p_school_id);
end;
$assign_staff$;

create or replace function public.platform_list_school_staff(p_school_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $list_staff$
declare v_result jsonb;
begin
 if not app_private.platform_approved() then raise exception 'Super Admin e 2FA richiesti';end if;
 if not exists(select 1 from public.schools where id=p_school_id)
 then raise exception 'Scuola sconosciuta';end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'user_id',u.id,'email',u.email,'role',r.role_code,
  'status',m.membership_status
 ) order by u.email,r.role_code),'[]'::jsonb)
 into v_result
 from public.school_memberships m
 join auth.users u on u.id=m.user_id
 join public.role_assignments r on r.membership_id=m.id
 where m.school_id=p_school_id and r.role_code in
 ('school_admin','bartender','warehouse_manager')
 and not exists(select 1 from app_private.platform_admins pa where pa.user_id=u.id);
 return v_result;
end;
$list_staff$;

create or replace function public.platform_revoke_school_staff(
 p_school_id uuid,p_user_id uuid,p_role text
) returns void language plpgsql security definer set search_path=''
as $revoke_staff$
declare v_membership uuid;
begin
 if not app_private.platform_approved() then raise exception 'Super Admin e 2FA richiesti';end if;
 if p_role not in ('school_admin','bartender','warehouse_manager') or p_role is null
 then raise exception 'Ruolo non valido';end if;
 select id into v_membership from public.school_memberships
 where school_id=p_school_id and user_id=p_user_id for update;
 if not found then raise exception 'Assegnazione inesistente';end if;
 delete from public.role_assignments
 where membership_id=v_membership and role_code=p_role;
 if not found then raise exception 'Ruolo già non assegnato';end if;
 insert into app_private.platform_staff_audit(actor_id,target_id,school_id,role_code,action)
 values(auth.uid(),p_user_id,p_school_id,p_role,'role_revoked');
end;
$revoke_staff$;

-- Consenti al Super Admin AAL2 di effettuare operazioni globali di servizio,
-- SENZA aggiungerlo a una school_membership. Le verifiche RPC dei clienti e il
-- trigger orders_block_superadmin_customer continuano a impedirgli di ordinare.
create or replace function app_private.can_operate_bar(
 p_school_id uuid,p_admin_only boolean default false
) returns boolean language sql stable security definer set search_path=''
as $can_bar$
 select (select auth.uid()) is not null
 and (
   ((select auth.jwt()->>'aal')='aal2' and exists(
     select 1 from app_private.platform_admins pa
     where pa.user_id=(select auth.uid())
   ))
   or exists(select 1 from public.school_memberships m
     join public.role_assignments r on r.membership_id=m.id
     where m.school_id=p_school_id and m.user_id=(select auth.uid())
       and m.membership_status='active'
       and ((r.role_code='school_admin' and (select auth.jwt()->>'aal')='aal2')
            or (not p_admin_only and r.role_code='bartender')))
 );
$can_bar$;
revoke all on function app_private.can_operate_bar(uuid,boolean) from public,anon,authenticated;

create or replace function public.platform_create_pickup_window(
 p_bar_id uuid,p_date date,p_start time,p_end time
) returns uuid language plpgsql security definer set search_path=''
as $create_window$
declare v_bar public.bars%rowtype;v_school public.schools%rowtype;v_id uuid;
begin
 if not app_private.platform_approved() then raise exception 'Super Admin e 2FA richiesti';end if;
 if p_date is null or p_start is null or p_end is null or p_start>=p_end then
  raise exception 'Data e fascia non valide';end if;
 select * into v_bar from public.bars where id=p_bar_id and is_active for update;
 if not found then raise exception 'Bar non attivo';end if;
 select * into v_school from public.schools where id=v_bar.school_id and is_active;
 if not found then raise exception 'Scuola non attiva';end if;
 if p_date<(now() at time zone v_school.timezone)::date or
    p_date>(now() at time zone v_school.timezone)::date+v_school.booking_horizon_days
 then raise exception 'La data non rientra nel periodo di prenotazione';end if;
 insert into public.pickup_windows(school_id,bar_id,service_date,starts_at,ends_at)
 values(v_bar.school_id,v_bar.id,p_date,p_start,p_end)
 on conflict(bar_id,service_date,starts_at) do nothing
 returning id into v_id;
 if v_id is null then
   select id into v_id from public.pickup_windows
    where bar_id=v_bar.id and service_date=p_date and starts_at=p_start and ends_at=p_end and is_active;
 end if;
 if v_id is null then raise exception 'Esiste una fascia incompatibile o disattivata';end if;
 return v_id;
end;
$create_window$;

create or replace function public.platform_set_stock(
 p_bar_id uuid,p_product_id uuid,p_date date,p_capacity integer
) returns void language plpgsql security definer set search_path=''
as $stock$
declare v_bar public.bars%rowtype;v_school public.schools%rowtype;
begin
 if not app_private.platform_approved() then raise exception 'Super Admin e 2FA richiesti';end if;
 if p_product_id is null or p_date is null or (p_capacity is not null and p_capacity<0)
 then raise exception 'Scorte non valide';end if;
 select * into v_bar from public.bars where id=p_bar_id and is_active for update;
 if not found then raise exception 'Bar non attivo';end if;
 if not exists(select 1 from public.products p where p.id=p_product_id
 and p.school_id=v_bar.school_id and p.bar_id=v_bar.id and p.is_active)
 then raise exception 'Prodotto inesistente, disattivato o di altra scuola';end if;
 select * into v_school from public.schools where id=v_bar.school_id;
 if p_date<(now() at time zone v_school.timezone)::date or
    p_date>(now() at time zone v_school.timezone)::date+v_school.booking_horizon_days
 then raise exception 'Scorte fuori dall''orizzonte prenotabile';end if;
 insert into public.daily_stock(school_id,bar_id,product_id,service_date,capacity)
 values(v_bar.school_id,v_bar.id,p_product_id,p_date,p_capacity)
 on conflict(bar_id,product_id,service_date)
 do update set capacity=excluded.capacity,updated_at=now();
 -- DB check prevents reducing below allocated. No direct write to allocated.
end;
$stock$;

create or replace function public.platform_set_product_foodinfo(
 p_product_id uuid,p_ingredients text,p_allergens text[]
) returns void language plpgsql security definer set search_path=''
as $food_info$
begin
 if not app_private.platform_approved() then raise exception 'Super Admin e 2FA richiesti';end if;
 if p_product_id is null or char_length(btrim(coalesce(p_ingredients,'')))<3
 or char_length(p_ingredients)>3000 or p_allergens is null
 then raise exception 'Ingredienti/allergeni non validi';end if;
 update public.products set ingredients=btrim(p_ingredients),
   allergens=p_allergens
 where id=p_product_id;
 if not found then raise exception 'Prodotto inesistente';end if;
 -- Existing check constraint validates legal allergen codes.
end;
$food_info$;

revoke all on function public.platform_assign_school_staff(uuid,text,text),
 public.platform_list_school_staff(uuid),
 public.platform_revoke_school_staff(uuid,uuid,text),
 public.platform_create_pickup_window(uuid,date,time,time),
 public.platform_set_stock(uuid,uuid,date,integer),
 public.platform_set_product_foodinfo(uuid,text,text[])
from public,anon,authenticated;
grant execute on function public.platform_assign_school_staff(uuid,text,text),
 public.platform_list_school_staff(uuid),
 public.platform_revoke_school_staff(uuid,uuid,text),
 public.platform_create_pickup_window(uuid,date,time,time),
 public.platform_set_stock(uuid,uuid,date,integer),
 public.platform_set_product_foodinfo(uuid,text,text[])
to authenticated;
commit;
