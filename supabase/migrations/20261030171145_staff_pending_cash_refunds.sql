-- Solo Barista o Admin della scuola (con AAL2) possono leggere gli obblighi pendenti.
-- Separato dalla lista storica: 200 rimborsi conclusi non devono nascondere i pendenti.
CREATE OR REPLACE FUNCTION public.list_staff_pending_cash_refunds(p_school uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE v_items jsonb; v_total bigint;
BEGIN
 IF auth.uid() IS NULL OR p_school IS NULL OR NOT app_private.can_serve_group_bar(p_school) THEN
   RAISE EXCEPTION 'Personale della scuola richiesto';
 END IF;
 SELECT count(*) INTO v_total FROM public.cash_refund_obligations r
 WHERE r.school_id=p_school AND r.status='pending';
 SELECT COALESCE(jsonb_agg(jsonb_build_object(
   'id',r.id, 'school_id',r.school_id, 'order_id',r.order_id,
   'group_order_id',r.group_order_id,'amount_cents',r.amount_cents,
   'reason',r.reason,'status',r.status)), '[]'::jsonb)
 INTO v_items
 FROM (SELECT id,school_id,order_id,group_order_id,amount_cents,reason,status
   FROM public.cash_refund_obligations
   WHERE school_id=p_school AND status='pending'
   ORDER BY id LIMIT 200) r;
 RETURN jsonb_build_object('items',v_items,'total',v_total,'has_more',v_total>200);
END;
$$;
REVOKE ALL ON FUNCTION public.list_staff_pending_cash_refunds(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_staff_pending_cash_refunds(uuid) TO authenticated;
