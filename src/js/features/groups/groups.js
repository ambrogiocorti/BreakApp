const el=(tag,value='',css='')=>{const n=document.createElement(tag);n.className=css;n.textContent=value;return n;};
const byId=id=>document.getElementById(id);
const money=c=>new Intl.NumberFormat('it-IT',{style:'currency',currency:'EUR'}).format(c/100);
const dateRome=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'Europe/Rome',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
function inviteId(input){
 const value=String(input||'').trim();
 let candidate=value;
 try{const url=new URL(value);candidate=url.searchParams.get('invite')||'';}catch{/* direct token */}
 if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(candidate))
  throw new Error('Incolla un link di invito valido o il relativo codice UUID.');
 return candidate;
}
function coordinates(){
 return new Promise((resolve,reject)=>{
  if(!('geolocation' in navigator))return reject(new Error('Geolocalizzazione non supportata dal dispositivo.'));
  navigator.geolocation.getCurrentPosition(p=>{
   if(p.coords.accuracy>100)return reject(new Error('Precisione GPS superiore a 100 m: riprova all’aperto.'));
   resolve({p_latitude:p.coords.latitude,p_longitude:p.coords.longitude,
    p_accuracy_m:p.coords.accuracy,p_observed_at:new Date(p.timestamp).toISOString()});
  },e=>reject(new Error(e.code===1?'Autorizza la posizione per entrare nel gruppo.':
    'Posizione non disponibile: '+e.message)),{enableHighAccuracy:true,maximumAge:0,timeout:15000});
 });
}
export function initializeGroupDrafts(client){
 if(!client)return;
 const panel=byId('groups'),list=byId('groups-list'),feedback=byId('groups-feedback'),
  createForm=byId('groups-create-form'),joinForm=byId('groups-join-form'),
  school=byId('groups-school'),bar=byId('groups-bar'),windowSelect=byId('groups-window'),
  detailPanel=byId('group-detail'),productsPanel=byId('group-products'),
  membersPanel=byId('group-members'),cartForm=byId('group-cart-form');
 let user=null,schools=[],bars=[],windows=[],products=[],detail=null,version=0,createdKey=null;
 const report=(message,error=false)=>{
  feedback.textContent=message;feedback.dataset.type=error?'error':'information';
 };
 function options(select,values){
  const old=select.value;select.replaceChildren();
  for(const [id,name] of values)select.add(new Option(name,id));
  if(values.some(x=>x[0]===old))select.value=old;
 }
 async function selectSchool(){
  options(bar,bars.filter(b=>b.school_id===school.value).map(b=>[b.id,b.name]));
  await selectBar();
 }
 async function selectBar(){
  options(windowSelect,windows.filter(w=>w.bar_id===bar.value).map(w=>[w.id,
   w.service_date+' · '+w.starts_at.slice(0,5)+'–'+w.ends_at.slice(0,5)]));
 }
 async function schoolsAndWindows(){
  const [a,b,w]=await Promise.all([
   client.from('schools').select('id,name').eq('is_active',true).order('name'),
   client.from('bars').select('id,school_id,name').eq('is_active',true).order('name'),
   client.from('pickup_windows').select('id,bar_id,service_date,starts_at,ends_at')
    .eq('is_active',true).gte('service_date',dateRome()).order('service_date').limit(150)
  ]);
  if(a.error||b.error||w.error)throw a.error||b.error||w.error;
  schools=a.data||[];bars=b.data||[];windows=w.data||[];
  options(school,schools.map(s=>[s.id,s.name]));
  await selectSchool();
 }
 async function myGroups(){
  const {data,error}=await client.rpc('list_my_group_drafts');
  if(error)throw error;
  list.replaceChildren();
  if(!Array.isArray(data)||!data.length)list.append(el('p','Nessuna bozza gruppo presente.'));
  for(const g of data||[]){
   const card=el('div','','group-draft-row');
   card.append(el('strong',g.title),el('small',
     (g.coordinator?'Coordinatore':'Partecipante')+' · '+g.my_status+
      ' · '+(g.status==='draft'?'Bozza':g.status)));
   const open=el('button','Apri gruppo','button button-outline button-small');
   open.type='button';open.addEventListener('click',()=>void showGroup(g.id));
   card.append(open);list.append(card);
  }
 }
 function renderLines(){
  productsPanel.replaceChildren();
  for(const p of products){
   const row=el('div','','group-product-row');
   const desc=el('div','','group-product-desc');
   desc.append(el('strong',p.name),el('span',money(p.price_cents)));
   const qty=el('input');qty.type='number';qty.min='0';qty.max='1000';qty.step='1';
   qty.value=String(detail.my_items.find(x=>x.product_id===p.id)?.quantity||0);
   qty.dataset.productId=p.id;
   qty.setAttribute('aria-label','Quantità di '+p.name);
   row.append(desc,qty);productsPanel.append(row);
  }
  if(!products.length)productsPanel.append(el('p','Nessun prodotto pubblicato per questo bar.'));
 }
 async function showGroup(id){
  const seq=++version;
  report('Caricamento bozza gruppo…');
  const {data,error}=await client.rpc('group_draft_details',{p_group_id:id});
  if(seq!==version)return;
  if(error){report(error.message,true);return;}
  detail=data;
  detailPanel.hidden=false;
  byId('group-detail-title').textContent=detail.title;
  byId('group-detail-meta').textContent=
   'Stato: '+detail.status+' · '+(detail.coordinator?'Coordinatore':'Partecipante')+
   ' · iscrizione: '+detail.my_status;
  byId('group-aggregate').replaceChildren(
   el('strong','Riepilogo aggregato'),
   el('span',(detail.totals?.count||0)+' prodotti · '+money(Number(detail.totals?.total_cents||0)))
  );
  const invite=byId('group-invite');
  invite.hidden=!detail.coordinator||!detail.invite_token;
  if(!invite.hidden){
   const u=new URL(location.href);
   u.searchParams.set('invite',detail.invite_token);u.hash='groups';
   byId('group-invite-link').value=u.toString();
  }
  const canPay=detail.my_status==='accepted'&&['draft','confirmed','approval_pending'].includes(detail.status);
  byId('group-payments-panel').hidden=!canPay;
  if(canPay)await loadPayableLines(detail.id,seq);
  const accepted=detail.my_status==='accepted'&&detail.status==='draft';
  byId('group-personal').hidden=!accepted;
  byId('group-coordinator-panel').hidden=!detail.coordinator;
  const managing=detail.coordinator&&detail.status==='draft';
  byId('group-manage').hidden=!managing;
  let couponBox=byId('group-coupon-box');
  if(!couponBox){couponBox=el('div','','order-actions');couponBox.id='group-coupon-box';const code=el('input');code.id='group-coupon-code';code.maxLength=32;code.placeholder='Codice coupon del gruppo';code.setAttribute('aria-label','Codice coupon del gruppo');
   const apply=el('button','Applica coupon al gruppo','button button-outline button-small');apply.type='button';
   apply.addEventListener('click',async()=>{const r=await client.rpc('apply_group_promotion',{p_group:detail.id,p_code:code.value,p_key:crypto.randomUUID()});if(r.error)return report(r.error.message,true);await showGroup(detail.id);});
   couponBox.append(code,apply);byId('group-manage').append(couponBox);}
  couponBox.hidden=!managing;
  byId('group-leave').hidden=detail.status!=='draft'||!['accepted','pending'].includes(detail.my_status);
  if(managing){
   byId('group-accepting').checked=detail.accepting_members;
   byId('group-approval').checked=detail.requires_approval;
   byId('group-limit').value=detail.max_members??'';
   const candidates=Array.isArray(detail.members)?detail.members.filter(
    m=>m.status==='accepted'&&m.member_id!==user.id):[];
   options(byId('group-transfer-member'),candidates.map(m=>[m.member_id,m.member_id.slice(0,8)]));
   const possible=windows.filter(w=>w.bar_id===detail.bar_id);
   options(byId('group-reschedule-window'),possible.map(w=>[w.id,
     w.service_date+' · '+w.starts_at.slice(0,5)+'–'+w.ends_at.slice(0,5)]));
   byId('group-reschedule-window').value=detail.pickup_window_id;
   byId('group-transfer').disabled=!candidates.length;
  }
  byId('group-confirm-panel').hidden=!managing;
  if(!managing)byId('group-accept-unready').checked=false;
  byId('group-confirmed-panel').hidden=true;
  if(['confirmed','approval_pending'].includes(detail.status))await loadConfirmedGroup(detail.id,seq);
  const readyButton=byId('group-ready');
  readyButton.textContent=detail.my_ready?'Modifica il mio ordine':'Ho finito';
  cartForm.hidden=!accepted||Boolean(detail.my_ready);
  if(accepted){
   const p=await client.from('products')
    .select('id,name,price_cents,category_id,categories!inner(is_active)')
    .eq('school_id',detail.school_id).eq('bar_id',detail.bar_id)
    .eq('is_active',true).eq('categories.is_active',true).order('name');
   if(seq!==version)return;
   if(p.error){report(p.error.message,true);return;}
   products=p.data||[];renderLines();
  }
  membersPanel.replaceChildren();
  if(detail.coordinator && Array.isArray(detail.members)){
   for(const m of detail.members){
    const row=el('div','','group-member-row');
    row.append(el('span',(m.member_id===user.id?'Io':m.member_id.slice(0,8))+
      ' · '+m.status+' · '+(m.ready?'Pronto':'In composizione')+' · '+m.line_count+' prodotti'));
    if(m.status==='pending'){
     for(const [label,approved] of [['Approva',true],['Rifiuta',false]]){
      const btn=el('button',label,'button button-outline button-small');btn.type='button';
      btn.addEventListener('click',async()=>{
       btn.disabled=true;
       const r=await client.rpc('review_group_member',{
        p_group_id:detail.id,p_member_id:m.member_id,p_approve:approved});
       if(r.error){report(r.error.message,true);btn.disabled=false;return;}
       await showGroup(detail.id);await myGroups();
      });
      row.append(btn);
     }
    }
    membersPanel.append(row);
   }
  }
  report(detail.my_status==='pending'
    ?'In attesa dell’approvazione del coordinatore.'
    :'Gruppo caricato. Le bozze non riservano scorte né incassano denaro.');
 }
 async function reload(){
  if(!user)return;
  report('Aggiornamento gruppi…');
  try{await schoolsAndWindows();await myGroups();report('Elenco gruppi aggiornato.');}
  catch(err){report(err.message,true);}
 }
 createForm.addEventListener('submit',async event=>{
  event.preventDefault();if(!user||!createForm.reportValidity())return;
  const button=createForm.querySelector('button[type=submit]');button.disabled=true;
  createdKey ||= crypto.randomUUID();
  const limit=byId('groups-limit').value;
  const {data,error}=await client.rpc('create_group_draft',{
   p_bar_id:bar.value,p_window_id:windowSelect.value,p_request_key:createdKey,
   p_title:byId('groups-create-title').value.trim(),
   p_requires_approval:byId('groups-entry-mode').value==='approval',
   p_max_members:limit?Number(limit):null
  });
  button.disabled=false;
  if(error){report(error.message,true);return;}
  createdKey=null;createForm.reset();
  await myGroups();await showGroup(data);
 });
 joinForm.addEventListener('submit',async event=>{
  event.preventDefault();if(!user||!joinForm.reportValidity())return;
  const button=joinForm.querySelector('button[type=submit]');button.disabled=true;
  try{
   const token=inviteId(byId('groups-invite-token').value);
   report('Richiesta del consenso GPS…');
   const pos=await coordinates();
   const {data,error}=await client.rpc('join_group_draft',{p_invite_token:token,...pos});
   if(error)throw error;
   await myGroups();await showGroup(data);
  }catch(err){report(err.message,true);}
  finally{button.disabled=false;}
 });
 cartForm.addEventListener('submit',async event=>{
  event.preventDefault();if(!detail||!user)return;
  const items=[];
  for(const n of productsPanel.querySelectorAll('input[data-product-id]')){
   const q=Number(n.value);
   if(!Number.isSafeInteger(q)||q<0||q>1000)return report('Quantità non valida.',true);
   if(q>0)items.push({product_id:n.dataset.productId,quantity:q});
  }
  const {error}=await client.rpc('replace_group_personal_cart',{p_group_id:detail.id,p_items:items});
  if(error)return report(error.message,true);
  await showGroup(detail.id);
 });
 byId('group-ready').addEventListener('click',async()=>{
  if(!detail)return;
  const {error}=await client.rpc('set_group_personal_ready',{
    p_group_id:detail.id,p_ready:!detail.my_ready
  });
  if(error)return report(error.message,true);
  await showGroup(detail.id);
 });
 async function loadPayableLines(groupId,seq){
  const {data,error}=await client.rpc('group_payable_lines',{p_group_id:groupId});
  if(seq!==version)return;
  const list=byId('group-payable-list');list.replaceChildren();
  if(error){report(error.message,true);return;}
  for(const line of data||[]){
   const row=el('label','','group-member-row');
   const check=el('input');check.type='checkbox';check.value=line.line_id;
   check.dataset.amountCents=String(line.amount_cents);
   check.disabled=line.payment_state!=='available'||Number(line.amount_cents)<=0;
   const own=line.beneficiary_id?(' · '+line.beneficiary_id.slice(0,8)):'';
   row.append(check,el('span',line.quantity+' × '+line.product_name+
    ' · '+money(line.amount_cents)+' · '+line.payment_state+own));
   list.append(row);
  }
  if(!data?.length)list.append(el('p','Nessuna riga da pagare.'));
 }
 byId('group-pay-selected').addEventListener('click',async()=>{
  if(!detail||!['draft','confirmed','approval_pending'].includes(detail.status))return;
  const lines=[...byId('group-payable-list').querySelectorAll('input[type=checkbox]:checked')]
   .map(n=>n.value).sort();
  if(!lines.length)return report('Seleziona almeno una riga disponibile.',true);
  const button=byId('group-pay-selected');button.disabled=true;
  const key='breakapp:group-checkout:'+detail.id;
  const signature=lines.join(',');
  let requestKey;
  try{
   const saved=JSON.parse(sessionStorage.getItem(key)||'null');
   requestKey=saved?.signature===signature?saved.requestKey:crypto.randomUUID();
   sessionStorage.setItem(key,JSON.stringify({signature,requestKey}));
   report('Avvio Checkout Stripe…');
   const {data,error}=await client.functions.invoke('stripe-checkout-group',{
    body:{group_id:detail.id,line_ids:lines,request_key:requestKey}
   });
   if(error)throw error;
   if(!data?.checkout_url||!data.checkout_url.startsWith('https://checkout.stripe.com/'))
    throw new Error(data?.error||'Risposta Checkout incompleta.');
   location.assign(data.checkout_url);
  }catch(err){report(err.message||'Checkout non disponibile.',true);button.disabled=false;}
 });
 let finalConfirmKey=null;
 async function loadConfirmedGroup(groupId,seq){
  const {data:orders,error}=await client.rpc('list_my_confirmed_group_orders');
  if(seq!==version)return;
  if(error)return report(error.message,true);
  const order=(orders||[]).find(o=>o.group_id===groupId);
  if(!order)return report('Ordine confermato non disponibile.',true);
  const {data:summary,error:summaryError}=await client.rpc('group_order_details',{
   p_group_order_id:order.id
  });
  if(seq!==version)return;
  if(summaryError)return report(summaryError.message,true);
  byId('group-confirmed-panel').hidden=false;
  byId('group-confirmed-summary').replaceChildren(
   el('strong','Stato: '+summary.status),
   el('p','Totale '+money(Number(summary.total_cents||0))+
     ' · Pagato '+money(Number(summary.paid_cents||0))+
     ' · Residuo '+money(Number(summary.due_cents||0))),
   el('p','Ritiro unico dal coordinatore, dopo il saldo completo.')
  );
  const box=byId('group-ticket-qr');box.replaceChildren();
  byId('group-ticket-token').textContent='';
  if(summary.coordinator&&summary.pickup_token){
   try{
    if(typeof window.QRCode!=='function')throw new Error('QR non disponibile');
    new window.QRCode(box,{text:'breakapp:group:'+summary.pickup_token,
     width:225,height:225,colorDark:'#080f21',colorLight:'#ffffff',
     correctLevel:window.QRCode.CorrectLevel.M});
   }catch{box.append(el('p','Mostra al Barista il codice UUID.'));}
   byId('group-ticket-token').textContent='Codice di ritiro: '+summary.pickup_token;
  }
  const cancel=byId('group-cancel-confirmed');
  cancel.hidden=!summary.coordinator||!['confirmed','ready'].includes(summary.status);
  cancel.dataset.orderId=summary.id;
 }
 byId('group-confirm').addEventListener('click',async()=>{
  if(!detail?.coordinator||detail.status!=='draft')return;
  const unready=byId('group-accept-unready').checked;
  if(!unready&&Array.isArray(detail.members)&&detail.members.some(
   m=>m.status==='accepted'&&!m.ready))
   return report('Conferma esplicitamente i partecipanti non pronti.',true);
  const button=byId('group-confirm');button.disabled=true;
  finalConfirmKey ||=crypto.randomUUID();
  try{
   report('Verifica GPS, disponibilità e scorte…');
   const gps=await coordinates();
   const {data:order,error}=await client.rpc('confirm_group_order',{
    p_group_id:detail.id,p_request_key:finalConfirmKey,
    p_accept_unready:unready,...gps
   });
   if(error)throw error;
   finalConfirmKey=null;
   await myGroups();await showGroup(detail.id);
   report('Ordine gruppo confermato: '+order.slice(0,8)+'.');
  }catch(err){report(err.message||'Conferma non riuscita.',true);}
  finally{button.disabled=false;}
 });
 byId('group-cancel-confirmed').addEventListener('click',async()=>{
  const id=byId('group-cancel-confirmed').dataset.orderId;
  if(!id||!confirm('Annullare l’intero ordine e liberare le scorte?'))return;
  const {error}=await client.rpc('cancel_confirmed_group_order',{p_group_order_id:id});
  if(error)return report(error.message,true);
  await myGroups();if(detail)await showGroup(detail.id);
  report('Ordine annullato e scorte ripristinate.');
 });
 async function mutateGroup(rpc,args,{close=false,success='Gruppo aggiornato.'}={}){
  if(!detail)return;
  const id=detail.id;
  report('Salvataggio sul server…');
  const {error}=await client.rpc(rpc,args);
  if(error)return report(error.message,true);
  if(close){detail=null;detailPanel.hidden=true;await myGroups();report(success);return;}
  await myGroups();await showGroup(id);
  report(success);
 }
 byId('group-save-settings').addEventListener('click',async()=>{
  if(!detail||!detail.coordinator)return;
  const field=byId('group-limit');
  const limit=field.value===''?null:Number(field.value);
  if(limit!==null&&(!Number.isInteger(limit)||limit<1||limit>100))
   return report('Il limite deve essere un intero tra 1 e 100.',true);
  await mutateGroup('configure_group_draft',{
   p_group_id:detail.id,p_accepting:byId('group-accepting').checked,
   p_requires_approval:byId('group-approval').checked,p_max_members:limit,p_rotate_invite:false
  });
 });
 byId('group-rotate-invite').addEventListener('click',async()=>{
  if(!detail||!detail.coordinator||!confirm('Il precedente link smetterà di funzionare. Continuare?'))return;
  await mutateGroup('configure_group_draft',{
   p_group_id:detail.id,p_accepting:byId('group-accepting').checked,
   p_requires_approval:byId('group-approval').checked,
   p_max_members:byId('group-limit').value===''?null:Number(byId('group-limit').value),
   p_rotate_invite:true
  },{success:'Invito rigenerato: condividi il nuovo link.'});
 });
 byId('group-transfer').addEventListener('click',async()=>{
  const target=byId('group-transfer-member').value;
  if(!detail||!detail.coordinator||!target||!confirm('Trasferire subito il ruolo di coordinatore?'))return;
  await mutateGroup('transfer_group_coordinator',{
   p_group_id:detail.id,p_new_coordinator:target
  },{success:'Coordinamento trasferito.'});
 });
 byId('group-reschedule').addEventListener('click',async()=>{
  const selected=byId('group-reschedule-window').value;
  if(!detail||!selected)return report('Seleziona una nuova fascia valida.',true);
  await mutateGroup('reschedule_group_draft',{p_group_id:detail.id,p_window_id:selected},
   {success:'Fascia di ritiro della bozza aggiornata.'});
 });
 byId('group-leave').addEventListener('click',async()=>{
  if(!detail||!confirm('Uscire dal gruppo? Il tuo carrello non pagato verrà eliminato.'))return;
  await mutateGroup('leave_group_draft',{p_group_id:detail.id},
   {close:true,success:'Hai lasciato il gruppo (oppure sciolto il gruppo se eri solo).'});
 });
 byId('group-cancel').addEventListener('click',async()=>{
  if(!detail||!detail.coordinator||!confirm('Annullare l’intera bozza di gruppo?'))return;
  await mutateGroup('cancel_group_draft',{p_group_id:detail.id},
   {close:true,success:'Bozza di gruppo annullata.'});
 });
 byId('group-invite-copy').addEventListener('click',async()=>{
  try{await navigator.clipboard.writeText(byId('group-invite-link').value);
   report('Link invito copiato.');}
  catch{byId('group-invite-link').select();report('Seleziona e copia il link invito.');}
 });
 byId('groups-refresh').addEventListener('click',()=>void reload());
 school.addEventListener('change',()=>void selectSchool());
 bar.addEventListener('change',()=>void selectBar());
 window.addEventListener('breakapp:route-changed',event=>{
  if(event.detail?.route==='groups'&&user)void reload();
 });
 function session(next){
  const changed=user?.id!==next?.id;user=next;
  panel.hidden=!user;
  if(!user){version++;detail=null;detailPanel.hidden=true;list.replaceChildren();return;}
  if(changed)void reload();
  if(changed&&location.search.includes('invite=')){
   const invite=new URLSearchParams(location.search).get('invite');
   if(invite){byId('groups-invite-token').value=invite;location.hash='groups';}
  }
 }
 client.auth.onAuthStateChange((_event,s)=>queueMicrotask(()=>session(s?.user||null)));
 client.auth.getUser().then(({data,error})=>{if(!error)session(data?.user||null);});
}
