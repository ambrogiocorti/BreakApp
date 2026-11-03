-- Add the orders table to the RLS-enforced Supabase Postgres Changes publication.
-- Customers can read their own orders; staff can read school orders with valid role
-- and Admin AAL2, as enforced by public.orders SELECT policies.
-- No new SELECT/UPDATE/INSERT grants are created.
ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
