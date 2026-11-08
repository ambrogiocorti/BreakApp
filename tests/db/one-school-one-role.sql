-- «Una scuola e un ruolo per account» (migrazione 20261106130000).
-- Fixture indipendenti; 4444… è il Super Admin creato da workspace-role.sql.
\set ON_ERROR_STOP on
reset role;
insert into public.schools(id,slug,name) values
 ('5cb00000-0000-4000-8000-00000000000a','regola-a','Scuola regola A'),
 ('5cb00000-0000-4000-8000-00000000000b','regola-b','Scuola regola B');
insert into auth.users(id,email,email_confirmed_at) values
 ('5cb00000-0000-4000-8000-0000000000c1','studente-regola@example.invalid',now()),
 ('5cb00000-0000-4000-8000-0000000000c2','barista-regola@example.invalid',now()),
 ('5cb00000-0000-4000-8000-0000000000c3','libero-regola@example.invalid',now());
insert into public.school_memberships(id,school_id,user_id,membership_status) values
 ('5cb00000-0000-4000-8000-0000000000d1','5cb00000-0000-4000-8000-00000000000a','5cb00000-0000-4000-8000-0000000000c1','active');
insert into public.role_assignments(membership_id,role_code) values
 ('5cb00000-0000-4000-8000-0000000000d1','customer');

create function pg_temp.denied(p_sql text) returns boolean language plpgsql as $d$
begin execute p_sql;return false;exception when others then return true;end;$d$;
create function pg_temp.as_user(p_user text,p_aal text) returns void language sql as $a$
 select set_config('request.jwt.claim.sub',p_user,false),
  set_config('request.jwt.claims',json_build_object('aal',p_aal,'is_anonymous',false)::text,false);
$a$;

-- Vincoli nel database, anche scrivendo direttamente nelle tabelle.
do $t$begin
 if not pg_temp.denied($$insert into public.school_memberships(school_id,user_id) values('5cb00000-0000-4000-8000-00000000000b','5cb00000-0000-4000-8000-0000000000c1')$$)
 then raise exception 'A second school was accepted';end if;
 if not pg_temp.denied($$insert into public.role_assignments(membership_id,role_code) values('5cb00000-0000-4000-8000-0000000000d1','bartender')$$)
 then raise exception 'A second role was accepted';end if;
 if not pg_temp.denied($$update public.school_memberships set school_id='5cb00000-0000-4000-8000-00000000000b' where id='5cb00000-0000-4000-8000-0000000000d1'$$)
 then raise exception 'A membership moved to another school';end if;
 if not pg_temp.denied($$update public.school_memberships set user_id='5cb00000-0000-4000-8000-0000000000c2' where id='5cb00000-0000-4000-8000-0000000000d1'$$)
 then raise exception 'A membership moved to another account';end if;
 -- Cambiare lo stato resta possibile.
 update public.school_memberships set membership_status='suspended' where id='5cb00000-0000-4000-8000-0000000000d1';
 update public.school_memberships set membership_status='active' where id='5cb00000-0000-4000-8000-0000000000d1';
end$t$;

-- La vecchia funzione dell'Admin scuola è ritirata.
set role authenticated;
select pg_temp.as_user('44444444-4444-4444-8444-444444444444','aal2');
do $t$begin
 if not pg_temp.denied($$select public.school_assign_staff('5cb00000-0000-4000-8000-00000000000a','libero-regola@example.invalid','bartender')$$)
 then raise exception 'Retired school_assign_staff still runs';end if;
end$t$;

-- La vecchia assegnazione del Super Admin applica i controlli degli inviti.
do $t$declare r jsonb;begin
 if not pg_temp.denied($$select public.platform_assign_school_staff('5cb00000-0000-4000-8000-00000000000b','studente-regola@example.invalid','bartender')$$)
 then raise exception 'Legacy assignment gave a second school and role';end if;
 if not pg_temp.denied($$select public.platform_assign_school_staff('5cb00000-0000-4000-8000-00000000000a','admin-a@example.invalid','school_admin')$$)
 then raise exception 'Legacy assignment gave a school role to the Super Admin';end if;
 if not pg_temp.denied($$select public.platform_assign_school_staff('5cb00000-0000-4000-8000-00000000000a','libero-regola@example.invalid','customer')$$)
 then raise exception 'Legacy assignment accepted a non-staff role';end if;

 r:=public.platform_assign_school_staff('5cb00000-0000-4000-8000-00000000000a','barista-regola@example.invalid','bartender');
 if r->>'status'<>'assigned' or r->>'school_id'<>'5cb00000-0000-4000-8000-00000000000a' then raise exception 'Confirmed account not assigned: %',r;end if;
 if not pg_temp.denied($$select public.platform_assign_school_staff('5cb00000-0000-4000-8000-00000000000b','barista-regola@example.invalid','warehouse_manager')$$)
 then raise exception 'Staff received a second school';end if;

 r:=public.platform_assign_school_staff('5cb00000-0000-4000-8000-00000000000b','ancora-senza-account@example.invalid','school_admin');
 if r->>'status'<>'invited' or coalesce(r->>'code','')='' then raise exception 'Unknown email not invited: %',r;end if;
end$t$;

-- La revoca libera l'account: senza ruolo l'appartenenza sparisce e la
-- persona può essere collegata a un'altra scuola.
do $t$declare r jsonb;begin
 perform public.platform_revoke_school_staff('5cb00000-0000-4000-8000-00000000000a','5cb00000-0000-4000-8000-0000000000c2','bartender');
 r:=public.platform_assign_school_staff('5cb00000-0000-4000-8000-00000000000b','barista-regola@example.invalid','warehouse_manager');
 if r->>'status'<>'assigned' then raise exception 'Revoked staff could not move school: %',r;end if;
end$t$;

reset role;
do $t$begin
 if (select count(*) from public.school_memberships where user_id='5cb00000-0000-4000-8000-0000000000c2')<>1
  or not exists(select 1 from public.school_memberships m join public.role_assignments r on r.membership_id=m.id
   where m.user_id='5cb00000-0000-4000-8000-0000000000c2' and m.school_id='5cb00000-0000-4000-8000-00000000000b' and r.role_code='warehouse_manager')
 then raise exception 'Moved staff does not have exactly one school and one role';end if;
 if exists(select 1 from public.school_memberships group by user_id having count(*)>1)
  or exists(select 1 from public.role_assignments group by membership_id having count(*)>1)
 then raise exception 'Some account has more than one school or role';end if;
end$t$;
