const make=(tag,text,cls='')=>{const n=document.createElement(tag);n.textContent=text;n.className=cls;return n;};
const money=cents=>new Intl.NumberFormat('it-IT',{style:'currency',currency:'EUR'}).format(cents/100);
export function initializeWorkspaceDashboards(client) {
 if(!client)return;
 const admin=document.getElementById('admin-overview'),
 platform=document.getElementById('platform-overview'),
 metrics=document.getElementById('dashboard-metrics'),
 recent=document.getElementById('dashboard-recent-orders'),
 adminFeedback=document.getElementById('dashboard-feedback'),
 platformList=document.getElementById('platform-school-list'),
 platformFeedback=document.getElementById('platform-feedback');
 let context=null,version=0,user=null;
 function metric(label,value,note){
   const box=make('article','','metric-card');
   box.append(make('p',label),make('strong',String(value)),make('span',note));
   return box;
 }
 async function refreshAdmin(schoolId){
   const token=++version;
   adminFeedback.textContent='Caricamento indicatori reali della scuola…';
   const [orders,products,slots,notices]=await Promise.all([
    client.from('orders').select('id,display_no,status,payment_status,total_cents,created_at')
      .eq('school_id',schoolId).order('created_at',{ascending:false}).limit(500),
    client.from('products').select('id,is_active').eq('school_id',schoolId).limit(500),
    client.from('pickup_windows').select('id,is_active')
      .eq('school_id',schoolId).limit(500),
    client.from('bar_service_state').select('bar_id,accepting_orders')
      .eq('school_id',schoolId)
   ]);
   if(token!==version)return;
   const error=orders.error||products.error||slots.error||notices.error;
   if(error){adminFeedback.textContent='Non è possibile verificare i dati: '+error.message;
    metrics.replaceChildren();recent.replaceChildren();return;}
   const os=orders.data||[],active=(products.data||[]).filter(x=>x.is_active),
    due=os.filter(x=>x.payment_status==='due'&&!['cancelled','delivered'].includes(x.status)),
    ongoing=os.filter(x=>['confirmed','preparing','ready'].includes(x.status)),
    unpaid=due.reduce((n,o)=>n+o.total_cents,0);
   metrics.replaceChildren(
    metric('Ordini in gestione',ongoing.length,'Confermati, in preparazione o pronti'),
    metric('Importo ancora da incassare',money(unpaid),'Solo sugli ordini caricati'),
    metric('Prodotti attivi',active.length,'Prodotti pubblicati nel catalogo'),
    metric('Fasce attive',(slots.data||[]).filter(x=>x.is_active).length,'Fasce realmente configurate'),
    metric('Bar in pausa',(notices.data||[]).filter(x=>!x.accepting_orders).length,'Prenotazioni sospese')
   );
   recent.replaceChildren();
   for(const o of os.slice(0,8)){
     const row=make('div','','service-list-item');
     row.append(make('strong','Ordine #'+o.display_no),
       make('span',o.status+' · '+money(o.total_cents)+' · '+o.payment_status));
     recent.append(row);
   }
   if(!os.length)recent.append(make('p','Non ci sono ancora ordini in questa scuola.'));
   adminFeedback.textContent=os.length>=500
     ?'Mostrati i primi 500 ordini: questa panoramica non è ancora una rendicontazione completa.'
     :'Ultimo aggiornamento: '+new Date().toLocaleTimeString('it-IT');
 }
 async function refreshPlatform(){
   const token=++version;
   const auth=await client.rpc('is_current_platform_admin');
   if(token!==version||auth.error||auth.data!==true){
    platform.hidden=true;return;
   }
   const [schools,bars]=await Promise.all([
    client.from('schools').select('id,name,is_active').order('name'),
    client.from('bars').select('id,name,school_id,is_active').order('name')
   ]);
   if(token!==version)return;
   if(schools.error||bars.error){
     platformFeedback.textContent='Directory non disponibile: '+(schools.error||bars.error).message;return;
   }
   platformList.replaceChildren();
   for(const s of schools.data||[]){
     const item=make('article','','metric-card');
     item.append(make('strong',s.name),make('p',s.is_active?'Scuola attiva':'Scuola disattivata'));
     const names=(bars.data||[]).filter(b=>b.school_id===s.id).map(b=>b.name);
     item.append(make('span','Bar: '+(names.join(', ')||'nessuno')));
     platformList.append(item);
   }
   platformFeedback.textContent='Directory aggiornata. Le modifiche globali non ancora implementate non sono disponibili.';
 }
 function routeUpdate(){
   if(!context||!user)return;
   if(context.role==='school_admin' && context.verified && context.schoolId){
     admin.hidden=false;void refreshAdmin(context.schoolId);
   }else admin.hidden=true;
   if(context.role==='platform_admin'&&context.verified){
     platform.hidden=false;void refreshPlatform();
   }else platform.hidden=true;
 }
 window.addEventListener('breakapp:workspace-context',event=>{
   context=event.detail;
   if(context.role==='school_admin')context.verified=true;
   if(context.role==='platform_admin')context.verified=true;
   routeUpdate();
 });
 window.addEventListener('breakapp:route-changed',event=>{
   if(event.detail.route==='admin-overview'&&context?.role==='school_admin')routeUpdate();
   if(event.detail.route==='platform-overview'&&context?.role==='platform_admin')routeUpdate();
 });
 client.auth.onAuthStateChange((_evt,session)=>queueMicrotask(()=>{
   user=session?.user||null;
   if(!user){version++;admin.hidden=true;platform.hidden=true;context=null;}
 }));
 client.auth.getUser().then(({data,error})=>{
   if(!error){user=data?.user||null;if(user)routeUpdate();}
 });
}
