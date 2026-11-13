-- BreakApp: lo scontrino si conferma nello stesso passaggio dell'incasso o della
-- consegna (richiesta di Ambrogio del 13/11/2026), senza aprire la pagina
-- "Scontrini da emettere". Il barista vede l'importo da battere sul registratore,
-- conferma, e le righe dell'ordine vengono segnate come emesse.

-- Scontrini ancora da emettere per un ordine individuale.
create function public.pending_order_receipts(p_order uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_school uuid;
begin
 select school_id into v_school from public.orders where id=p_order;
 if v_school is null or not app_private.can_handle_fiscal(v_school) then raise exception 'Ordine non disponibile';end if;
 return (select jsonb_build_object(
   'count',count(*),
   'sale_cents',coalesce(sum(amount_cents) filter (where doc_type='sale'),0),
   'return_cents',coalesce(sum(amount_cents) filter (where doc_type='return'),0))
  from public.fiscal_documents where order_id=p_order and status='to_issue');
end;$$;
revoke all on function public.pending_order_receipts(uuid) from public,anon,authenticated;
grant execute on function public.pending_order_receipts(uuid) to authenticated;

-- Segna come emessi (con il registratore del bar) gli scontrini dell'ordine.
create function public.mark_order_receipts_issued(p_order uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare v_school uuid;v_count integer;
begin
 select school_id into v_school from public.orders where id=p_order;
 if v_school is null or not app_private.can_handle_fiscal(v_school) then raise exception 'Ordine non disponibile';end if;
 update public.fiscal_documents set status='issued',issued_by=auth.uid(),issued_at=now(),issue_channel='bar_register'
  where order_id=p_order and status='to_issue';
 get diagnostics v_count=row_count;
 return v_count;
end;$$;
revoke all on function public.mark_order_receipts_issued(uuid) from public,anon,authenticated;
grant execute on function public.mark_order_receipts_issued(uuid) to authenticated;
