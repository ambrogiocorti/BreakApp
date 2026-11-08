-- BreakApp: segnala le scuole dimostrative (decisione 8/11/2026).
-- La scuola DEMO usa soltanto Stripe TEST: l'interfaccia mostra un avviso
-- discreto "Ambiente dimostrativo — pagamenti di prova, nessun addebito reale".
-- Il flag è in sola lettura per i client: nessuna policy UPDATE su schools.
alter table public.schools add column if not exists is_demo boolean not null default false;
grant select(is_demo) on public.schools to anon,authenticated;
update public.schools set is_demo=true where slug='demo-breakapp-test';
