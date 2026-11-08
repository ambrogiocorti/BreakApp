-- account.updated: only an associated merchant changes, duplicates and stale
-- snapshots are ignored, clients cannot call the RPC.
insert into public.schools(id,slug,name) values
 ('97000000-0000-4000-8000-000000000001','ci-stripe-status','CI Stripe status')
on conflict(id) do nothing;
insert into public.school_stripe_merchants(school_id,stripe_account_id,charges_enabled,payouts_enabled)
values('97000000-0000-4000-8000-000000000001','acct_CiStatusSync',false,false);
do $status_sync$
declare r text;m public.school_stripe_merchants%rowtype;denied boolean:=false;
 v_account text;
begin
 select stripe_account_id into v_account from public.school_stripe_merchants
  where school_id='97000000-0000-4000-8000-000000000001';
 r:=public.apply_signed_stripe_account_status('evt_CiStatus2',v_account,200,true,true,true);
 if r<>'applied' then raise exception 'Status not applied: %',r;end if;
 select * into m from public.school_stripe_merchants where stripe_account_id=v_account;
 if not(m.charges_enabled and m.payouts_enabled and m.details_submitted) or m.verified_at is null
 then raise exception 'Merchant flags not updated';end if;
 r:=public.apply_signed_stripe_account_status('evt_CiStatus2',v_account,200,false,false,false);
 if r<>'duplicate' then raise exception 'Duplicate event not detected: %',r;end if;
 r:=public.apply_signed_stripe_account_status('evt_CiStatus1',v_account,100,false,false,false);
 if r<>'stale' then raise exception 'Stale snapshot applied: %',r;end if;
 select * into m from public.school_stripe_merchants where stripe_account_id=v_account;
 if not m.charges_enabled then raise exception 'Stale snapshot changed the merchant';end if;
 r:=public.apply_signed_stripe_account_status('evt_CiStatus3',v_account,300,false,true,true);
 select * into m from public.school_stripe_merchants where stripe_account_id=v_account;
 if r<>'applied' or m.charges_enabled or m.verified_at is not null
 then raise exception 'Disabled charges not recorded';end if;
 r:=public.apply_signed_stripe_account_status('evt_CiStatus4','acct_NotLinkedAnywhere',400,true,true,true);
 if r<>'unknown_account' then raise exception 'Unknown account handled as %',r;end if;
 if exists(select 1 from public.school_stripe_merchants where stripe_account_id='acct_NotLinkedAnywhere')
 then raise exception 'An association was created';end if;
 if (select count(*) from app_private.stripe_merchant_status_audit where stripe_account_id=v_account)<>2
 then raise exception 'Status changes not audited';end if;
 if has_function_privilege('authenticated',
   'public.apply_signed_stripe_account_status(text,text,bigint,boolean,boolean,boolean)','execute')
  or has_function_privilege('anon',
   'public.apply_signed_stripe_account_status(text,text,bigint,boolean,boolean,boolean)','execute')
 then raise exception 'Clients can call the status RPC';end if;
end;$status_sync$;
