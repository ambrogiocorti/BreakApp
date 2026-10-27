import {readClassNames} from './class-import.js';
const node=(tag,text='',cls='')=>{const e=document.createElement(tag);e.textContent=text;e.className=cls;return e;};
function input(form,label,type='text',value=''){
 const wrapper=node('label',label),field=node('input');field.type=type;field.value=value;field.required=true;wrapper.append(field);form.append(wrapper);return field;
}
function select(form,label,rows){const wrapper=node('label',label),s=node('select');s.setAttribute('aria-label',label);for(const[id,text]of rows)s.add(new Option(text,id));wrapper.append(s);form.append(wrapper);return s;}
function formCard(parent,title){const box=node('article','','order-card'),f=node('form');box.append(node('h3',title),f);parent.append(box);return f;}
function submit(f,label,action,act){const b=node('button',label,'button button-primary button-small');b.type='submit';f.append(b);f.addEventListener('submit',e=>{e.preventDefault();if(f.reportValidity())void act(b,action);});}
export function initializeCompletionUI(client){
 if(!client)return;let epoch=0;
 window.addEventListener('breakapp:workflow-loaded',async event=>{
  const {section,context,user,rpc,act,button,formatEuro}=event.detail,v=++epoch;
  section.querySelector('.completion-panels')?.remove();const extra=node('div','','completion-panels');section.append(extra);
  const staff=['bartender','school_admin'].includes(context.role),admin=context.role==='school_admin';
  try{
   if(context.role==='platform_admin'){
    const f=formCard(extra,'Nuova scuola'),slug=input(f,'Identificativo della scuola (es. liceo-verdi)'),name=input(f,'Nome della scuola'),bar=input(f,'Nome del bar'),lat=input(f,'Latitudine','number'),lon=input(f,'Longitudine','number');
    lat.step='any';lon.step='any';const mode=select(f,'Preparazione',[['active','Preparazione su ordine'],['ready_made','Prodotti già pronti']]),email=input(f,'Email verificata del primo Admin','email');
    submit(f,'Crea scuola e bar',()=>rpc('platform_onboard_school',{p_slug:slug.value,p_name:name.value,p_bar_name:bar.value,p_latitude:Number(lat.value),p_longitude:Number(lon.value),p_mode:mode.value,p_admin_email:email.value}),act);return;
   }
   const [individual,groups,changes,refunds,documents]=await Promise.all([
    client.from('orders').select('id,display_no,bar_id,status').eq(staff?'school_id':'customer_id',staff?context.schoolId:user.id).order('created_at',{ascending:false}).limit(100),
    rpc(staff?'list_staff_group_orders':'list_my_confirmed_group_orders',staff?{p_school:context.schoolId,p_bar:null}:{}),
    rpc('list_order_changes',{p_school:staff?context.schoolId:null}),rpc('list_cash_refund_obligations',{p_school:staff?context.schoolId:null}),
    staff?Promise.resolve([]):rpc('my_payment_documents',{})]);
   if(v!==epoch)return;if(individual.error)throw individual.error;
   const orders=[...(individual.data||[]).map(o=>({...o,kind:'individual',label:'#'+o.display_no})),...(groups||[]).filter(g=>staff||g.coordinator).map(o=>({...o,kind:'group',label:o.title||'Gruppo'}))].filter(o=>!['cancelled','delivered','no_show'].includes(o.status));
   const cards=node('div','','service-list');extra.append(node('h3','Proposte e modifiche'),cards);
   for(const c of changes||[]){
    const box=node('article','','order-card');box.append(node('strong',c.kind+' · '+c.state));
    if(c.payload.name)box.append(node('p',c.payload.quantity+' × '+c.payload.name+' · '+formatEuro(c.payload.quantity*c.payload.unit_cents)),node('p','Ingredienti: '+(c.payload.ingredients||'non indicati')),node('p','Allergeni: '+(c.payload.allergens||[]).join(', ')));
    if(c.owner_id===user.id&&c.state==='customer_pending'){
     for(const[label,action]of [['Accetta proposta','accept'],['Rifiuta proposta','reject'],['Annulla ordine e avvia rimborsi','cancel']])box.append(button(label,b=>act(b,async()=>{if(confirm(label+'?'))await rpc('respond_order_exception',{p_change:c.id,p_action:action,p_window:null});})));
     if(c.kind==='delay'){
      const o=await rpc('workflow_order_details',{p_kind:c.order_id?'individual':'group',p_order:c.order_id||c.group_order_id});
      const slots=await client.from('pickup_windows').select('id,service_date,starts_at').eq('bar_id',o.bar_id).eq('is_active',true).order('service_date').order('starts_at');
      const s=select(box,'Fascia alternativa',(slots.data||[]).map(w=>[w.id,w.service_date+' '+w.starts_at.slice(0,5)]));
      box.append(button('Scegli questa alternativa',b=>act(b,()=>rpc('respond_order_exception',{p_change:c.id,p_action:'alternative',p_window:s.value}))));
     }
    }
    if(staff&&c.kind==='amendment'&&c.state==='staff_pending'){
     box.append(node('p','Prodotti richiesti: '+(c.payload.items||[]).map(i=>i.quantity+' × '+i.name).join(', ')));
     for(const[label,accept]of [['Approva modifica',true],['Rifiuta modifica',false]])box.append(button(label,b=>act(b,()=>rpc('decide_order_amendment',{p_change:c.id,p_accept:accept}))));
    }cards.append(box);
   }
   if(!changes.length)cards.append(node('p','Nessuna proposta aperta.'));
   if(orders.length){
    const f=formCard(extra,staff?'Proponi sostituzione o nuovo orario':'Modifica o annulla un ordine'),choice=select(f,'Ordine',orders.map(o=>[o.kind+':'+o.id,o.label+' · '+o.status]));
    const body=node('div');f.append(body);
    const fill=async()=>{
     const selected=choice.value,[kind,id]=selected.split(':'),detail=await rpc('workflow_order_details',{p_kind:kind,p_order:id});
     const products=await client.from('products').select('id,name,price_cents,ingredients,allergens').eq('bar_id',detail.bar_id).eq('is_active',true).order('name');
     if(v!==epoch||choice.value!==selected)return;body.replaceChildren();
     if(staff){
      const type=select(body,'Tipo di proposta',[['substitution','Sostituzione prodotto'],['delay','Cambio orario']]);
      const line=select(body,'Riga da sostituire',detail.lines.map(i=>[i.line_id,i.quantity+' × '+(i.name||products.data?.find(p=>p.id===i.product_id)?.name||'Prodotto')]));
      const replacement=select(body,'Prodotto sostitutivo',(products.data||[]).map(p=>[p.id,p.name+' · '+formatEuro(p.price_cents)]));
      const info=node('p');body.append(info);const preview=()=>{const p=products.data?.find(p=>p.id===replacement.value);info.textContent=p?'Ingredienti: '+p.ingredients+' · Allergeni: '+p.allergens.join(', '):'';};replacement.addEventListener('change',preview);preview();
      const windows=await client.from('pickup_windows').select('id,service_date,starts_at').eq('bar_id',detail.bar_id).eq('is_active',true).order('service_date').order('starts_at');
      const win=select(body,'Nuova fascia',(windows.data||[]).map(w=>[w.id,w.service_date+' '+w.starts_at.slice(0,5)]));
      const send=button('Invia proposta al cliente',b=>act(b,()=>rpc('propose_order_exception',{p_kind:kind,p_order:id,p_type:type.value,p_line:line.value||null,p_product:replacement.value||null,p_window:win.value||null,p_key:crypto.randomUUID()})));body.append(send);
     }else{
      body.append(node('p','Totale '+formatEuro(detail.total_cents)+' · Residuo '+formatEuro(detail.due_cents)));
      if(kind==='individual'){
       const quantities=[];for(const p of products.data||[]){const q=input(body,p.name+' · '+formatEuro(p.price_cents),'number',String(detail.lines.find(i=>i.product_id===p.id)?.quantity||0));q.min='0';q.max='1000';q.step='1';quantities.push({p,q});}
       body.append(button('Invia modifica',b=>act(b,()=>rpc('request_order_amendment',{p_order:id,p_items:quantities.filter(x=>Number(x.q.value)>0).map(x=>({product_id:x.p.id,quantity:Number(x.q.value)})),p_key:crypto.randomUUID()}))));
      }
      body.append(button('Annulla ordine',b=>act(b,async()=>{if(confirm('Annullare e avviare gli eventuali rimborsi?'))await rpc('cancel_workflow_order',{p_kind:kind,p_order:id,p_key:crypto.randomUUID()});})));
     }
    };choice.addEventListener('change',()=>void fill());void fill();f.addEventListener('submit',e=>e.preventDefault());
   }
   if(refunds.length){extra.append(node('h3','Contanti da restituire'));for(const r of refunds){const box=node('article','','order-card');box.append(node('p',formatEuro(r.amount_cents)+' · '+r.status+' · '+r.reason));
    if(staff&&r.status==='pending')box.append(button('Registra restituzione fisica',b=>act(b,async()=>{const reason=prompt('Conferma restituzione fisica e motivo (almeno 8 caratteri)');if(reason)await rpc('confirm_cash_refund_return',{p_refund:r.id,p_reason:reason});})));extra.append(box);}}
   if(!staff){extra.append(node('h3','I tuoi pagamenti'),node('p','Conferme interne di pagamento e rimborsi. Non sostituiscono il documento fiscale.'));
    for(const p of documents||[])extra.append(node('p',new Date(p.created_at).toLocaleString('it-IT')+' · '+formatEuro(p.amount_cents)+' · '+p.status+' · rimborsi: '+p.refunds.map(r=>formatEuro(r.amount_cents)+' '+r.status).join(', ')));}
   if(admin){
    const bars=await client.from('bars').select('id,name').eq('school_id',context.schoolId).eq('is_active',true);
    const f=formCard(extra,'Coupon e bundle'),bar=select(f,'Bar',(bars.data||[]).map(b=>[b.id,b.name])),code=input(f,'Codice coupon'),title=input(f,'Titolo'),kind=select(f,'Tipo',[['percent','Sconto percentuale'],['unit_discount','Sconto in centesimi per prodotto'],['bundle','Bundle di prodotti']]),value=input(f,'Valore (% o centesimi)','number','10'),start=input(f,'Inizio','datetime-local'),end=input(f,'Fine','datetime-local'),max=input(f,'Utilizzi totali (vuoto: nessun limite)','number'),per=input(f,'Utilizzi per cliente','number','1');max.required=false;
    const recipe=[],recipeList=node('p');f.append(recipeList);
    const prod=await client.from('products').select('id,name').eq('school_id',context.schoolId).eq('is_active',true);
    const component=select(f,'Prodotto del bundle',(prod.data||[]).map(p=>[p.id,p.name])),qty=input(f,'Quantità del componente','number','1'),discount=input(f,'Sconto unitario del componente, centesimi','number','0');
    f.append(button('Aggiungi componente',async()=>{recipe.push({product_id:component.value,quantity:Number(qty.value),discount_cents:Number(discount.value)});recipeList.textContent=recipe.map(r=>r.quantity+' × '+(prod.data||[]).find(p=>p.id===r.product_id)?.name).join(', ');}));
    submit(f,'Crea promozione',()=>rpc('save_school_promotion',{p_id:null,p_bar:bar.value,p_code:code.value,p_title:title.value,p_kind:kind.value,p_value:Number(value.value),p_start:new Date(start.value).toISOString(),p_end:new Date(end.value).toISOString(),p_max:max.value?Number(max.value):null,p_per_user:Number(per.value),p_recipe:kind.value==='bundle'?recipe:[]}),act);
    const promos=await rpc('list_school_promotions',{p_bar:bar.value});for(const p of promos)extra.append(node('p',p.code+' · '+p.title),button('Disattiva '+p.code,b=>act(b,()=>rpc('save_school_promotion',{p_id:p.id,p_bar:bar.value,p_code:p.code,p_title:p.title,p_kind:p.kind,p_value:p.value,p_start:new Date().toISOString(),p_end:p.ends_at,p_max:null,p_per_user:1,p_recipe:[]}))));
    const classes=formCard(extra,'Importa classi da CSV o Excel'),file=input(classes,'File CSV o XLSX','file');file.accept='.csv,.xlsx';
    submit(classes,'Importa classi',async()=>rpc('import_school_classes',{p_school:context.schoolId,p_names:await readClassNames(file.files[0])}),act);
    const people=formCard(extra,'Assegna personale'),email=input(people,'Email verificata','email'),role=select(people,'Ruolo',[['bartender','Barista'],['warehouse_manager','Magazziniere']]);
    submit(people,'Assegna ruolo',()=>rpc('school_assign_staff',{p_school:context.schoolId,p_email:email.value,p_role:role.value}),act);
   }
  }catch(error){if(v===epoch)extra.append(node('p','Impossibile aggiornare: '+error.message));}
 });
}
