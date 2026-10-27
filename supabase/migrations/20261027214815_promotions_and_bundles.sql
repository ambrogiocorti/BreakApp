begin;
create table public.school_promotions(
 id uuid primary key default gen_random_uuid(),school_id uuid not null references public.schools(id),bar_id uuid not null references public.bars(id),
 code text not null check(code~'^[A-Z0-9_-]{3,32}$'),title text not null check(length(title) between 3 and 120),
 kind text not null check(kind in ('percent','unit_discount','bundle')),value integer not null check(value>0),
 starts_at timestamptz not null,ends_at timestamptz not null,active boolean not null default true,
 max_uses integer check(max_uses>0),per_user_limit integer not null default 1 check(per_user_limit between 1 and 1000),
 recipe jsonb not null default '[]'::jsonb,created_by uuid not null references auth.users(id),
 unique(bar_id,code),check(ends_at>starts_at),check(kind<>'percent' or value<=100),
 check(jsonb_typeof(recipe)='array')
);
create index promotions_school on public.school_promotions(school_id);
create index promotions_actor on public.school_promotions(created_by);
create table public.promotion_redemptions(
 id uuid primary key default gen_random_uuid(),promotion_id uuid not null references public.school_promotions(id),
 user_id uuid not null references auth.users(id),order_id uuid references public.orders(id),group_id uuid references public.group_drafts(id),
 request_key uuid not null,created_at timestamptz not null default now(),unique(user_id,request_key),check(num_nonnulls(order_id,group_id)=1)
);
create index promotion_usage on public.promotion_redemptions(promotion_id,user_id);
create index promotion_order on public.promotion_redemptions(order_id);
create index promotion_group on public.promotion_redemptions(group_id);
alter table public.group_drafts add column promotion_id uuid references public.school_promotions(id);
create index group_promotion on public.group_drafts(promotion_id);
alter table public.school_promotions enable row level security;
alter table public.promotion_redemptions enable row level security;
revoke all on public.school_promotions,public.promotion_redemptions from public,anon,authenticated;
create function app_private.promotion_allowed(p_id uuid,p_actor uuid,p_cart jsonb)
returns boolean language plpgsql set search_path='' as $$
declare p public.school_promotions%rowtype;x record;n integer;v_mult integer;
begin
 select * into p from public.school_promotions where id=p_id for update;
 if not found or not p.active or now()<p.starts_at or now()>=p.ends_at then return false;end if;
 if p.kind='bundle' then
  for x in select * from jsonb_to_recordset(p.recipe) r(product_id uuid,quantity integer,discount_cents integer) loop
   select coalesce(sum(quantity),0) into n from jsonb_to_recordset(p_cart) r(product_id uuid,quantity integer) where product_id=x.product_id;
   if x.quantity<=0 or n<x.quantity or n%x.quantity<>0 then raise exception 'Il bundle richiede multipli interi della composizione indicata';end if;
   if v_mult is not null and v_mult<>n/x.quantity then raise exception 'Rispetta le proporzioni dei prodotti del bundle';end if;v_mult:=n/x.quantity;
  end loop;
 end if;
 return true;
end;$$;
revoke all on function app_private.promotion_allowed(uuid,uuid,jsonb) from public,anon,authenticated,service_role;
create function app_private.promotion_price(p_promo uuid,p_product uuid,p_price integer)
returns integer language sql stable set search_path='' as $$
 select coalesce((select greatest(0,case when p.kind='percent' then p_price-(p_price::bigint*p.value/100)::int
 when p.kind='unit_discount' then p_price-p.value
 else p_price-coalesce((select (x->>'discount_cents')::int from jsonb_array_elements(p.recipe) x where (x->>'product_id')::uuid=p_product),0) end)
 from public.school_promotions p where p.id=p_promo and p.active and now()>=p.starts_at and now()<p.ends_at),p_price);
$$;
revoke all on function app_private.promotion_price(uuid,uuid,integer) from public,anon,authenticated,service_role;
create function app_private.assert_promotion_quota(p_promo uuid,p_user uuid)
returns void language plpgsql set search_path='' as $$
declare p public.school_promotions%rowtype;n integer;u integer;
begin
 select * into p from public.school_promotions where id=p_promo for update;
 select count(*),count(*) filter(where r.user_id=p_user) into n,u from public.promotion_redemptions r
 left join public.orders o on o.id=r.order_id left join public.group_drafts g on g.id=r.group_id
 where r.promotion_id=p.id and coalesce(o.status,g.status) not in ('cancelled','expired');
 if (p.max_uses is not null and n>=p.max_uses) or u>=p.per_user_limit then raise exception 'Limite di utilizzo del coupon raggiunto';end if;
end;$$;
revoke all on function app_private.assert_promotion_quota(uuid,uuid) from public,anon,authenticated,service_role;
create function public.save_school_promotion(p_id uuid,p_bar uuid,p_code text,p_title text,p_kind text,p_value integer,p_start timestamptz,p_end timestamptz,p_max integer,p_per_user integer,p_recipe jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_school uuid;v_id uuid;begin
 select school_id into v_school from public.bars where id=p_bar;
 if not app_private.can_review_school_offline(v_school) then raise exception 'Admin con 2FA richiesto';end if;
 if p_kind='bundle' and (jsonb_array_length(p_recipe)=0 or exists(select 1 from jsonb_to_recordset(p_recipe) x(product_id uuid,quantity integer,discount_cents integer)
  where quantity is null or quantity<=0 or discount_cents is null or discount_cents<0 or not exists(select 1 from public.products where id=x.product_id and bar_id=p_bar)))
 then raise exception 'Composizione bundle non valida';end if;
 if p_id is null then insert into public.school_promotions(school_id,bar_id,code,title,kind,value,starts_at,ends_at,max_uses,per_user_limit,recipe,created_by)
 values(v_school,p_bar,upper(btrim(p_code)),p_title,p_kind,p_value,p_start,p_end,p_max,p_per_user,p_recipe,auth.uid()) returning id into v_id;
 else update public.school_promotions set title=p_title,active=false where id=p_id and bar_id=p_bar returning id into v_id;
  if not found then raise exception 'Promozione non disponibile';end if;end if;return v_id;
end;$$;
create function public.list_school_promotions(p_bar uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare j jsonb;begin
 if auth.uid() is null then raise exception 'Accesso richiesto';end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into j from(select id,code,title,kind,value,recipe,ends_at from public.school_promotions
 where bar_id=p_bar and active and starts_at<=now() and ends_at>now()) x;return j;
end;$$;
create function public.submit_promoted_order(p_bar uuid,p_window uuid,p_items jsonb,p_key uuid,p_latitude double precision,p_longitude double precision,p_accuracy double precision,p_observed timestamptz,p_code text default '')
returns uuid language plpgsql security definer set search_path='' as $$
declare p public.school_promotions%rowtype;v_order uuid;x record;v_total bigint;j jsonb;sc public.schools%rowtype;o public.orders%rowtype;w public.pickup_windows%rowtype;
begin
 if btrim(p_code)='' then return public.submit_individual_order(p_bar,p_window,p_items,p_key,p_latitude,p_longitude,p_accuracy,p_observed);end if;
 select id into v_order from public.orders where customer_id=auth.uid() and request_key=p_key;if found then return v_order;end if;
 select * into p from public.school_promotions where bar_id=p_bar and code=upper(btrim(p_code)) for update;
 if p.id is null or not app_private.promotion_allowed(p.id,auth.uid(),p_items) then raise exception 'Coupon non attivo';end if;
 perform app_private.assert_promotion_quota(p.id,auth.uid());
 v_order:=public.submit_individual_order(p_bar,p_window,p_items,p_key,p_latitude,p_longitude,p_accuracy,p_observed);
 -- Discount the immutable server quote, never a client-provided price.
 update public.order_items set unit_cents=app_private.promotion_price(p.id,product_id,unit_cents) where order_id=v_order and removed_at is null;
 select sum(subtotal_cents) into v_total from public.order_items where order_id=v_order and removed_at is null;
 update public.orders set total_cents=v_total where id=v_order;perform app_private.refresh_individual_balance(v_order);
 select * into o from public.orders where id=v_order;
 select * into sc from public.schools where id=o.school_id;
 if o.status in ('approval_queued','approval_active') and
  (sc.approval_amount_threshold_cents is null or v_total<=sc.approval_amount_threshold_cents) and
  (sc.approval_product_threshold is null or (select sum(quantity) from public.order_items where order_id=v_order and removed_at is null)<=sc.approval_product_threshold) then
  select * into w from public.pickup_windows where id=o.pickup_window_id;
  if not o.stock_reserved then
   for x in select product_id,quantity from public.order_items where order_id=v_order and removed_at is null order by product_id loop
    update public.daily_stock set allocated=allocated+x.quantity,updated_at=now() where bar_id=o.bar_id and product_id=x.product_id and service_date=w.service_date;
    if not found then raise exception 'Scorte non configurate';end if;
   end loop;
  end if;
  update public.order_approvals set state='cancelled',lease_until=null,reason='Totale scontato entro le soglie: approvazione non necessaria' where order_id=v_order;
  update public.orders set status=case when (select preparation_mode from public.bars where id=o.bar_id)='ready_made' then 'ready' else 'confirmed' end,stock_reserved=true where id=v_order;
 end if;
 insert into public.promotion_redemptions(promotion_id,user_id,order_id,request_key) values(p.id,auth.uid(),v_order,p_key);
 return v_order;
end;$$;
create function public.apply_group_promotion(p_group uuid,p_code text,p_key uuid)
returns void language plpgsql security definer set search_path='' as $$
declare g public.group_drafts%rowtype;p public.school_promotions%rowtype;j jsonb;
begin
 select * into g from public.group_drafts where id=p_group for update;
 if not found or g.coordinator_id<>auth.uid() or g.status<>'draft' then raise exception 'Solo coordinatore di una bozza';end if;
 if exists(select 1 from public.group_line_payment_claims cl join public.group_cart_items i on i.id=cl.group_cart_item_id where i.group_id=g.id)
 then raise exception 'Applica il coupon prima dei pagamenti';end if;
 select * into p from public.school_promotions where bar_id=g.bar_id and code=upper(btrim(p_code)) for update;
 select jsonb_agg(jsonb_build_object('product_id',product_id,'quantity',quantity)) into j from public.group_cart_items where group_id=g.id and removed_at is null;
 if p.id is null or not app_private.promotion_allowed(p.id,auth.uid(),coalesce(j,'[]'::jsonb)) then raise exception 'Coupon non valido';end if;
 if not exists(select 1 from public.promotion_redemptions where group_id=g.id and promotion_id=p.id) then
  perform app_private.assert_promotion_quota(p.id,auth.uid());
  insert into public.promotion_redemptions(promotion_id,user_id,group_id,request_key) values(p.id,auth.uid(),g.id,p_key);end if;
 update public.group_drafts set promotion_id=p.id,updated_at=now() where id=g.id;
 update public.group_cart_items i set unit_price_cents=app_private.promotion_price(p.id,i.product_id,pr.price_cents)
 from public.products pr where pr.id=i.product_id and i.group_id=g.id and i.removed_at is null;
end;$$;
create function app_private.group_product_price(p_group uuid,p_product uuid,p_price integer)
returns integer language sql stable set search_path='' as $$
 select app_private.promotion_price((select promotion_id from public.group_drafts where id=p_group),p_product,p_price);
$$;
revoke all on function app_private.group_product_price(uuid,uuid,integer) from public,anon,authenticated,service_role;
create function app_private.group_promotion_quote()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_promo uuid;v_price integer;begin
 select promotion_id into v_promo from public.group_drafts where id=new.group_id;
 if v_promo is not null and not exists(select 1 from public.group_line_payment_claims where group_cart_item_id=new.id) then
  select price_cents into v_price from public.products where id=new.product_id;
  new.unit_price_cents:=app_private.promotion_price(v_promo,new.product_id,v_price);end if;return new;
end;$$;
revoke all on function app_private.group_promotion_quote() from public,anon,authenticated;
create trigger group_coupon_price before insert or update of unit_price_cents on public.group_cart_items for each row execute function app_private.group_promotion_quote();
do $$declare d text;begin
 d:=pg_get_functiondef('public.confirm_group_order(uuid,uuid,boolean,double precision,double precision,double precision,timestamptz)'::regprocedure);
 d:=replace(d,'else p.price_cents end','else app_private.group_product_price(p_group_id,p.id,p.price_cents) end');execute d;
 d:=pg_get_functiondef('public.begin_group_stripe_checkout(uuid,uuid[],uuid)'::regprocedure);
 d:=replace(d,'i.unit_price_cents<>p.price_cents','i.unit_price_cents<>app_private.group_product_price(p_group_id,p.id,p.price_cents)');execute d;
end;$$;
revoke all on function public.save_school_promotion(uuid,uuid,text,text,text,integer,timestamptz,timestamptz,integer,integer,jsonb),public.list_school_promotions(uuid),
 public.submit_promoted_order(uuid,uuid,jsonb,uuid,double precision,double precision,double precision,timestamptz,text),public.apply_group_promotion(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.save_school_promotion(uuid,uuid,text,text,text,integer,timestamptz,timestamptz,integer,integer,jsonb),public.list_school_promotions(uuid),
 public.submit_promoted_order(uuid,uuid,jsonb,uuid,double precision,double precision,double precision,timestamptz,text),public.apply_group_promotion(uuid,text,uuid) to authenticated;
-- Revalidate bundle eligibility at payment/confirmation, after any member edits.
create function app_private.assert_group_promotion(p_group uuid)
returns void language plpgsql set search_path='' as $$
declare g public.group_drafts%rowtype;j jsonb;begin
 select * into g from public.group_drafts where id=p_group;
 if g.promotion_id is null then return;end if;
 select jsonb_agg(jsonb_build_object('product_id',product_id,'quantity',quantity)) into j from public.group_cart_items where group_id=p_group and removed_at is null;
 if not app_private.promotion_allowed(g.promotion_id,g.coordinator_id,coalesce(j,'[]'::jsonb))
 then raise exception 'Promozione scaduta o composizione bundle non valida: verifica il gruppo prima di pagare';end if;
end;$$;
revoke all on function app_private.assert_group_promotion(uuid) from public,anon,authenticated,service_role;
do $$declare d text;begin
 d:=pg_get_functiondef('public.confirm_group_order(uuid,uuid,boolean,double precision,double precision,double precision,timestamptz)'::regprocedure);
 d:=replace(d,' select * into v_group from public.group_drafts',E' perform app_private.assert_group_promotion(p_group_id);\n select * into v_group from public.group_drafts');execute d;
 d:=pg_get_functiondef('public.begin_group_stripe_checkout(uuid,uuid[],uuid)'::regprocedure);
 d:=replace(d,' select * into g from public.group_drafts',E' perform app_private.assert_group_promotion(p_group_id);\n select * into g from public.group_drafts');execute d;
end;$$;
commit;
