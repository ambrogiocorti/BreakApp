-- Ticket personali: RLS, idempotenza, login MFA, messaggi, riaperture e Storage.
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);

select public.open_support_ticket(
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 (select id from public.orders where customer_id=auth.uid() limit 1),
 null,'order','Problema di consegna','Buongiorno, vorrei verificare il mio ordine.',
 '11111111-0000-4000-8000-000000000180'
) as ticket_id \gset
select set_config('app.test_ticket_id',:'ticket_id',false);

-- Same request key: no duplicate.
select public.open_support_ticket(
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 null,null,'other','Altra richiesta','Messaggio ritentato',
 '11111111-0000-4000-8000-000000000180'
) as repeated_ticket \gset
select case when :'ticket_id'=:'repeated_ticket' then 'OK idempotent'
 else (1/0)::text end as test_idempotence;

do $owner_view$
begin
 if (select count(*) from public.support_tickets)<>1 then
   raise exception 'Owner ticket invisible or duplicated';end if;
 if (select count(*) from public.support_messages)<>1 then
   raise exception 'Initial message missing';end if;
end;
$owner_view$;
select public.post_support_message(
 :'ticket_id'::uuid,'Aggiungo ulteriori informazioni utili.') as customer_message \gset

-- Different customer cannot read/modify private ticket.
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
do $other_user$
declare denied boolean:=false;
begin
 if (select count(*) from public.support_tickets)<>0 then
   raise exception 'Ticket of other customer visible';end if;
 if (select count(*) from public.support_messages)<>0 then
   raise exception 'Messages of other customer visible';end if;
 begin
  perform public.post_support_message(current_setting('app.test_ticket_id')::uuid,'Messaggio abusivo');
 exception when others then denied:=true;end;
 if not denied then raise exception 'Other user posted on private ticket';end if;
end;
$other_user$;

-- Admin senza AAL2 non può leggere ticket, né risolverli.
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
do $admin_aal1$
declare denied boolean:=false;
begin
 if (select count(*) from public.support_tickets)<>0 then
  raise exception 'AAL1 admin can read sensitive ticket';end if;
 begin
   perform public.set_support_ticket_status(current_setting('app.test_ticket_id')::uuid,'resolved','');
 exception when others then denied:=true;end;
 if not denied then raise exception 'AAL1 admin resolved ticket';end if;
end;
$admin_aal1$;

-- Admin verified sees ticket and can reply and resolve.
select set_config('request.jwt.claims','{"aal":"aal2","is_anonymous":false}',false);
do $admin_aal2$
begin
 if (select count(*) from public.support_tickets)<>1 then
  raise exception 'Verified admin cannot read school ticket';end if;
end;
$admin_aal2$;
select public.post_support_message(current_setting('app.test_ticket_id')::uuid,'Verifichiamo l’accaduto.');
select public.set_support_ticket_status(current_setting('app.test_ticket_id')::uuid,'resolved','Risposta fornita');

-- Il cliente non può continuare a scrivere sul ticket risolto; richiede riapertura.
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
do $closed_write$
declare denied boolean:=false;
begin
 begin
  perform public.post_support_message(current_setting('app.test_ticket_id')::uuid,'Tentativo su ticket chiuso');
 exception when others then denied:=true;end;
 if not denied then raise exception 'Closed ticket accepts messages';end if;
end;
$closed_write$;
select public.request_support_reopen(:'ticket_id'::uuid,
 'Il problema non è stato risolto, chiedo una revisione.') as reopen_id \gset
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
select set_config('request.jwt.claims','{"aal":"aal2","is_anonymous":false}',false);
select public.review_support_reopen(:'reopen_id'::uuid,true,'Accettata');
do $reopened$
begin
 if (select status from public.support_tickets where id=current_setting('app.test_ticket_id')::uuid)<>'open'
 then raise exception 'Approved reopening did not reopen ticket';end if;
end;
$reopened$;

-- Oggetto privato: Admin AAL2 autorizzato può leggerlo/caricarlo per ticket della propria scuola.
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select set_config('request.jwt.claims','{"aal":"aal1","is_anonymous":false}',false);
insert into storage.objects(bucket_id,name)
values('breakapp-ticket-images',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/'||:'ticket_id'||'/aaaaaaaa-0000-4000-8000-000000000190.jpg');
insert into public.support_attachments(school_id,ticket_id,message_id,uploader_id,object_path,mime_type,size_bytes)
values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',:'ticket_id'::uuid,
 :'customer_message'::uuid,auth.uid(),
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/'||:'ticket_id'||'/aaaaaaaa-0000-4000-8000-000000000190.jpg',
 'image/jpeg',1234);

select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
do $private_storage$
declare denied boolean:=false;
begin
 if (select count(*) from public.support_attachments)<>0 then
  raise exception 'Other customer sees attachments';end if;
 if (select count(*) from storage.objects where bucket_id='breakapp-ticket-images')<>0 then
  raise exception 'Other customer sees private Storage objects';end if;
 begin
  insert into storage.objects(bucket_id,name)
  values('breakapp-ticket-images',
   'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/'||current_setting('app.test_ticket_id')||'/aaaaaaaa-0000-4000-8000-000000000191.jpg');
 exception when others then denied:=true;end;
 if not denied then raise exception 'Other customer can upload into ticket';end if;
end;
$private_storage$;
reset role;
do $bucket_private$
begin
 if (select public from storage.buckets where id='breakapp-ticket-images') is distinct from false
 then raise exception 'Support bucket must be private';end if;
end;
$bucket_private$;
