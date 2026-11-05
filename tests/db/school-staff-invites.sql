-- Inviti del personale (migrazione 20261105180000). Fixture indipendenti.
\set ON_ERROR_STOP on
reset role;
insert into public.schools(id,slug,name) values
 ('5ca00000-0000-4000-8000-00000000000a','inviti-a','Scuola inviti A'),
 ('5ca00000-0000-4000-8000-00000000000b','inviti-b','Scuola inviti B');
insert into auth.users(id,email,email_confirmed_at) values
 ('5ca00000-0000-4000-8000-0000000000a1','preside-a@example.invalid',now()),
 ('5ca00000-0000-4000-8000-0000000000e1','gia-registrata@example.invalid',now()),
 ('5ca00000-0000-4000-8000-0000000000e2','ha-ruolo@example.invalid',now());
insert into public.school_memberships(id,school_id,user_id,membership_status) values
 ('5ca00000-0000-4000-8000-0000000000b1','5ca00000-0000-4000-8000-00000000000a','5ca00000-0000-4000-8000-0000000000a1','active'),
 ('5ca00000-0000-4000-8000-0000000000b2','5ca00000-0000-4000-8000-00000000000b','5ca00000-0000-4000-8000-0000000000e2','active');
insert into public.role_assignments(membership_id,role_code) values
 ('5ca00000-0000-4000-8000-0000000000b1','school_admin'),
 ('5ca00000-0000-4000-8000-0000000000b2','customer');

create function pg_temp.denied(p_sql text) returns boolean language plpgsql as $d$
begin execute p_sql;return false;exception when others then return true;end;$d$;
create function pg_temp.as_user(p_user text,p_aal text) returns void language sql as $a$
 select set_config('request.jwt.claim.sub',p_user,false),
  set_config('request.jwt.claims',json_build_object('aal',p_aal,'is_anonymous',false)::text,false);
$a$;

-- Admin scuola senza 2FA: nessun accesso.
set role authenticated;
select pg_temp.as_user('5ca00000-0000-4000-8000-0000000000a1','aal1');
do $t$begin
 if not pg_temp.denied($$select public.list_school_staff('5ca00000-0000-4000-8000-00000000000a')$$)
 then raise exception 'Admin without MFA listed staff';end if;
 if not pg_temp.denied($$select public.invite_school_staff('5ca00000-0000-4000-8000-00000000000a','nuovo@example.invalid','bartender')$$)
 then raise exception 'Admin without MFA invited staff';end if;
end$t$;

-- Admin scuola con 2FA: baristi e magazzinieri della propria scuola soltanto.
select pg_temp.as_user('5ca00000-0000-4000-8000-0000000000a1','aal2');
do $t$declare r jsonb;begin
 if not pg_temp.denied($$select public.invite_school_staff('5ca00000-0000-4000-8000-00000000000a','altro-admin@example.invalid','school_admin')$$)
 then raise exception 'School admin invited another school admin';end if;
 if not pg_temp.denied($$select public.invite_school_staff('5ca00000-0000-4000-8000-00000000000b','x@example.invalid','bartender')$$)
 then raise exception 'School admin invited staff in another school';end if;
 if not pg_temp.denied($$select public.list_school_staff('5ca00000-0000-4000-8000-00000000000b')$$)
 then raise exception 'School admin listed another school';end if;
 if not pg_temp.denied($$select public.invite_school_staff('5ca00000-0000-4000-8000-00000000000a','non-una-email','bartender')$$)
 then raise exception 'Invalid email accepted';end if;
 if not pg_temp.denied($$select public.invite_school_staff('5ca00000-0000-4000-8000-00000000000a','ha-ruolo@example.invalid','bartender')$$)
 then raise exception 'Second role granted to an account with a role';end if;
 if not pg_temp.denied($$select public.invite_school_staff('5ca00000-0000-4000-8000-00000000000a','admin-a@example.invalid','bartender')$$)
 then raise exception 'Super Admin received a school role';end if;

 r:=public.invite_school_staff('5ca00000-0000-4000-8000-00000000000a',' Barista.Nuovo@Example.invalid ','bartender');
 if r->>'status'<>'invited' or r->>'email'<>'barista.nuovo@example.invalid' or r->>'code'!~'^[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$'
 then raise exception 'Unexpected invite result %',r;end if;
 perform set_config('app.code_barista',r->>'code',false);
 if not pg_temp.denied($$select public.invite_school_staff('5ca00000-0000-4000-8000-00000000000a','barista.nuovo@example.invalid','warehouse_manager')$$)
 then raise exception 'Duplicate invite accepted';end if;

 r:=public.invite_school_staff('5ca00000-0000-4000-8000-00000000000a','magazzino@admin.breakapp.it','warehouse_manager');
 perform set_config('app.code_magazzino',r->>'code',false);

 -- Account già confermato e senza ruoli: assegnazione immediata, senza codice.
 r:=public.invite_school_staff('5ca00000-0000-4000-8000-00000000000a','gia-registrata@example.invalid','bartender');
 if r->>'status'<>'assigned' or r ? 'code' then raise exception 'Existing account not assigned directly %',r;end if;

 r:=public.list_school_staff('5ca00000-0000-4000-8000-00000000000a');
 if jsonb_array_length(r->'invites')<>2 then raise exception 'Expected two invites %',r;end if;
 if not exists(select 1 from jsonb_array_elements(r->'members') m where m->>'email'='gia-registrata@example.invalid' and m->>'role'='bartender')
 then raise exception 'Directly assigned member not listed %',r;end if;
 if exists(select 1 from jsonb_array_elements(r->'invites') i where i ? 'code' or i ? 'code_hash')
 then raise exception 'Invite list leaks the code';end if;
end$t$;

-- Il client non legge le tabelle private.
do $t$begin
 if not pg_temp.denied($$select * from app_private.school_staff_invites$$)
 then raise exception 'Invite table readable by clients';end if;
end$t$;

-- Modifica: ruolo consentito, codice rinnovato; non si promuove ad admin.
do $t$declare v uuid;r jsonb;begin
 select (i->>'id')::uuid into v from jsonb_array_elements(public.list_school_staff('5ca00000-0000-4000-8000-00000000000a')->'invites') i
  where i->>'email'='barista.nuovo@example.invalid';
 if not pg_temp.denied(format($$select public.update_school_staff_invite(%L,'barista.nuovo@example.invalid','school_admin')$$,v))
 then raise exception 'School admin promoted an invite to admin';end if;
 r:=public.update_school_staff_invite(v,'barista.nuovo@example.invalid','warehouse_manager',false);
 if r->>'role'<>'warehouse_manager' or r->>'code' is not null then raise exception 'Update failed %',r;end if;
 r:=public.update_school_staff_invite(v,'barista.nuovo@example.invalid','bartender',true);
 if r->>'code' is null or r->>'code'=current_setting('app.code_barista') then raise exception 'Code not renewed';end if;
 perform set_config('app.code_barista',r->>'code',false);
end$t$;

-- Super Admin con 2FA: può invitare un admin scuola in qualunque scuola.
select pg_temp.as_user('44444444-4444-4444-8444-444444444444','aal2');
do $t$declare r jsonb;begin
 r:=public.invite_school_staff('5ca00000-0000-4000-8000-00000000000b','preside-b@example.invalid','school_admin');
 if r->>'status'<>'invited' then raise exception 'Super Admin could not invite an admin';end if;
 r:=public.invite_school_staff('5ca00000-0000-4000-8000-00000000000a','da-rimuovere@example.invalid','bartender');
end$t$;

-- L'admin della scuola A non tocca l'invito admin né la scuola B; rimuove il suo.
select pg_temp.as_user('5ca00000-0000-4000-8000-0000000000a1','aal2');
do $t$declare v uuid;begin
 select id into v from (select (i->>'id')::uuid id from jsonb_array_elements(public.list_school_staff('5ca00000-0000-4000-8000-00000000000a')->'invites') i
  where i->>'email'='da-rimuovere@example.invalid') x;
 perform public.remove_school_staff_invite(v);
 if not pg_temp.denied(format($$select public.remove_school_staff_invite(%L)$$,v))
 then raise exception 'Removed invite twice';end if;
end$t$;
reset role;
do $t$declare v uuid;begin
 select id into v from app_private.school_staff_invites where email='preside-b@example.invalid';
 perform set_config('app.admin_invite',v::text,false);
end$t$;
set role authenticated;
select pg_temp.as_user('5ca00000-0000-4000-8000-0000000000a1','aal2');
do $t$begin
 if not pg_temp.denied(format($$select public.remove_school_staff_invite(%L)$$,current_setting('app.admin_invite')))
 then raise exception 'School admin removed an admin invite of another school';end if;
end$t$;

-- Registrazione con email reale verificata: collegamento automatico alla conferma.
reset role;
insert into auth.users(id,email,email_confirmed_at) values
 ('5ca00000-0000-4000-8000-0000000000c1','barista.nuovo@example.invalid',null),
 ('5ca00000-0000-4000-8000-0000000000c2','magazzino@admin.breakapp.it',now()),
 ('5ca00000-0000-4000-8000-0000000000c3','preside-b@example.invalid',now());
do $t$begin
 if exists(select 1 from public.school_memberships where user_id='5ca00000-0000-4000-8000-0000000000c1')
 then raise exception 'Unconfirmed email claimed an invite';end if;
end$t$;
update auth.users set email_confirmed_at=now() where id='5ca00000-0000-4000-8000-0000000000c1';
do $t$begin
 if not exists(select 1 from public.school_memberships m join public.role_assignments r on r.membership_id=m.id
  where m.user_id='5ca00000-0000-4000-8000-0000000000c1' and m.school_id='5ca00000-0000-4000-8000-00000000000a' and r.role_code='bartender')
 then raise exception 'Confirmed email not linked';end if;
 if exists(select 1 from app_private.school_staff_invites where email='barista.nuovo@example.invalid')
 then raise exception 'Claimed invite still pending';end if;
 if not exists(select 1 from public.school_memberships m join public.role_assignments r on r.membership_id=m.id
  where m.user_id='5ca00000-0000-4000-8000-0000000000c3' and r.role_code='school_admin')
 then raise exception 'Super Admin admin invite not linked';end if;
 -- Indirizzo interno: nessun collegamento senza codice.
 if exists(select 1 from public.school_memberships where user_id='5ca00000-0000-4000-8000-0000000000c2')
 then raise exception 'Internal address claimed without code';end if;
end$t$;

-- Indirizzo interno: codice sbagliato rifiutato e conteggiato, poi codice giusto.
set role authenticated;
select pg_temp.as_user('5ca00000-0000-4000-8000-0000000000c2','aal1');
do $t$declare r jsonb;begin
 r:=public.claim_school_staff_invite('0000-0000-0000');
 if (r->>'ok')::boolean then raise exception 'Wrong code accepted';end if;
 r:=public.claim_school_staff_invite(lower(replace(current_setting('app.code_magazzino'),'-',' ')));
 if not (r->>'ok')::boolean or r->>'role'<>'warehouse_manager' then raise exception 'Right code refused %',r;end if;
end$t$;
-- Un altro account non può usare il codice di qualcun altro.
select pg_temp.as_user('5ca00000-0000-4000-8000-0000000000e2','aal1');
do $t$declare r jsonb;begin
 r:=public.claim_school_staff_invite(current_setting('app.code_magazzino'));
 if (r->>'ok')::boolean then raise exception 'Code claimed by another account';end if;
end$t$;
reset role;
do $t$begin
 if (select n from app_private.school_staff_claim_attempts where user_id='5ca00000-0000-4000-8000-0000000000c2')<>1
 then raise exception 'Failed attempt not counted';end if;
 if (select count(*) from app_private.school_staff_invite_audit where school_id='5ca00000-0000-4000-8000-00000000000a')<6
 then raise exception 'Audit rows missing';end if;
end$t$;

-- Limite tentativi.
update app_private.school_staff_claim_attempts set n=10 where user_id='5ca00000-0000-4000-8000-0000000000e2';
set role authenticated;
select pg_temp.as_user('5ca00000-0000-4000-8000-0000000000e2','aal1');
do $t$begin
 if not pg_temp.denied($$select public.claim_school_staff_invite('AAAA-BBBB-CCCC')$$)
 then raise exception 'Attempt limit not enforced';end if;
end$t$;
reset role;
