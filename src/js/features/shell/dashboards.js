import {exportSchoolOrdersCsv,downloadCsv} from './order-export.js';
import {icon} from '../../core/icons.js';
import {initializePlatformDashboard} from './platform-dashboard.js';
const make=(tag,text,cls='')=>{const n=document.createElement(tag);n.textContent=text;n.className=cls;return n;};
const money=cents=>new Intl.NumberFormat('it-IT',{style:'currency',currency:'EUR'}).format(cents/100);
const ORDER_LABELS={pending_approval:'Da approvare',approval_queued:'In coda',approval_active:'Da approvare',awaiting_reschedule:'Da riprogrammare',confirmed:'Confermato',preparing:'In preparazione',ready:'Pronto al ritiro',delivered:'Consegnato',cancelled:'Annullato',no_show:'Non ritirato'};
const PAYMENT_LABELS={due:'Da pagare',paid:'Pagato',pending:'In attesa',refund_pending:'Rimborso in corso',refunded:'Rimborsato'};
export function metric(label,value,note,iconName='LayoutDashboard'){
 const box=make('article','','metric-card'),heading=make('div','','metric-label'),pictogram=make('span','','metric-icon');
 pictogram.append(icon(iconName));heading.append(make('p',label),pictogram);
 box.append(heading,make('strong',String(value)),make('span',note));return box;
}
export function initializeWorkspaceDashboards(client) {
 if(!client)return;
 document.querySelectorAll('[data-icon]').forEach(node=>node.replaceChildren(icon(node.dataset.icon)));
 initializePlatformDashboard(client,metric);
 const admin=document.getElementById('admin-overview'),metrics=document.getElementById('dashboard-metrics'),
 recent=document.getElementById('dashboard-recent-orders'),feedback=document.getElementById('dashboard-feedback'),
 distribution=document.getElementById('dashboard-order-status');
 let context=null,version=0,user=null,loadedAt=0;
 const authorized=()=>user&&context?.role==='school_admin'&&context.verified&&context.schoolId;
 const exportButton=make('button','Esporta CSV','button button-outline button-small');
 exportButton.type='button';document.getElementById('dashboard-export').append(exportButton);
 exportButton.addEventListener('click',async()=>{
  if(!authorized())return;
  exportButton.disabled=true;feedback.textContent='Esportazione in corso…';
  const schoolId=context.schoolId;
  try{const result=await exportSchoolOrdersCsv(client,schoolId);
   if(!authorized()||context.schoolId!==schoolId)return;
   downloadCsv(result.csv,'breakapp-ordini-'+new Date().toISOString().slice(0,10)+'.csv');
   feedback.textContent=result.count+' ordini esportati'+(result.truncated?' (limite di 20.000 righe raggiunto)':'')+'.';
  }catch(error){if(authorized()&&context.schoolId===schoolId)feedback.textContent='Esportazione non riuscita: '+error.message;}
  finally{exportButton.disabled=false;}
 });
 async function refreshAdmin(){
  if(!authorized())return;
  const token=++version,schoolId=context.schoolId,refresh=document.getElementById('dashboard-refresh');
  refresh.disabled=true;metrics.setAttribute('aria-busy','true');feedback.textContent='Aggiornamento della panoramica…';
  try{
   const [orders,products,slots,notices]=await Promise.all([
    client.from('orders').select('id,display_no,status,payment_status,total_cents,created_at')
      .eq('school_id',schoolId).order('created_at',{ascending:false}).limit(500),
    client.from('products').select('id,is_active').eq('school_id',schoolId).limit(500),
    client.from('pickup_windows').select('id,is_active').eq('school_id',schoolId).limit(500),
    client.from('bar_service_state').select('bar_id,accepting_orders').eq('school_id',schoolId)
   ]);
   if(token!==version||!authorized()||context.schoolId!==schoolId)return;
   const error=orders.error||products.error||slots.error||notices.error;if(error)throw error;
   const os=orders.data||[],active=(products.data||[]).filter(x=>x.is_active),
    due=os.filter(x=>x.payment_status==='due'&&!['cancelled','delivered','no_show'].includes(x.status)),
    ongoing=os.filter(x=>['confirmed','preparing','ready'].includes(x.status)),
    unpaid=due.reduce((n,o)=>n+o.total_cents,0),paused=(notices.data||[]).filter(x=>!x.accepting_orders).length;
   metrics.replaceChildren(
    metric('Ordini in gestione',ongoing.length,'Confermati, in preparazione e pronti','ClipboardList'),
    metric('Da incassare',money(unpaid),'Sugli ultimi 500 ordini individuali','ShoppingBag'),
    metric('Prodotti attivi',active.length,'Nel catalogo della scuola','UtensilsCrossed'),
    metric('Fasce di ritiro',(slots.data||[]).filter(x=>x.is_active).length,paused?paused+' bar con prenotazioni in pausa':'Fasce attive configurate','CalendarDays')
   );
   recent.replaceChildren();
   for(const o of os.slice(0,6)){
    const row=make('div','','service-list-item');
    row.append(make('strong','Ordine #'+o.display_no),make('span',(ORDER_LABELS[o.status]||o.status)+' · '+money(o.total_cents)+' · '+(PAYMENT_LABELS[o.payment_status]||o.payment_status)));
    recent.append(row);
   }
   if(!os.length){const empty=make('div','','empty-state');empty.append(icon('ClipboardList'),make('strong','Nessun ordine, per ora'),make('p','I nuovi ordini della scuola compariranno qui.'));recent.append(empty);}
   distribution.replaceChildren();
   for(const status of ['confirmed','preparing','ready']){
    const count=os.filter(o=>o.status===status).length,box=make('div',''),label=make('div','','order-status-label'),track=make('div','','order-status-track'),value=make('div','','order-status-value');
    label.append(make('span',ORDER_LABELS[status]),make('strong',String(count)));value.style.width=(ongoing.length?100*count/ongoing.length:0)+'%';track.append(value);track.setAttribute('aria-hidden','true');box.append(label,track);distribution.append(box);
   }
   feedback.textContent='Aggiornato alle '+new Date().toLocaleTimeString('it-IT',{timeZone:'Europe/Rome',hour:'2-digit',minute:'2-digit'})+(os.length>=500?' · Panoramica limitata agli ultimi 500 ordini individuali.':' · Ordini individuali della scuola.');
   feedback.dataset.type='information';loadedAt=Date.now();
  }catch(error){
   if(token!==version)return;metrics.replaceChildren();recent.replaceChildren();distribution.replaceChildren();feedback.textContent='Dati non disponibili. '+error.message;feedback.dataset.type='error';
  }finally{if(token===version){refresh.disabled=false;metrics.setAttribute('aria-busy','false');}}
 }
 document.getElementById('dashboard-refresh').addEventListener('click',()=>void refreshAdmin());
 window.addEventListener('breakapp:workspace-context',event=>{
  context=event.detail;version++;loadedAt=0;admin.hidden=!authorized();
  if(authorized())void refreshAdmin();else{metrics.replaceChildren();recent.replaceChildren();distribution.replaceChildren();}
 });
 window.addEventListener('breakapp:route-changed',event=>{if(event.detail.route==='admin-overview'&&authorized()&&Date.now()-loadedAt>60000)void refreshAdmin();});
 client.auth.onAuthStateChange((_evt,session)=>queueMicrotask(()=>{
  const old=user?.id;user=session?.user||null;
  if(old!==user?.id){version++;metrics.replaceChildren();recent.replaceChildren();distribution.replaceChildren();}
  if(!user){admin.hidden=true;context=null;}else if(authorized()){admin.hidden=false;void refreshAdmin();}
 }));
 client.auth.getUser().then(({data,error})=>{if(!error){user=data?.user||null;if(authorized()){admin.hidden=false;void refreshAdmin();}}});
}
