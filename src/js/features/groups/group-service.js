const $=id=>document.getElementById(id);
const make=(tag,value='',cls='')=>{const n=document.createElement(tag);n.className=cls;n.textContent=value;return n;};
const cents=n=>new Intl.NumberFormat('it-IT',{style:'currency',currency:'EUR'}).format(Number(n||0)/100);
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function parseToken(text){
 const raw=String(text||'').trim().replace(/^breakapp:group:/i,'');
 if(!UUID.test(raw))throw new Error('Codice gruppo non valido.');
 return raw;
}
export function initializeGroupService(client){
 if(!client)return;
 const panel=$('group-staff-panel'),list=$('group-staff-list'),
  active=$('group-staff-active'),feedback=$('group-staff-feedback');
 let context=null,version=0,focused=null,scannedId=null;
 const say=(message,error=false)=>{feedback.textContent=message;feedback.dataset.type=error?'error':'information';};
 async function listGroups(){
  if(!context)return;
  const seq=++version;
  say('Caricamento ordini di gruppo…');
  const {data,error}=await client.rpc('list_staff_group_orders',{
   p_school:context.schoolId,p_bar:null
  });
  if(seq!==version)return;
  list.replaceChildren();
  if(error)return say(error.message,true);
  if(!Array.isArray(data)||data.length===0)
   list.append(make('p','Nessun ordine di gruppo per questa scuola.'));
  for(const group of data||[]){
   const card=make('div','','service-list-item');
   card.append(make('strong',group.title+' · '+group.status),
    make('span',cents(group.total_cents)));
   const button=make('button','Apri','button button-outline button-small');
   button.type='button';button.addEventListener('click',()=>void openGroup(group.id));
   card.append(button);list.append(card);
  }
  say('Ordini di gruppo aggiornati.');
 }
 async function openGroup(id){
  const seq=++version;
  const {data,error}=await client.rpc('group_order_details',{p_group_order_id:id});
  if(seq!==version)return;
  if(error)return say(error.message,true);
  focused=data;
  active.hidden=false;active.replaceChildren();
  active.append(make('h4','Ordine gruppo · '+data.status),
   make('p','Totale '+cents(data.total_cents)+' · Saldato '+cents(data.paid_cents)+
    ' · Residuo '+cents(data.due_cents)));
  const ul=make('ul','','scan-item-list');
  for(const item of data.lines||[])ul.append(make('li',
   item.quantity+' × '+item.name+' · '+cents(item.subtotal_cents)));
  active.append(ul);
  if(scannedId===id&&data.pickup_lease_until){
   active.append(make('p','Sessione ritiro fino a '+
    new Date(data.pickup_lease_until).toLocaleTimeString('it-IT'),'catalog-help'));
  }
  async function action(label,rpc,args){
   if(!confirm(label))return;
   for(const button of active.querySelectorAll('button'))button.disabled=true;
   const {data:result,error:changeError}=await client.rpc(rpc,args);
   if(changeError){say(changeError.message,true);
    for(const button of active.querySelectorAll('button'))button.disabled=false;return;}
   await listGroups();await openGroup(id);
   say(rpc==='record_group_counter_payment'?
    'Incasso di '+cents(result?.amount_cents)+' registrato.':'Operazione confermata.');
  }
  if(data.status==='confirmed'||data.status==='preparing'){
   const ready=make('button','Segna tutto pronto','button button-outline button-small');
   ready.type='button';ready.addEventListener('click',()=>void action(
    'Confermi che tutti i prodotti del gruppo sono pronti?',
    'advance_group_order',{p_group_order_id:id,p_next:'ready'}));
   active.append(ready);
  }
  if(scannedId===id&&Number(data.due_cents)>0
     &&['confirmed','preparing','ready'].includes(data.status)){
   for(const [method,label] of [['cash','Incassa contanti'],['external_pos','Incassa POS esterno']]){
    const button=make('button',label,'button button-outline button-small');button.type='button';
    let key=crypto.randomUUID();
    button.addEventListener('click',()=>void action(
     'Confermi l’incasso del saldo residuo dal coordinatore?',
     'record_group_counter_payment',{
       p_group_order_id:id,p_method:method,p_request_key:key
     }));
    active.append(button);
   }
  }
  if(data.status==='ready'&&Number(data.due_cents)===0&&scannedId===id){
   const deliver=make('button','Consegna intero gruppo','button button-primary');
   deliver.type='button';deliver.addEventListener('click',()=>void action(
    'Confermi la consegna simultanea di tutti i prodotti al coordinatore?',
    'deliver_group_order',{p_group_order_id:id}));
   active.append(deliver);
  }
  if(data.status==='delivered')scannedId=null;
  if(data.status==='ready'&&Number(data.due_cents)>0&&scannedId!==id)
   active.append(make('p','Scansiona prima il QR del coordinatore per incassare.','catalog-help'));
 }
 async function scan(raw){
  if(!context)return say('Seleziona un profilo Barista o Admin con 2FA.',true);
  try{
   const token=parseToken(raw);
   say('Verifica QR del gruppo sul server…');
   const {data,error}=await client.rpc('scan_group_pickup',{p_pickup_token:token});
   if(error)throw error;
   scannedId=data.id;await openGroup(data.id);
   say('Ritiro avviato. Lease valido dieci minuti.');
  }catch(err){say(err.message||'Scansione non riuscita.',true);}
 }
 $('group-staff-scan-form').addEventListener('submit',event=>{
  event.preventDefault();void scan($('group-staff-token').value);
 });
 $('group-staff-refresh').addEventListener('click',()=>void listGroups());
 window.addEventListener('breakapp:group-pickup-scanned',event=>{
  if(!panel.hidden)void scan(event.detail?.token);
 });
 window.addEventListener('breakapp:workspace-context',event=>{
  const next=event.detail;
  context=next?.verified&&['bartender','school_admin'].includes(next.role)&&next.schoolId?
   next:null;
  panel.hidden=!context;focused=null;scannedId=null;active.hidden=true;version++;
  if(context)void listGroups();else list.replaceChildren();
 });
 window.addEventListener('breakapp:route-changed',event=>{
  if(event.detail?.route==='staff-orders-section'&&context)void listGroups();
 });
 client.auth.onAuthStateChange((_e,session)=>queueMicrotask(()=>{
  if(!session){context=null;version++;panel.hidden=true;active.hidden=true;scannedId=null;}
 }));
}
