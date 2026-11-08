-- BreakApp: stato del merchant scolastico aggiornato dagli eventi Stripe firmati.
-- Prima charges_enabled/payouts_enabled si impostavano a mano dopo l'onboarding.
-- Ora l'evento Connect `account.updated` (firma verificata dalla Edge Function)
-- aggiorna soltanto un merchant già associato a una scuola: non crea né sposta
-- associazioni. Gli eventi arrivano senza ordine garantito: si applica solo uno
-- snapshot più recente dell'ultimo registrato. Ogni evento passa dall'inbox
-- idempotente e i cambi di stato restano tracciati.
alter table public.school_stripe_merchants
 add column if not exists status_event_created bigint,
 add column if not exists details_submitted boolean not null default false;

create table if not exists app_private.stripe_merchant_status_audit(
 id bigint generated always as identity primary key,
 school_id uuid not null references public.schools(id) on delete restrict,
 stripe_account_id text not null,
 event_id text not null,
 charges_enabled boolean not null,
 payouts_enabled boolean not null,
 details_submitted boolean not null,
 created_at timestamptz not null default now()
);
create index if not exists stripe_merchant_status_audit_school_idx
 on app_private.stripe_merchant_status_audit(school_id,created_at desc);
alter table app_private.stripe_merchant_status_audit enable row level security;
revoke all on app_private.stripe_merchant_status_audit from public,anon,authenticated;

create or replace function public.apply_signed_stripe_account_status(
 p_event text,p_account text,p_created bigint,
 p_charges boolean,p_payouts boolean,p_details boolean
) returns text language plpgsql security definer set search_path=''
as $account_status$
declare v_merchant public.school_stripe_merchants%rowtype;
begin
 if p_event is null or p_event !~ '^evt_[A-Za-z0-9]+$'
   or p_account is null or p_account !~ '^acct_[A-Za-z0-9]+$'
   or p_created is null or p_created<=0
   or p_charges is null or p_payouts is null or p_details is null
 then raise exception 'Evento account Stripe non valido';end if;
 insert into app_private.stripe_webhook_inbox(event_id,stripe_account_id,event_type,payload)
 values(p_event,p_account,'account.updated',jsonb_build_object(
  'created',p_created,'charges_enabled',p_charges,
  'payouts_enabled',p_payouts,'details_submitted',p_details))
 on conflict(event_id) do nothing;
 if not found then return 'duplicate';end if;
 select * into v_merchant from public.school_stripe_merchants
  where stripe_account_id=p_account for update;
 if not found then
  update app_private.stripe_webhook_inbox set processed_at=now(),
   error_text='Account non associato a una scuola' where event_id=p_event;
  return 'unknown_account';
 end if;
 if v_merchant.status_event_created is not null and p_created<v_merchant.status_event_created then
  update app_private.stripe_webhook_inbox set processed_at=now(),
   error_text='Snapshot più vecchio dell''ultimo applicato' where event_id=p_event;
  return 'stale';
 end if;
 update public.school_stripe_merchants set
  charges_enabled=p_charges,payouts_enabled=p_payouts,details_submitted=p_details,
  status_event_created=p_created,
  verified_at=case when p_charges and p_payouts then coalesce(verified_at,now()) else null end
 where school_id=v_merchant.school_id;
 insert into app_private.stripe_merchant_status_audit(
  school_id,stripe_account_id,event_id,charges_enabled,payouts_enabled,details_submitted)
 values(v_merchant.school_id,p_account,p_event,p_charges,p_payouts,p_details);
 update app_private.stripe_webhook_inbox set processed_at=now() where event_id=p_event;
 return 'applied';
end;
$account_status$;
revoke all on function public.apply_signed_stripe_account_status(text,text,bigint,boolean,boolean,boolean)
 from public,anon,authenticated;
grant execute on function public.apply_signed_stripe_account_status(text,text,bigint,boolean,boolean,boolean)
 to service_role;
