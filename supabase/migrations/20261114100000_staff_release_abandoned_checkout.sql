-- BreakApp: il pagamento con carta avviato e non concluso non deve bloccare
-- l'incasso al banco (segnalazione di Ambrogio del 14/11/2026, ordine #19).
-- Il barista puo' annullare il Checkout Stripe ancora aperto: la funzione
-- stripe-checkout-cancel chiede a Stripe di farlo scadere e solo se Stripe
-- risponde "scaduto e non pagato" il tentativo viene chiuso. Cosi' il cliente
-- non puo' piu' pagare online e non c'e' rischio di doppio incasso.

-- Checkout ancora aperto su un ordine individuale (per il personale del bar).
create function public.staff_open_checkout(p_order uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_school uuid;a public.payment_attempts%rowtype;
begin
 select school_id into v_school from public.orders where id=p_order;
 if v_school is null or not app_private.can_serve_group_bar(v_school) then raise exception 'Ordine non disponibile';end if;
 select * into a from public.payment_attempts where order_id=p_order
  and status in ('initiated','requires_action','processing','review') order by created_at desc limit 1;
 if not found then return jsonb_build_object('open',false);end if;
 return jsonb_build_object('open',true,'attempt_id',a.id,'status',a.status,'amount_cents',a.amount_cents,
  'has_session',a.stripe_checkout_session_id is not null,'created_at',a.created_at);
end;$$;
revoke all on function public.staff_open_checkout(uuid) from public,anon,authenticated;
grant execute on function public.staff_open_checkout(uuid) to authenticated;

-- Dati Stripe del Checkout da annullare: solo personale del bar, solo tentativi
-- ancora in attesa del cliente (non in elaborazione o in revisione).
create function public.staff_checkout_to_cancel(p_order uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_school uuid;a public.payment_attempts%rowtype;
begin
 select school_id into v_school from public.orders where id=p_order;
 if v_school is null or not app_private.can_serve_group_bar(v_school) then raise exception 'Ordine non disponibile';end if;
 select * into a from public.payment_attempts where order_id=p_order
  and status in ('initiated','requires_action','processing','review') order by created_at desc limit 1 for update;
 if not found then return jsonb_build_object('open',false);end if;
 if a.status in ('processing','review') then raise exception 'Il pagamento con carta è in elaborazione: aspetta l’esito prima di incassare al banco';end if;
 return jsonb_build_object('open',true,'attempt_id',a.id,'session',a.stripe_checkout_session_id,
  'account',a.stripe_account_id,'created_at',a.created_at);
end;$$;
revoke all on function public.staff_checkout_to_cancel(uuid) from public,anon,authenticated;
grant execute on function public.staff_checkout_to_cancel(uuid) to authenticated;

-- Chiusura del tentativo dopo la conferma di Stripe (solo service role, dalla
-- funzione stripe-checkout-cancel). Senza sessione Stripe registrata si chiude
-- solo oltre la durata massima del Checkout (35 minuti + margine).
create function public.cancel_abandoned_checkout(p_attempt uuid,p_session text)
returns text language plpgsql security definer set search_path='' as $$
declare a public.payment_attempts%rowtype;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Service role richiesto';end if;
 select * into a from public.payment_attempts where id=p_attempt for update;
 if not found then raise exception 'Tentativo di pagamento non trovato';end if;
 if a.status in ('succeeded','review','processing') then return 'not_cancelled';end if;
 if a.status in ('cancelled','failed') then return 'duplicate';end if;
 if p_session is null then
  if a.stripe_checkout_session_id is not null or a.created_at>now()-interval '40 minutes' then
   raise exception 'Pagamento con carta appena avviato: riprova tra qualche minuto';end if;
 elsif a.stripe_checkout_session_id is distinct from p_session then
  raise exception 'Sessione Stripe non corrisponde al pagamento';
 end if;
 update public.payment_attempts set status='cancelled',updated_at=now() where id=p_attempt;
 perform app_private.notify_order_change('individual',a.order_id,'Pagamento con carta annullato al banco: hai pagato direttamente al bar.');
 return 'cancelled';
end;$$;
revoke all on function public.cancel_abandoned_checkout(uuid,text) from public,anon,authenticated;
grant execute on function public.cancel_abandoned_checkout(uuid,text) to service_role;
