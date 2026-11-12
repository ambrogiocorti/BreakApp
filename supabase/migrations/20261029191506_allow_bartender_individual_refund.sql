-- Applied to BreakApp test project on 2026-10-29 as allow_bartender_individual_refund.
-- Admin scuola (AAL2) and Barista may refund a finished individual order of their school.
-- Group refund privileges remain unchanged (admin-only).
CREATE OR REPLACE FUNCTION public.request_completed_order_refund(p_kind text, p_order uuid, p_key uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  j jsonb;
  v_paid bigint;
  outcome jsonb;
BEGIN
  j := app_private.order_scope(p_kind, p_order, 'internal');
  IF NOT (
    app_private.can_manage_support_school((j->>'school_id')::uuid)
    OR (p_kind = 'individual' AND app_private.can_serve_group_bar((j->>'school_id')::uuid))
  ) OR p_key IS NULL OR length(btrim(coalesce(p_reason, ''))) NOT BETWEEN 8 AND 300 THEN
    RAISE EXCEPTION 'Solo Admin scuola con 2FA o Barista della scuola possono rimborsare ordini individuali, indicando un motivo valido';
  END IF;
  IF j->>'status' NOT IN ('delivered', 'no_show') THEN
    RAISE EXCEPTION 'Il rimborso amministrativo richiede un ordine concluso';
  END IF;
  PERFORM app_private.assert_no_pending_checkout(p_kind, p_order);
  v_paid := app_private.order_paid_cents(p_kind, p_order);
  PERFORM app_private.refund_order_credit(p_kind, p_order, NULL, v_paid, p_key, p_reason);
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'refund_id', r.id,
    'account', a.stripe_account_id,
    'payment_intent', a.stripe_payment_intent_id,
    'amount_cents', r.amount_cents,
    'status', r.status
  )), '[]'::jsonb)
  INTO outcome
  FROM public.payment_refunds r
  JOIN public.payment_attempts a ON a.id = r.payment_id
  WHERE r.request_key = p_key;
  IF outcome = '[]'::jsonb AND NOT EXISTS (
    SELECT 1 FROM public.cash_refund_obligations WHERE request_key = p_key
  ) THEN
    RAISE EXCEPTION 'Nessun importo residuo da rimborsare';
  END IF;
  PERFORM app_private.notify_order_change(p_kind, p_order,
    'Rimborso richiesto: importi online in elaborazione ai pagatori originali; eventuali contanti devono essere restituiti fisicamente.');
  RETURN jsonb_build_object(
    'online', outcome,
    'cash_pending', coalesce((SELECT sum(amount_cents) FROM public.cash_refund_obligations WHERE request_key = p_key), 0)
  );
END;
$function$;
