-- BreakApp: registro degli scontrini da emettere (decisione di Ambrogio del 12/11/2026).
--
-- Il bar non ha un registratore di marca nota e l'app deve funzionare con
-- tutti. Per ora non si collega nessun servizio esterno a pagamento: ogni
-- incasso o rimborso registrato dall'app crea una riga in
-- public.fiscal_documents ('sale' o 'return') con importo, metodo e prodotti.
-- Il bar (Admin o barista) segna la riga come emessa con il proprio
-- registratore; quando sara' scelto un servizio di scontrino online (A-Cube,
-- Openapi o altro) le righe 'to_issue' saranno inviate da li'.
-- Nessuna regola economica esistente cambia: i trigger leggono soltanto.

create table public.fiscal_documents(
 id uuid primary key default gen_random_uuid(),
 school_id uuid not null references public.schools(id),
 bar_id uuid not null references public.bars(id),
 order_id uuid references public.orders(id),
 group_id uuid references public.group_drafts(id),
 doc_type text not null check (doc_type in ('sale','return')),
 payment_method text not null check (payment_method in ('card','cash','external_pos')),
 amount_cents bigint not null check (amount_cents>0),
 order_total_cents bigint not null check (order_total_cents>=0),
 lines jsonb not null default '[]'::jsonb check (jsonb_typeof(lines)='array'),
 source_key text not null unique check (length(source_key) between 3 and 120),
 status text not null default 'to_issue' check (status in ('to_issue','issued')),
 issued_by uuid references auth.users(id),
 issued_at timestamptz,
 issue_channel text check (issue_channel in ('bar_register','online_service')),
 provider_ref text check (length(provider_ref)<=200),
 created_at timestamptz not null default now(),
 check (num_nonnulls(order_id,group_id)=1),
 check ((status='to_issue' and issued_at is null and issue_channel is null)
  or (status='issued' and issued_at is not null and issue_channel is not null))
);
create index fiscal_documents_school on public.fiscal_documents(school_id,status,created_at);
create index fiscal_documents_bar on public.fiscal_documents(bar_id);
create index fiscal_documents_order on public.fiscal_documents(order_id);
create index fiscal_documents_group on public.fiscal_documents(group_id);
create index fiscal_documents_issued_by on public.fiscal_documents(issued_by);
alter table public.fiscal_documents enable row level security;
revoke all on public.fiscal_documents from public,anon,authenticated;

-- Crea la riga se non esiste gia' (stessa sorgente = stessa riga).
create function app_private.record_fiscal_document(p_kind text,p_id uuid,p_doc text,p_method text,p_amount bigint,p_source text)
returns void language plpgsql security definer set search_path='' as $$
declare v_school uuid;v_bar uuid;v_group uuid;v_total bigint;v_lines jsonb;
begin
 if coalesce(p_amount,0)<=0 then return;end if;
 if p_kind='individual' then
  select o.school_id,o.bar_id,o.total_cents into v_school,v_bar,v_total from public.orders o where o.id=p_id;
  select coalesce(jsonb_agg(jsonb_build_object('name',i.product_name,'quantity',i.quantity,'unit_cents',i.unit_cents) order by i.product_name),'[]'::jsonb)
  into v_lines from public.order_items i where i.order_id=p_id and i.removed_at is null and i.quantity>0;
 else
  v_group:=p_id;
  select g.school_id,g.bar_id,coalesce(o.total_cents,0),o.id into v_school,v_bar,v_total,p_id
  from public.group_drafts g left join public.group_orders o on o.group_id=g.id where g.id=v_group;
  select coalesce(jsonb_agg(jsonb_build_object('name',l.name,'quantity',l.quantity,'unit_cents',l.unit_cents) order by l.name),'[]'::jsonb)
  into v_lines from public.group_order_lines l where l.group_order_id=p_id and l.quantity>0;
 end if;
 if v_school is null then return;end if;
 insert into public.fiscal_documents(school_id,bar_id,order_id,group_id,doc_type,payment_method,amount_cents,order_total_cents,lines,source_key)
 values(v_school,v_bar,case when p_kind='individual' then p_id end,v_group,p_doc,p_method,p_amount,coalesce(v_total,0),v_lines,p_source)
 on conflict (source_key) do nothing;
end;$$;
revoke all on function app_private.record_fiscal_document(text,uuid,text,text,bigint,text) from public,anon,authenticated;

create function app_private.group_of_order(p_group_order uuid)
returns uuid language sql stable security definer set search_path='' as $$
 select group_id from public.group_orders where id=p_group_order $$;
revoke all on function app_private.group_of_order(uuid) from public,anon,authenticated;

-- Pagamento online riuscito.
create function app_private.fiscal_from_payment_attempt() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.status='succeeded' and (tg_op='INSERT' or old.status is distinct from 'succeeded') then
  perform app_private.record_fiscal_document(case when new.order_id is not null then 'individual' else 'group' end,
   coalesce(new.order_id,new.group_id),'sale','card',new.amount_cents,'payment:'||new.id);
 end if;return null;
end;$$;
revoke all on function app_private.fiscal_from_payment_attempt() from public,anon,authenticated;
create trigger fiscal_documents_payment after insert or update of status on public.payment_attempts
 for each row execute function app_private.fiscal_from_payment_attempt();

-- Rimborso online confermato da Stripe.
create function app_private.fiscal_from_payment_refund() returns trigger
language plpgsql security definer set search_path='' as $$
declare a public.payment_attempts%rowtype;
begin
 if new.status='succeeded' and (tg_op='INSERT' or old.status is distinct from 'succeeded') then
  select * into a from public.payment_attempts where id=new.payment_id;
  if found then perform app_private.record_fiscal_document(case when a.order_id is not null then 'individual' else 'group' end,
   coalesce(a.order_id,a.group_id),'return','card',new.amount_cents,'refund:'||new.id);end if;
 end if;return null;
end;$$;
revoke all on function app_private.fiscal_from_payment_refund() from public,anon,authenticated;
create trigger fiscal_documents_refund after insert or update of status on public.payment_refunds
 for each row execute function app_private.fiscal_from_payment_refund();

-- Incassi al banco (contanti o POS del bar), anche offline e di gruppo.
create function app_private.fiscal_from_counter_receipt() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_group_order uuid;
begin
 if tg_table_name='group_counter_payments' then v_group_order:=new.group_order_id;
 elsif tg_table_name='order_additional_receipts' then v_group_order:=new.group_order_id;
 end if;
 if v_group_order is not null then
  perform app_private.record_fiscal_document('group',app_private.group_of_order(v_group_order),'sale',new.method,new.amount_cents,tg_table_name||':'||new.id);
 else
  perform app_private.record_fiscal_document('individual',new.order_id,'sale',new.method,new.amount_cents,tg_table_name||':'||new.id);
 end if;return null;
end;$$;
revoke all on function app_private.fiscal_from_counter_receipt() from public,anon,authenticated;
create trigger fiscal_documents_counter after insert on public.counter_payments
 for each row execute function app_private.fiscal_from_counter_receipt();
create trigger fiscal_documents_group_counter after insert on public.group_counter_payments
 for each row execute function app_private.fiscal_from_counter_receipt();
create trigger fiscal_documents_receipt after insert on public.order_additional_receipts
 for each row execute function app_private.fiscal_from_counter_receipt();

-- Contanti restituiti al cliente.
create function app_private.fiscal_from_cash_refund() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.status='returned' and (tg_op='INSERT' or old.status is distinct from 'returned') then
  if new.group_order_id is not null then
   perform app_private.record_fiscal_document('group',app_private.group_of_order(new.group_order_id),'return','cash',new.amount_cents,'cash_refund:'||new.id);
  else
   perform app_private.record_fiscal_document('individual',new.order_id,'return','cash',new.amount_cents,'cash_refund:'||new.id);
  end if;
 end if;return null;
end;$$;
revoke all on function app_private.fiscal_from_cash_refund() from public,anon,authenticated;
create trigger fiscal_documents_cash_refund after insert or update of status on public.cash_refund_obligations
 for each row execute function app_private.fiscal_from_cash_refund();

-- Chi puo' vedere e segnare gli scontrini: Admin della scuola con 2FA o barista.
create function app_private.can_handle_fiscal(p_school uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (app_private.has_barista_role(p_school,auth.uid()) or (
  coalesce(auth.jwt()->>'aal','')='aal2' and exists(select 1 from public.school_memberships m
  join public.role_assignments r on r.membership_id=m.id
  where m.school_id=p_school and m.user_id=auth.uid() and m.membership_status='active' and r.role_code='school_admin'))) $$;
revoke all on function app_private.can_handle_fiscal(uuid) from public,anon,authenticated;

create function public.list_fiscal_documents(p_school uuid,p_from date,p_to date,p_status text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_tz text;
begin
 if not app_private.can_handle_fiscal(p_school) then raise exception 'Non puoi vedere gli scontrini di questa scuola';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>92 then raise exception 'Periodo non valido: massimo 3 mesi';end if;
 if p_status is not null and p_status not in ('to_issue','issued') then raise exception 'Stato non valido';end if;
 select coalesce(timezone,'Europe/Rome') into v_tz from public.schools where id=p_school;
 return coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'created_at',d.created_at,'doc_type',d.doc_type,
  'payment_method',d.payment_method,'amount_cents',d.amount_cents,'order_total_cents',d.order_total_cents,'lines',d.lines,
  'status',d.status,'issued_at',d.issued_at,'issue_channel',d.issue_channel,
  'reference',case when d.order_id is not null then '#'||(select display_no from public.orders where id=d.order_id)
   else 'G-'||left(coalesce((select id::text from public.group_orders where group_id=d.group_id),d.group_id::text),8) end)
  order by d.created_at desc)
  from public.fiscal_documents d where d.school_id=p_school
   and d.created_at>=(p_from::timestamp at time zone v_tz) and d.created_at<((p_to+1)::timestamp at time zone v_tz)
   and (p_status is null or d.status=p_status) limit 2000),'[]'::jsonb);
end;$$;
revoke all on function public.list_fiscal_documents(uuid,date,date,text) from public,anon,authenticated;
grant execute on function public.list_fiscal_documents(uuid,date,date,text) to authenticated;

-- Il bar segna lo scontrino come emesso con il proprio registratore (o lo riapre).
create function public.mark_fiscal_document(p_id uuid,p_issued boolean)
returns void language plpgsql security definer set search_path='' as $$
declare d public.fiscal_documents%rowtype;
begin
 select * into d from public.fiscal_documents where id=p_id for update;
 if not found or not app_private.can_handle_fiscal(d.school_id) then raise exception 'Scontrino non disponibile';end if;
 if d.issue_channel='online_service' then raise exception 'Scontrino gia'' inviato dal servizio online';end if;
 if p_issued then
  update public.fiscal_documents set status='issued',issued_by=auth.uid(),issued_at=now(),issue_channel='bar_register' where id=p_id and status='to_issue';
 else
  update public.fiscal_documents set status='to_issue',issued_by=null,issued_at=null,issue_channel=null where id=p_id and status='issued';
 end if;
end;$$;
revoke all on function public.mark_fiscal_document(uuid,boolean) from public,anon,authenticated;
grant execute on function public.mark_fiscal_document(uuid,boolean) to authenticated;
