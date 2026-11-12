-- Uno studente ordina solo dal bar della propria scuola (20261106140000).
\set ON_ERROR_STOP on
reset role;
insert into public.schools(id,slug,name) values
 ('5cc00000-0000-4000-8000-00000000000a','cliente-a','Scuola cliente A'),
 ('5cc00000-0000-4000-8000-00000000000b','cliente-b','Scuola cliente B');
insert into public.bars(id,school_id,name) values
 ('5cc00000-0000-4000-8000-0000000000ba','5cc00000-0000-4000-8000-00000000000a','Bar A'),
 ('5cc00000-0000-4000-8000-0000000000bb','5cc00000-0000-4000-8000-00000000000b','Bar B');
insert into public.bar_opening_hours(school_id,bar_id,weekday,starts_at,ends_at)
 select b.school_id,b.id,d,'00:00','23:59' from public.bars b cross join generate_series(0,6) d
 where b.id in ('5cc00000-0000-4000-8000-0000000000ba','5cc00000-0000-4000-8000-0000000000bb');
insert into public.pickup_windows(id,school_id,bar_id,service_date,starts_at,ends_at) values
 ('5cc00000-0000-4000-8000-0000000000fa','5cc00000-0000-4000-8000-00000000000a','5cc00000-0000-4000-8000-0000000000ba',current_date+1,'10:00','10:15'),
 ('5cc00000-0000-4000-8000-0000000000fb','5cc00000-0000-4000-8000-00000000000b','5cc00000-0000-4000-8000-0000000000bb',current_date+1,'10:00','10:15');
insert into auth.users(id,email,email_confirmed_at) values
 ('5cc00000-0000-4000-8000-0000000000c1','studente-uno@example.invalid',now()),
 ('5cc00000-0000-4000-8000-0000000000c2','studente-due@example.invalid',now()),
 ('5cc00000-0000-4000-8000-0000000000c3','barista-b@example.invalid',now());
insert into public.school_memberships(id,school_id,user_id) values
 ('5cc00000-0000-4000-8000-0000000000d3','5cc00000-0000-4000-8000-00000000000b','5cc00000-0000-4000-8000-0000000000c3');
insert into public.role_assignments(membership_id,role_code) values('5cc00000-0000-4000-8000-0000000000d3','bartender');

create function pg_temp.denied(p_sql text) returns boolean language plpgsql as $d$
begin execute p_sql;return false;exception when others then return true;end;$d$;
create function pg_temp.draft(p_user text,p_school text,p_bar text,p_window text) returns text language sql as $q$
 select format($f$insert into public.group_drafts(school_id,bar_id,pickup_window_id,coordinator_id,request_key,title)
  values(%L,%L,%L,%L,gen_random_uuid(),'Merenda di prova')$f$,p_school,p_bar,p_window,p_user);
$q$;

do $t$declare g uuid;begin
 -- Il primo gruppo collega lo studente alla scuola come cliente.
 execute pg_temp.draft('5cc00000-0000-4000-8000-0000000000c1','5cc00000-0000-4000-8000-00000000000a','5cc00000-0000-4000-8000-0000000000ba','5cc00000-0000-4000-8000-0000000000fa');
 if not exists(select 1 from public.school_memberships m join public.role_assignments r on r.membership_id=m.id
  where m.user_id='5cc00000-0000-4000-8000-0000000000c1' and m.school_id='5cc00000-0000-4000-8000-00000000000a' and r.role_code='customer')
 then raise exception 'First group did not bind the student to the school';end if;
 -- Stessa scuola: consentito, nessuna appartenenza in più.
 execute pg_temp.draft('5cc00000-0000-4000-8000-0000000000c1','5cc00000-0000-4000-8000-00000000000a','5cc00000-0000-4000-8000-0000000000ba','5cc00000-0000-4000-8000-0000000000fa');
 -- Un'altra scuola: rifiutato.
 if not pg_temp.denied(pg_temp.draft('5cc00000-0000-4000-8000-0000000000c1','5cc00000-0000-4000-8000-00000000000b','5cc00000-0000-4000-8000-0000000000bb','5cc00000-0000-4000-8000-0000000000fb'))
 then raise exception 'Student created a group in another school';end if;
 -- Il personale ordina solo nella propria scuola.
 if not pg_temp.denied(pg_temp.draft('5cc00000-0000-4000-8000-0000000000c3','5cc00000-0000-4000-8000-00000000000a','5cc00000-0000-4000-8000-0000000000ba','5cc00000-0000-4000-8000-0000000000fa'))
 then raise exception 'Staff created a group in another school';end if;
 -- Entrare nel gruppo di un'altra scuola: rifiutato; il primo ingresso collega.
 select id into g from public.group_drafts where coordinator_id='5cc00000-0000-4000-8000-0000000000c1' limit 1;
 if not pg_temp.denied(format($f$insert into public.group_members(group_id,user_id,status) values(%L,'5cc00000-0000-4000-8000-0000000000c3','accepted')$f$,g))
 then raise exception 'Staff of another school joined the group';end if;
 insert into public.group_members(group_id,user_id,status) values(g,'5cc00000-0000-4000-8000-0000000000c2','accepted');
 if (select school_id from public.school_memberships where user_id='5cc00000-0000-4000-8000-0000000000c2')<>'5cc00000-0000-4000-8000-00000000000a'
 then raise exception 'Joining a group did not bind the student';end if;
 if not pg_temp.denied($$select app_private.bind_customer_school('5cc00000-0000-4000-8000-0000000000c2','5cc00000-0000-4000-8000-00000000000b')$$)
 then raise exception 'Bound student accepted in another school';end if;
 -- Gli ordini individuali passano dallo stesso controllo.
 if not exists(select 1 from pg_trigger where tgname='breakapp_order_own_school' and tgrelid='public.orders'::regclass)
 then raise exception 'Order trigger missing';end if;
end$t$;

-- Il client non può chiamare la funzione di collegamento.
set role authenticated;
do $t$begin
 if not pg_temp.denied($$select app_private.bind_customer_school('5cc00000-0000-4000-8000-0000000000c2','5cc00000-0000-4000-8000-00000000000a')$$)
 then raise exception 'Client called bind_customer_school';end if;
end$t$;
reset role;
