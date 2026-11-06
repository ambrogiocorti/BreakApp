-- BreakApp 22: SECURITY DEFINER trigger must not be user-callable.
-- Script 17 created it without REVOKE, and script 20 replaced it while
-- preserving the original default EXECUTE privilege for PUBLIC.
-- Existing triggers still execute under their configured function ownership.
begin;
revoke all on function app_private.prevent_cash_stripe_overlap()
 from public,anon,authenticated;
commit;
