begin;
alter table public.orders drop constraint orders_payment_status_check;
alter table public.orders add constraint orders_payment_status_check check(payment_status in ('due','paid','refund_pending','refunded'));
create or replace function app_private.refresh_individual_balance(p_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare o public.orders%rowtype;v_paid bigint;v_has_credit boolean;v_pending boolean;
begin
 select * into o from public.orders where id=p_id for update;
 if not found then return;end if;
 v_paid:=app_private.order_paid_cents('individual',p_id);
 select exists(select 1 from public.payment_refunds r join public.payment_attempts a on a.id=r.payment_id where a.order_id=p_id)
  or exists(select 1 from public.cash_refund_obligations where order_id=p_id) into v_has_credit;
 select exists(select 1 from public.payment_refunds r join public.payment_attempts a on a.id=r.payment_id where a.order_id=p_id and r.status<>'succeeded')
  or exists(select 1 from public.cash_refund_obligations where order_id=p_id and status<>'returned') into v_pending;
 update public.orders set payment_status=case
  when o.status in ('cancelled','no_show','delivered') and v_paid=0 and v_has_credit then case when v_pending then 'refund_pending' else 'refunded' end
  when v_paid>=total_cents then 'paid' else 'due' end,updated_at=now() where id=p_id;
end;$$;
revoke all on function app_private.refresh_individual_balance(uuid) from public,anon,authenticated,service_role;
do $$declare d text;name text;begin
 foreach name in array array['app_private.refund_order_credit(text,uuid,uuid,bigint,uuid,text)','app_private.refund_order_online(text,uuid,text)'] loop
  d:=pg_get_functiondef(name::regprocedure);
  d:=replace(d,E'\nend;',E'\n if p_kind=''individual'' then perform app_private.refresh_individual_balance(p_id);end if;\nend;');execute d;
 end loop;
 d:=pg_get_functiondef('public.confirm_cash_refund_return(uuid,text)'::regprocedure);
 d:=replace(d,E'\nend;',E'\n if r.order_id is not null then perform app_private.refresh_individual_balance(r.order_id);end if;\nend;');execute d;
 d:=pg_get_functiondef('public.finalize_verified_stripe_refund(text,text,uuid,text,text,bigint,text,text)'::regprocedure);
 d:=replace(d,$old$  if p_status='succeeded' and (select coalesce(sum(amount_cents),0) from public.payment_refunds where payment_id=a.id and status='succeeded')>=a.amount_cents
  and (select count(*) from public.payment_attempts where order_id=a.order_id and status='succeeded')=1
  and app_private.order_paid_cents('individual',a.order_id)=0
  then update public.orders set payment_status='refunded' where id=a.order_id;end if;$old$,'');execute d;
end;$$;
select app_private.refresh_individual_balance(o.id) from public.orders o where
 exists(select 1 from public.payment_refunds r join public.payment_attempts a on a.id=r.payment_id where a.order_id=o.id)
 or exists(select 1 from public.cash_refund_obligations where order_id=o.id);
commit;
