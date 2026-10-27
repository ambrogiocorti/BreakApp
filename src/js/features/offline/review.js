const $=id=>document.getElementById(id);
const element=(tag,text='',cls='')=>{const n=document.createElement(tag);n.textContent=text;n.className=cls;return n;};
const statusNames={quarantined:'In quarantena',approved:'Approvato per riconciliazione',rejected:'Rifiutato',applied:'Contabilizzato'};
const types={counter_sale:'Vendita al bancone',cash_pickup:'Ritiro con contanti',shift_change:'Cambio turno'};
export function initializeOfflineReview(client){
 if(!client)return;
 const panel=$('offline-review'),feedback=$('offline-review-feedback'),
  list=$('offline-review-list'),reload=$('offline-review-refresh'),
  conflicts=$('offline-stock-conflicts');
 let context=null,requestNo=0;
 const report=(message,isError=false)=>{feedback.textContent=message;feedback.dataset.type=isError?'error':'information';};
 async function refresh(){
  if(!context||panel.hidden)return;
  const school=context.schoolId,serial=++requestNo;
  report('Caricamento eventi offline da verificare…');
  reload.disabled=true;
  const {data,error}=await client.rpc('list_school_offline_events',{p_school:school});
  if(serial!==requestNo)return;
  reload.disabled=false;
  list.replaceChildren();
  if(error){report(error.message,true);return;}
  if(!Array.isArray(data)||!data.length){
   list.append(element('p','Nessuna operazione offline da revisionare.'));
  }
  for(const event of data){
   const row=element('article','','pilot-card');
   row.append(element('strong',types[event.event_kind]||'Evento offline'),
     element('p',(statusNames[event.status]||event.status)+
      ' · acquisito dal server: '+new Date(event.received_at).toLocaleString('it-IT')));
   const cents=Number(event.payload?.amount_cents);
   if(Number.isSafeInteger(cents)&&cents>=0)
    row.append(element('p','Importo dichiarato: '+
      new Intl.NumberFormat('it-IT',{style:'currency',currency:'EUR'}).format(cents/100)));
   row.append(element('p','Barista: '+String(event.barista_id||'').slice(0,8)+
     ' · dispositivo: '+String(event.device_id||'').slice(0,8)));
   if(event.local_recorded_at)row.append(element('small','Orario dichiarato dal dispositivo: '+
     new Date(event.local_recorded_at).toLocaleString('it-IT')+' (non verificato)'));
   if(event.review_reason)row.append(element('p','Motivo quarantena: '+String(event.review_reason).slice(0,500)));
   if(event.reviewer_note)row.append(element('p','Motivazione Admin: '+String(event.reviewer_note).slice(0,500)));
   if(typeof event.payload?.note==='string'&&event.payload.note)
    row.append(element('p','Nota operatore: '+event.payload.note.slice(0,300)));
   if(event.status==='quarantined'){
    const label=element('label','Motivazione obbligatoria della decisione (10–500 caratteri)');
    const reason=element('textarea');reason.id='offline-reason-'+event.id;
    label.htmlFor=reason.id;reason.rows=2;reason.maxLength=500;reason.minLength=10;
    reason.placeholder='Esito del controllo e riferimenti verificati';
    const actions=element('div','','staff-actions');
    for(const [caption,approve] of [['Approva per riconciliazione',true],['Rifiuta',false]]){
     const button=element('button',caption,'button button-outline button-small');button.type='button';
     button.addEventListener('click',async()=>{
      const why=reason.value.trim();
      if(why.length<10||why.length>500)return report('Inserisci una motivazione tra 10 e 500 caratteri.',true);
      if(!confirm('Registrare questa decisione? Non viene contabilizzato alcun incasso.'))return;
      for(const control of actions.querySelectorAll('button'))control.disabled=true;
      const {data:decision,error:decisionError}=await client.rpc('review_school_offline_event',{
       p_event_id:event.id,p_approve:approve,p_reason:why
      });
      if(decisionError){report(decisionError.message,true);
       for(const control of actions.querySelectorAll('button'))control.disabled=false;return;}
      await refresh();
      report((decision?.status==='approved'?'Approvazione':'Rifiuto')+
       ' registrato con audit. Nessuna vendita/incasso contabilizzato.');
     });
     actions.append(button);
    }
    row.append(label,reason,actions);
   }
   if(event.status==='approved'&&event.event_kind==='counter_sale'){
    const button=element('button','Contabilizza vendita approvata','button button-primary button-small');
    button.type='button';
    button.addEventListener('click',async()=>{
     if(!confirm('Registrare i contanti realmente verificati e aggiornare le scorte?'))return;
     button.disabled=true;
     const {data:receipt,error:e}=await client.rpc('apply_approved_offline_cash_event',{
      p_event:event.id
     });
     if(e){report(e.message,true);button.disabled=false;return;}
     await refresh();
     report(receipt.status==='applied'?'Vendita contabilizzata. Conflitti stock: '+
       (receipt.stock_conflicts||0):'Evento in verifica: '+(receipt.reason||receipt.status),
       receipt.status!=='applied');
    });
    row.append(button);
   }
   list.append(row);
  }
  const {data:pendingConflicts,error:conflictError}=await client.rpc(
   'list_school_stock_conflicts',{p_school:school});
  if(serial!==requestNo)return;
  conflicts.replaceChildren();
  if(conflictError){report(conflictError.message,true);return;}
  for(const c of pendingConflicts||[]){
   const box=element('article','','service-list-item');
   box.append(element('strong','Conflitto di magazzino · '+String(c.product_id).slice(0,8)),
    element('p','Data '+c.service_date+' · vendute offline '+c.sold_quantity+
     ' · riservate '+c.allocated+' · capacità '+c.capacity));
   const button=element('button','Riconcilia scorta fisica','button button-outline button-small');
   button.type='button';
   button.addEventListener('click',async()=>{
    const units=prompt('Nuova capacità verificata fisicamente (non inferiore alle prenotazioni):');
    if(units===null)return;
    const capacity=Number(units);
    if(!Number.isInteger(capacity)||capacity<Number(c.allocated))
     return report('Capacità non valida: non può essere inferiore al già prenotato.',true);
    const reason=prompt('Motivo dell’inventario e dettaglio verifica (almeno 10 caratteri):');
    if(!reason||reason.trim().length<10)return report('Motivazione obbligatoria.',true);
    if(!confirm('Salvare la rettifica di magazzino? Resterà nello storico.'))return;
    button.disabled=true;
    const {error:resolveError}=await client.rpc('resolve_offline_stock_conflict',{
     p_conflict:c.id,p_new_capacity:capacity,p_reason:reason.trim()
    });
    if(resolveError){report(resolveError.message,true);button.disabled=false;return;}
    await refresh();report('Scorta riconciliata con audit.');
   });
   box.append(button);conflicts.append(box);
  }
  if(!pendingConflicts?.length)conflicts.append(element('p','Nessun conflitto di magazzino aperto.'));
  report('Visualizzati '+data.length+' eventi e '+(pendingConflicts||[]).length+
   ' conflitti di magazzino.');
 }
 reload.addEventListener('click',()=>void refresh());
 window.addEventListener('breakapp:workspace-context',event=>{
  context=event.detail?.role==='school_admin'&&event.detail?.verified?event.detail:null;
  panel.hidden=!context;requestNo++;
  if(context)void refresh();else{list.replaceChildren();conflicts.replaceChildren();}
 });
 window.addEventListener('breakapp:route-changed',event=>{
  if(event.detail?.route==='offline-review'&&context)void refresh();
 });
 client.auth.onAuthStateChange((_e,s)=>queueMicrotask(()=>{
  if(!s){context=null;requestNo++;panel.hidden=true;list.replaceChildren();}
 }));
}
