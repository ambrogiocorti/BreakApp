-- Eseguire SOLO dopo 01_breakapp_foundations.sql e dopo aver registrato
-- e confermato l'email del primo Admin sul sito BreakApp.
-- Sostituire i tre valori qui sotto. Eseguire in SQL Editor, mai dal browser.
-- Ripetibile senza duplicare scuola, bar o ruolo.

do $$
declare
  v_admin_email text := 'INSERISCI_EMAIL_ADMIN@esempio.it';
  v_school_slug text := 'scuola-esempio';
  v_school_name text := 'Scuola di esempio';
  v_bar_name text := 'Bar principale';
  v_user_id uuid;
  v_school_id uuid;
  v_membership_id uuid;
begin
  if v_admin_email = 'INSERISCI_EMAIL_ADMIN@esempio.it' then
    raise exception 'Prima sostituisci v_admin_email con la tua email confermata';
  end if;

  select id into v_user_id
    from auth.users
    where lower(email) = lower(v_admin_email)
      and email_confirmed_at is not null;

  if v_user_id is null then
    raise exception 'Admin non trovato o email non ancora confermata: %', v_admin_email;
  end if;

  insert into public.schools (slug, name)
  values (v_school_slug, v_school_name)
  on conflict (slug) do nothing;

  select id into v_school_id
    from public.schools where slug = v_school_slug;

  insert into public.bars (school_id, name)
  values (v_school_id, v_bar_name)
  on conflict (school_id, name) do nothing;

  insert into public.school_memberships (school_id, user_id, membership_status)
  values (v_school_id, v_user_id, 'active')
  on conflict (school_id, user_id) do update
    set membership_status = 'active'
  returning id into v_membership_id;

  insert into public.role_assignments (membership_id, role_code)
  values (v_membership_id, 'school_admin')
  on conflict do nothing;

  raise notice 'Prima scuola e Admin creati: school_id=%, user_id=%',
    v_school_id, v_user_id;
end;
$$;
