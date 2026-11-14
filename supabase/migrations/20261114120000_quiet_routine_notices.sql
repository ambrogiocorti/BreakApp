-- 2026-11-14 Ambrogio: gli avvisi di routine «occupano spazio e basta».
-- Non creiamo più avvisi (né push) per ciò che la persona ha appena fatto o
-- vede già in Ordini: ordine confermato/inviato, cambio di stato
-- (preparing/ready/delivered/cancelled), rimborso richiesto al banco,
-- pagamento con carta annullato al banco, cambio prodotto al banco.
-- Restano: ordine annullato (con motivo), spostato di fascia, non ritirato,
-- modifiche, articoli mancanti, rimborso amministrativo, gruppi, assistenza,
-- avvisi scuola e promemoria. Pagamenti, rimborsi e registri non cambiano:
-- si tocca solo l'inserimento in customer_notifications.
begin;

-- Stato grezzo in inglese: duplicava le altre notifiche e la pagina Ordini.
drop trigger if exists orders_notify_state on public.orders;

-- Conferma dell'ordine singolo: l'ha appena fatto la persona stessa.
-- La conferma di gruppo resta (gli altri membri non l'hanno confermata).
create or replace function app_private.notify_new_booking()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='orders' then return new;end if;
 insert into public.customer_notifications(school_id,user_id,group_id,event_type,message,delivery_event_key)
 select new.school_id,m.user_id,new.group_id,'group_confirmed',
  case when new.status like 'approval_%' then 'Richiesta di gruppo inviata al Barista per approvazione.' else 'Ordine di gruppo confermato. Il ritiro dell’intero gruppo spetta al coordinatore.' end,
  'booking:group:'||new.id||':'||m.user_id from public.group_members m
 where m.group_id=new.group_id and m.status='accepted'
 on conflict(delivery_event_key) do nothing;
 return new;
end;$$;
drop trigger if exists individual_booking_notice on public.orders;

-- Operazioni fatte al banco davanti allo studente: nessun avviso.
create or replace function app_private.notify_order_change(p_kind text,p_id uuid,p_message text)
returns void language plpgsql security definer set search_path='' as $$
declare j jsonb;
begin
 if p_message like 'Rimborso richiesto:%'
  or p_message like 'Pagamento con carta annullato al banco%'
  or p_message like 'Cambio registrato al banco%' then return;end if;
 j:=app_private.order_scope(p_kind,p_id,'internal');
 if p_kind='individual' then insert into public.customer_notifications(school_id,user_id,order_id,event_type,message)
 values((j->>'school_id')::uuid,(j->>'owner_id')::uuid,p_id,'order_status',left(p_message,1000));
 else insert into public.customer_notifications(school_id,user_id,group_id,event_type,message)
 select (j->>'school_id')::uuid,user_id,(j->>'group_id')::uuid,'group_confirmed',left(p_message,1000)
 from public.group_members where group_id=(j->>'group_id')::uuid and status='accepted';end if;
end;$$;
revoke all on function app_private.notify_order_change(text,uuid,text) from public,anon,authenticated,service_role;
revoke all on function app_private.notify_new_booking() from public,anon,authenticated;

commit;
