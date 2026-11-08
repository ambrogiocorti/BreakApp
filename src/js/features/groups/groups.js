import {accuratePosition} from '../../core/geolocation.js';
import {windowLabel} from '../orders/staff-board.js';
import {confirmDialog} from '../../core/dialog.js';
import {friendlyError} from '../../core/errors.js';
import {paymentError} from '../../core/payment-error.js';
import {showLocation,locationProblem} from '../../core/location-ui.js';

const el=(tag,value='',css='')=>{const n=document.createElement(tag);n.className=css;n.textContent=value;return n;};
const byId=id=>document.getElementById(id);
const money=c=>new Intl.NumberFormat('it-IT',{style:'currency',currency:'EUR'}).format(c/100);
const dateRome=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'Europe/Rome',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
const groupStatus=status=>({draft:'Bozza',confirmed:'Confermato',preparing:'In preparazione',ready:'Pronto al ritiro',delivered:'Consegnato',no_show:'Non ritirato',approval_pending:'In attesa di approvazione',approval_queued:'In coda per approvazione',approval_active:'In approvazione',awaiting_reschedule:'In attesa di una nuova fascia',expired:'Scaduto',cancelled:'Annullato'})[status]||'Stato da verificare';
const groupTone=status=>({draft:'brand',confirmed:'info',preparing:'warning',ready:'success',delivered:'neutral',cancelled:'neutral',expired:'neutral',no_show:'danger'})[status]||'warning';
const memberStatus=status=>({accepted:'Iscritto',pending:'In attesa',rejected:'Rifiutato',left:'Uscito'})[status]||'Stato da verificare';
const paymentStatus=status=>({available:'Da pagare',pending:'Pagamento in corso',paid:'Pagato',refund_pending:'Rimborso in corso',refunded:'Rimborsato'})[status]||'Stato da verificare';
function inviteId(input){
 const value=String(input||'').trim();
 let candidate=value;
 try{const url=new URL(value);candidate=url.searchParams.get('invite')||'';}catch{/* direct token */}
 if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(candidate))
  throw new Error('Incolla un link di invito valido o il relativo codice UUID.');
 return candidate;
}
async function coordinates(onProgress){
 const p=await accuratePosition({onProgress});
 return {p_latitude:p.coords.latitude,p_longitude:p.coords.longitude,
  p_accuracy_m:p.coords.accuracy,p_observed_at:new Date(p.timestamp).toISOString()};
}
export function initializeGroupDrafts(client){
 if(!client)return;
 const panel=byId('groups'),list=byId('groups-list'),feedback=byId('groups-feedback'),
  createForm=byId('groups-create-form'),joinForm=byId('groups-join-form'),
  school=byId('groups-school'),bar=byId('groups-bar'),windowSelect=byId('groups-window'),
  detailPanel=byId('group-detail'),overview=byId('groups-overview'),pageHeading=panel.querySelector('.group-page-heading'),productsPanel=byId('group-products'),
  membersPanel=byId('group-members'),cartForm=byId('group-cart-form');
 let user=null,schools=[],bars=[],windows=[],products=[],detail=null,version=0,createdKey=null,activeSchoolId=null;
 const report=(message,error=false)=>{
  feedback.textContent=error?friendlyError(message):message;feedback.dataset.type=error?'error':'information';
 };
 const locate=async(container,onProgress)=>{
  showLocation(container,'pending');
  try{
   const result=await coordinates(accuracy=>{showLocation(container,'improving',{detail:'Precisione attuale: circa ±'+accuracy+' m (serve entro 100 m).'});onProgress?.(accuracy);});
   showLocation(container,'ok',{detail:'Ora il server controlla che tu sia entro il raggio della scuola.'});
   return result;
  }catch(error){const key=locationProblem(error);if(key)showLocation(container,key,{detail:error.message});throw error;}
 };
 const serverLocation=(container,error)=>{const key=locationProblem(error);if(key==='far'||key==='server_accuracy'||key==='not_configured')showLocation(container,key);else showLocation(container,'idle');};
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
  options(windowSelect,windows.filter(w=>w.bar_id===bar.value).map(w=>[w.id,windowLabel(w)]));
  if(!windowSelect.options.length)windowSelect.add(new Option('Nessuna fascia disponibile',''));
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
  if(activeSchoolId&&schools.some(s=>s.id===activeSchoolId))school.value=activeSchoolId;
  await selectSchool();
 }
 async function myGroups(){
  const {data,error}=await client.rpc('list_my_group_drafts');
  if(error)throw error;
  list.replaceChildren();
  if(!Array.isArray(data)||!data.length){
   const guest=Boolean(user?.app_metadata?.guest||user?.is_anonymous);
   list.append(el('p',guest?'Non hai ancora gruppi. Partecipa con un invito.':'Non hai ancora gruppi. Creane uno o partecipa con un invito.'));
  }
  for(const g of data||[]){
   const card=el('div','','group-draft-row');
   const text=el('div','','group-draft-text');
   text.append(el('strong',g.title),el('small',
     (g.coordinator?'Coordini tu':'Partecipi')+(g.my_status==='accepted'?'':' · '+memberStatus(g.my_status))));
   const state=el('span',groupStatus(g.status),'status');state.dataset.tone=groupTone(g.status);
   const open=el('button','Apri','button button-outline button-small group-open');
   open.type='button';open.setAttribute('aria-label','Apri il gruppo '+g.title);
   open.addEventListener('click',()=>void showGroup(g.id,{focus:true}));
   card.append(text,state,open);list.append(card);
  }
 }
 function renderLines(){
  productsPanel.replaceChildren();
  for(const p of products){
   const row=el('div','','group-product-row');
   const desc=el('div','','group-product-desc');
   desc.append(el('strong',p.name),el('span',money(p.price_cents)));
   const qty=el('input');qty.type='number';qty.min='0';qty.max='1000';qty.step='1';qty.inputMode='numeric';
   qty.value=String(detail.my_items.find(x=>x.product_id===p.id)?.quantity||0);
   qty.dataset.productId=p.id;
   qty.setAttribute('aria-label','Quantità di '+p.name);
   const stepper=el('div','','stepper');
   const step=(label,delta,name)=>{const b=el('button',label);b.type='button';b.setAttribute('aria-label',name+' '+p.name);
    b.addEventListener('click',()=>{const next=Math.min(1000,Math.max(0,(Number(qty.value)||0)+delta));qty.value=String(next);mark();});return b;};
   const mark=()=>{row.dataset.selected=String(Number(qty.value)>0);updateDraftTotal();};
   qty.addEventListener('input',mark);
   stepper.append(step('−',-1,'Togli uno:'),qty,step('+',1,'Aggiungi uno:'));
   row.dataset.selected=String(Number(qty.value)>0);
   row.append(desc,stepper);productsPanel.append(row);
  }
  updateDraftTotal();
  if(!products.length)productsPanel.append(el('p','Nessun prodotto pubblicato per questo bar.'));
 }
 function updateDraftTotal(){
  const total=byId('group-draft-total');if(!total)return;
  let count=0,cents=0;
  for(const n of productsPanel.querySelectorAll('input[data-product-id]')){
   const q=Number(n.value);if(!Number.isSafeInteger(q)||q<1)continue;
   const p=products.find(x=>x.id===n.dataset.productId);count+=q;cents+=q*Number(p?.price_cents||0);
  }
  const dirty=detail&&(()=>{try{return normalizeCart(cartItems())!==normalizeCart(savedCart());}catch{return true;}})();
  total.replaceChildren(el('span',count?count+(count===1?' prodotto':' prodotti')+' · '+money(cents):'Nessun prodotto scelto'),
   el('small',dirty?'Modifiche non ancora salvate':'Salvato'));
  total.dataset.dirty=String(Boolean(dirty));
 }
 function renderReadySummary(){
  const box=byId('group-ready-summary');box.replaceChildren();
  const items=detail?.my_items||[];
  box.hidden=!detail?.my_ready;
  if(box.hidden)return;
  box.append(el('p','Hai finito. Ecco cosa hai scelto:','group-ready-title'));
  const ul=el('ul','','order-items');
  for(const item of items){
   const li=el('li');const name=item.product_name||products.find(p=>p.id===item.product_id)?.name||'Prodotto';
   li.append(el('b',item.quantity+'× '),document.createTextNode(name));ul.append(li);
  }
  if(!items.length)ul.append(el('li','Nessun prodotto: partecipi senza ordinare.'));
  box.append(ul);
 }
 function renderProgress(){
  const box=byId('group-progress');box.replaceChildren();
  const members=(Array.isArray(detail?.members)?detail.members:[]).filter(m=>m.status==='accepted');
  box.hidden=detail?.status!=='draft'||!members.length;
  if(box.hidden)return;
  const ready=members.filter(m=>m.ready).length;
  const bar=el('div','','group-progress-bar');bar.setAttribute('role','progressbar');
  bar.setAttribute('aria-valuemin','0');bar.setAttribute('aria-valuemax',String(members.length));bar.setAttribute('aria-valuenow',String(ready));
  bar.setAttribute('aria-label','Partecipanti che hanno finito');
  const fill=el('span');fill.style.width=Math.round(ready/members.length*100)+'%';bar.append(fill);
  box.append(el('p',ready+' di '+members.length+(members.length===1?' partecipante ha':' partecipanti hanno')+' finito'),bar);
 }
 async function showGroup(id,{focus=false}={}){
  const seq=++version;
  report('Caricamento bozza gruppo…');
  const {data,error}=await client.rpc('group_draft_details',{p_group_id:id});
  if(seq!==version)return;
  if(error){report(error.message,true);return;}
  detail=data;
  detailPanel.hidden=false;
  overview.hidden=true;
  pageHeading.hidden=true;
  byId('group-detail-title').textContent=detail.title;
  const pickup=windows.find(w=>w.id===detail.pickup_window_id);
  const meta=byId('group-detail-meta');meta.replaceChildren();
  const state=el('span',groupStatus(detail.status),'status');state.dataset.tone=groupTone(detail.status);
  meta.append(state,el('span',(detail.coordinator?'Coordini tu':'Partecipi')+(detail.my_status==='accepted'?'':' · '+memberStatus(detail.my_status))));
  if(pickup)meta.append(el('span','Ritiro '+windowLabel(pickup)));
  byId('group-aggregate').replaceChildren(
   el('small','Totale del gruppo'),
   el('strong',money(Number(detail.totals?.total_cents||0))),
   el('span',(detail.totals?.count||0)+' prodotti')
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
   const remove=el('button','Rimuovi coupon','button button-outline button-small');remove.type='button';
   remove.addEventListener('click',async()=>{const r=await client.rpc('apply_group_promotion',{p_group:detail.id,p_code:'',p_key:crypto.randomUUID()});if(r.error)return report(r.error.message,true);code.value='';await showGroup(detail.id);});
   couponBox.append(code,apply,remove);byId('group-manage').querySelector('.group-manage-fields').append(couponBox);}
  couponBox.hidden=!managing;
  byId('group-leave').hidden=detail.status!=='draft'||!['accepted','pending'].includes(detail.my_status);
  if(managing){
   byId('group-accepting').checked=detail.accepting_members;
   byId('group-approval').checked=detail.requires_approval;
   byId('group-limit').value=detail.max_members??'';
   const candidates=Array.isArray(detail.members)?detail.members.filter(
    m=>m.status==='accepted'&&m.member_id!==user.id):[];
   options(byId('group-transfer-member'),candidates.map(m=>[m.member_id,'Partecipante '+m.member_id.slice(0,8)]));
   const possible=windows.filter(w=>w.bar_id===detail.bar_id);
   options(byId('group-reschedule-window'),possible.map(w=>[w.id,windowLabel(w)]));
   byId('group-reschedule-window').value=detail.pickup_window_id;
   byId('group-transfer').disabled=!candidates.length;
  }
  byId('group-confirm-panel').hidden=!managing;
  const unready=managing&&Array.isArray(detail.members)&&detail.members.some(m=>m.status==='accepted'&&!m.ready);
  byId('group-accept-unready-label').hidden=!unready;
  if(!unready)byId('group-accept-unready').checked=false;
  byId('group-confirmed-panel').hidden=true;
  if(['confirmed','approval_pending'].includes(detail.status))await loadConfirmedGroup(detail.id,seq);
  const readyButton=byId('group-ready');
  readyButton.textContent=detail.my_ready?'Modifica il mio ordine':'Ho finito';
  readyButton.className='button '+(detail.my_ready?'button-outline':'button-primary');
  const personal=byId('group-personal-state');
  personal.textContent=detail.my_ready?'Hai finito':'Da completare';personal.dataset.tone=detail.my_ready?'success':'warning';
  cartForm.hidden=!accepted||Boolean(detail.my_ready);
  renderProgress();
  if(accepted){
   const p=await client.from('products')
    .select('id,name,price_cents,category_id,categories!inner(is_active)')
    .eq('school_id',detail.school_id).eq('bar_id',detail.bar_id)
    .eq('is_active',true).eq('categories.is_active',true).order('name');
   if(seq!==version)return;
   if(p.error){report(p.error.message,true);return;}
   products=p.data||[];renderLines();
  }
  renderReadySummary();
  for(const id of ['group-confirm-location'])showLocation(byId(id),'idle');
  membersPanel.replaceChildren();
  const pending=(Array.isArray(detail.members)?detail.members:[]).filter(m=>m.status==='pending').length;
  byId('group-members-count').textContent=pending?' · '+pending+' in attesa':'';
  if(detail.coordinator && Array.isArray(detail.members)){
   for(const m of detail.members){
    const row=el('div','','group-member-row');
    const who=el('div','','group-member-text');
    who.append(el('strong',m.member_id===user.id?'Tu':'Partecipante '+m.member_id.slice(0,8)),
      el('small',(m.status==='accepted'?'':memberStatus(m.status)+' · ')+m.line_count+(Number(m.line_count)===1?' prodotto':' prodotti')));
    const badge=el('span',m.status!=='accepted'?memberStatus(m.status):m.ready?'Ha finito':'Sta scegliendo','status');
    badge.dataset.tone=m.status==='pending'?'warning':m.status!=='accepted'?'neutral':m.ready?'success':'neutral';
    row.append(who,badge);
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
  if(detail.my_status==='pending')report('In attesa dell’approvazione del coordinatore.');
  else if(feedback.dataset.type!=='error')report('');
  if(focus){
   for(const id of ['group-coordinator-panel','group-payments-panel','group-manage'])byId(id).open=false;
   byId('group-detail-title').focus();
  }
 }
 async function reload({announce=false}={}){
  if(!user)return;
  report('Aggiornamento gruppi…');
  try{await schoolsAndWindows();await myGroups();report(announce?'Elenco gruppi aggiornato.':'');}
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
  await myGroups();await showGroup(data,{focus:true});
 });
 joinForm.addEventListener('submit',async event=>{
  event.preventDefault();if(!user||!joinForm.reportValidity())return;
  const button=joinForm.querySelector('button[type=submit]');button.disabled=true;
  try{
   const token=inviteId(byId('groups-invite-token').value);
   report('Accesso al gruppo…');
   // The RPC retains the historical signature until all clients are updated.
   // Group entry does not require GPS; only final confirmation does.
   const {data,error}=await client.rpc('join_group_draft',{
    p_invite_token:token,p_latitude:null,p_longitude:null,
    p_accuracy_m:null,p_observed_at:null
   });
   if(error)throw error;
   await myGroups();await showGroup(data,{focus:true});
  }catch(err){report(err.message,true);}
  finally{button.disabled=false;}
 });
 function cartItems(){
  const items=[];
  for(const n of productsPanel.querySelectorAll('input[data-product-id]')){
   const q=Number(n.value);
   if(!Number.isSafeInteger(q)||q<0||q>1000)throw new Error('Quantità non valida.');
   if(q>0)items.push({product_id:n.dataset.productId,quantity:q});
  }
  return items;
 }
 const normalizeCart=rows=>JSON.stringify([...rows].sort((a,b)=>a.product_id.localeCompare(b.product_id)));
 const savedCart=()=>((detail?.my_items||[]).map(x=>({product_id:x.product_id,quantity:Number(x.quantity)})));
 cartForm.addEventListener('submit',async event=>{
  event.preventDefault();if(!detail||!user)return;
  let items;
  try{items=cartItems();}catch(error){return report(error.message,true);}
  const button=cartForm.querySelector('button[type=submit]'),ready=byId('group-ready');
  button.disabled=ready.disabled=true;
  try{
   const {error}=await client.rpc('replace_group_personal_cart',{p_group_id:detail.id,p_items:items});
   if(error)throw error;
   await showGroup(detail.id);report('Carrello salvato.');
  }catch(error){report(error.message||'Impossibile salvare il carrello.',true);}
  finally{button.disabled=ready.disabled=false;}
 });
 byId('group-ready').addEventListener('click',async()=>{
  if(!detail)return;
  const button=byId('group-ready'),save=cartForm.querySelector('button[type=submit]');
  let cartSaved=false;button.disabled=save.disabled=true;
  try{
   if(!detail.my_ready){
    const items=cartItems();
    const saved=savedCart();
    if(normalizeCart(items)!==normalizeCart(saved)){
     const visible=new Set(products.map(p=>p.id));
     if(saved.some(item=>!visible.has(item.product_id)))throw new Error('Alcuni prodotti non sono più disponibili. Verifica e salva il carrello prima di proseguire.');
     const result=await client.rpc('replace_group_personal_cart',{p_group_id:detail.id,p_items:items});
     if(result.error)throw result.error;
     cartSaved=true;
    }
   }
   const {error}=await client.rpc('set_group_personal_ready',{
     p_group_id:detail.id,p_ready:!detail.my_ready
   });
   if(error)throw error;
   await showGroup(detail.id);
  }catch(error){report((cartSaved?'Carrello salvato, ma non sei ancora segnato come pronto. ':'')+(error.message||'Impossibile aggiornare il carrello.'),true);}
  finally{button.disabled=save.disabled=false;}
 });
 async function loadPayableLines(groupId,seq){
  const {data,error}=await client.rpc('group_payable_lines',{p_group_id:groupId});
  if(seq!==version)return;
  const list=byId('group-payable-list');list.replaceChildren();
  if(error){report(error.message,true);return;}
  for(const line of data||[]){
   const row=el('label','','group-pay-row');
   const check=el('input');check.type='checkbox';check.value=line.line_id;
   check.dataset.amountCents=String(line.amount_cents);
   check.disabled=line.payment_state!=='available'||Number(line.amount_cents)<=0;
   const own=line.beneficiary_id?(' · '+(line.beneficiary_id===user.id?'Tu':'Partecipante '+line.beneficiary_id.slice(0,8))):'';
   const text=el('span','','group-pay-text');
   text.append(el('strong',line.quantity+'× '+line.product_name),el('small',paymentStatus(line.payment_state)+own));
   row.append(check,text,el('span',money(line.amount_cents),'group-pay-amount'));
   list.append(row);
  }
  if(!data?.length)list.append(el('p','Non ci sono ancora prodotti da pagare.'));
  byId('group-pay-selected').disabled=!(data||[]).some(line=>line.payment_state==='available'&&Number(line.amount_cents)>0);
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
   if(error)throw await paymentError(error);
   if(!data?.checkout_url||!data.checkout_url.startsWith('https://checkout.stripe.com/'))
    throw new Error(data?.error||'Risposta Checkout incompleta.');
   location.assign(data.checkout_url);
  }catch(err){report(friendlyError(err,'Checkout non disponibile.'),true);button.disabled=false;}
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
  const facts=el('dl','','group-facts');
  for(const [term,value] of [['Stato',groupStatus(summary.status)],['Totale',money(Number(summary.total_cents||0))],['Pagato',money(Number(summary.paid_cents||0))],['Da pagare',money(Number(summary.due_cents||0))]]){
   const row=el('div');row.append(el('dt',term),el('dd',value));facts.append(row);
  }
  byId('group-confirmed-summary').replaceChildren(facts,
   el('p','Ritiro unico dal coordinatore, dopo il saldo completo.','help'));
  const box=byId('group-ticket-qr');box.replaceChildren();
  byId('group-ticket-token').textContent='';
  if(summary.coordinator&&summary.pickup_token){
   try{
    if(typeof window.QRCode!=='function')throw new Error('QR non disponibile');
    new window.QRCode(box,{text:'breakapp:group:'+summary.pickup_token,
     width:225,height:225,colorDark:'#1c1917',colorLight:'#ffffff',
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
  if(!cartForm.hidden){
   try{
    if(normalizeCart(cartItems())!==normalizeCart(savedCart()))
     return report('Hai quantità non salvate: premi «Salva» o «Ho finito» prima di confermare.',true);
   }catch(error){return report(error.message,true);}
  }
  const unready=byId('group-accept-unready').checked;
  if(!unready&&Array.isArray(detail.members)&&detail.members.some(
   m=>m.status==='accepted'&&!m.ready))
   return report('Conferma esplicitamente i partecipanti non pronti.',true);
  const button=byId('group-confirm');button.disabled=true;
  const groupId=detail.id,requestVersion=version;
  finalConfirmKey ||=crypto.randomUUID();
  try{
   report('');
   const where=byId('group-confirm-location');
   let gps;
   try{gps=await locate(where);}catch(error){if(error.code)return;throw error;}
   report('Controllo di disponibilità e scorte…');
   if(version!==requestVersion||!detail||detail.id!==groupId||!detail.coordinator||detail.status!=='draft')return;
   if(!cartForm.hidden&&normalizeCart(cartItems())!==normalizeCart(savedCart()))
    throw new Error('Hai modificato il carrello durante la verifica: salvalo prima di confermare.');
   const {data:order,error}=await client.rpc('confirm_group_order',{
    p_group_id:detail.id,p_request_key:finalConfirmKey,
    p_accept_unready:unready,...gps
   });
   if(error){serverLocation(where,error);throw error;}
   finalConfirmKey=null;
   await myGroups();await showGroup(detail.id);
   report('Ordine del gruppo confermato.');
  }catch(err){if(locationProblem(err))report('');else report(err.message||'Conferma non riuscita.',true);}
  finally{button.disabled=false;}
 });
 byId('group-cancel-confirmed').addEventListener('click',async()=>{
  const id=byId('group-cancel-confirmed').dataset.orderId;
  if(!id||!await confirmDialog({title:'Annullare l’intero ordine?',message:'I prodotti tornano disponibili e i pagamenti online vengono rimborsati secondo le regole del gruppo.',confirmLabel:'Annulla l’ordine',cancelLabel:'Indietro',danger:true}))return;
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
  if(close){detail=null;detailPanel.hidden=true;overview.hidden=false;pageHeading.hidden=false;await myGroups();report(success);return;}
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
  if(!detail||!detail.coordinator||!await confirmDialog({title:'Creare un nuovo link di invito?',message:'Il link attuale smetterà di funzionare.',confirmLabel:'Crea nuovo link'}))return;
  await mutateGroup('configure_group_draft',{
   p_group_id:detail.id,p_accepting:byId('group-accepting').checked,
   p_requires_approval:byId('group-approval').checked,
   p_max_members:byId('group-limit').value===''?null:Number(byId('group-limit').value),
   p_rotate_invite:true
  },{success:'Invito rigenerato: condividi il nuovo link.'});
 });
 byId('group-transfer').addEventListener('click',async()=>{
  const target=byId('group-transfer-member').value;
  if(!detail||!detail.coordinator||!target||!await confirmDialog({title:'Passare il coordinamento?',message:'Il nuovo coordinatore gestirà conferma, ritiro e impostazioni del gruppo.',confirmLabel:'Passa il coordinamento'}))return;
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
  if(!detail||!await confirmDialog({title:'Uscire dal gruppo?',message:'I tuoi prodotti non pagati verranno tolti dal gruppo.',confirmLabel:'Esci dal gruppo',danger:true}))return;
  await mutateGroup('leave_group_draft',{p_group_id:detail.id},
   {close:true,success:'Hai lasciato il gruppo (oppure sciolto il gruppo se eri solo).'});
 });
 byId('group-cancel').addEventListener('click',async()=>{
  if(!detail||!detail.coordinator||!await confirmDialog({title:'Annullare il gruppo?',message:'Il gruppo verrà chiuso per tutti i partecipanti.',confirmLabel:'Annulla il gruppo',cancelLabel:'Indietro',danger:true}))return;
  await mutateGroup('cancel_group_draft',{p_group_id:detail.id},
   {close:true,success:'Bozza di gruppo annullata.'});
 });
 byId('group-invite-copy').addEventListener('click',async()=>{
  try{await navigator.clipboard.writeText(byId('group-invite-link').value);
   report('Link invito copiato.');}
  catch{byId('group-invite-link').hidden=false;byId('group-invite-link').select();report('Seleziona e copia il link invito.');}
 });
 byId('groups-refresh').addEventListener('click',()=>void reload({announce:true}));
 byId('group-back').addEventListener('click',()=>{
  version++;detail=null;detailPanel.hidden=true;overview.hidden=false;pageHeading.hidden=false;report('');
  byId('groups-heading').focus();
 });
 window.addEventListener('breakapp:workspace-context',event=>{
  if(event.detail?.role!=='customer')return;
  activeSchoolId=event.detail.schoolId||null;
  if(activeSchoolId&&schools.some(s=>s.id===activeSchoolId)){
   school.value=activeSchoolId;void selectSchool();
  }
 });
 school.addEventListener('change',()=>void selectSchool());
 bar.addEventListener('change',()=>void selectBar());
 window.addEventListener('breakapp:route-changed',event=>{
  if(event.detail?.route==='groups'&&user)void reload();
 });
 function session(next){
  const changed=user?.id!==next?.id;user=next;
  panel.hidden=!user;
  const guest=Boolean(user?.app_metadata?.guest||user?.is_anonymous);
  byId('groups-create-disclosure').hidden=guest;panel.classList.toggle('group-guest',guest);
  if(!user){version++;detail=null;detailPanel.hidden=true;overview.hidden=false;pageHeading.hidden=false;list.replaceChildren();return;}
  if(changed)void reload();
  if(changed&&location.search.includes('invite=')){
   const invite=new URLSearchParams(location.search).get('invite');
   if(invite){byId('groups-invite-token').value=invite;byId('groups-join-disclosure').open=true;location.hash='groups';}
  }
 }
 client.auth.onAuthStateChange((_event,s)=>queueMicrotask(()=>session(s?.user||null)));
 client.auth.getUser().then(({data,error})=>{if(!error)session(data?.user||null);});
}
