import {formatEuro} from '../catalog/utils.js';
import {validateOfflinePin,pinSalt,deriveOfflineKey,sealOffline,unsealOffline,
 openOfflineDB,readDevice,saveDevice,appendPending,deletePending,readPending,readConfiguredOperators} from './vault.js';

const $=id=>document.getElementById(id);
const make=(tag,text='',cls='')=>{const x=document.createElement(tag);x.textContent=text;x.className=cls;return x;};
const MAX_IDLE_MS=5*60*1000;
const verifierText='breakapp-offline-device-verifier-v1';
export function initializeOfflineTerminal(client){
 if(!client)return;
 const panel=$('offline-terminal'),status=$('offline-status'),
  leaseView=$('offline-lease-summary'),queueView=$('offline-queue'),
  activateForm=$('offline-activate-form'),unlockForm=$('offline-unlock-form'),
  entryForm=$('offline-entry-form'),syncButton=$('offline-sync');
 let ctx=null,user=null,db=null,device=null,key=null,lastTouch=0,
  authVersion=0,pinFailures=0,blockedUntil=0,
  catalog=null,saleItems=[],onlineCashKey=null,manifest=null,pickupCandidate=null,cashSnapshot=null;
 const currentCashSession=barId=>(cashSnapshot?.sessions||[]).find(s=>
  s.bar_id===barId&&s.actor_id===user?.id&&!s.closed_at)?.id||null;
 async function queueLocal(payload){
  if(!touch()||!hasLease())throw new Error('PIN e autorizzazione offline validi richiesti.');
  const id=payload.request_key||crypto.randomUUID(),now=new Date().toISOString();
  const data={...payload,local_recorded_at:payload.local_recorded_at||now,request_key:id};
  await appendPending(db,device,{id,context:contextKey(),createdAt:now,
   encrypted:await sealOffline(key,data),deviceId:device.deviceId,generation:device.generation});
  await renderQueue();return id;
 }
 const info=(text,error=false)=>{status.textContent=text;status.dataset.type=error?'error':'information';};
 const lock=()=>{
  key=null;lastTouch=0;catalog=null;saleItems=[];onlineCashKey=null;manifest=null;pickupCandidate=null;cashSnapshot=null;
  window.dispatchEvent(new Event('breakapp:offline-vault-state'));
  $('offline-unlock-pin').value='';
  unlockForm.hidden=!device;
  entryForm.hidden=true;
  syncButton.disabled=true;
  $('offline-lock').disabled=true;
 };
 const touch=()=>{
  if(!key)return false;
  if(Date.now()-lastTouch>=MAX_IDLE_MS){lock();info('Sessione offline bloccata dopo 5 minuti.');return false;}
  lastTouch=Date.now();return true;
 };
 const contextKey=()=>ctx&&user?user.id+':'+ctx.schoolId:null;
 const hasLease=()=>Boolean(device&&Date.parse(device.expiresAt)>Date.now()
   &&(!localStorage.getItem('breakapp:offline-start')||Date.now()-Number(localStorage.getItem('breakapp:offline-start'))<8*60*60*1000)
   &&device.schoolId===ctx?.schoolId);
 const todayRome=()=>new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Rome',
  year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 const manifestForm=$('offline-pickup-form'),manifestSummary=$('offline-manifest-summary');
 const renderManifest=()=>{
  const valid=Boolean(manifest&&manifest.school_id===ctx?.schoolId&&
   manifest.service_date===todayRome());
  const total=valid?(manifest.orders||[]).length:0;
  manifestSummary.textContent=valid?total+' ordini pronti del giorno salvati localmente.':
   'Manifest non presente o di un altro giorno. Sincronizza online.';
  manifestForm.hidden=!key||!valid||!total;
 };
 async function refreshManifest(){
  if(!navigator.onLine||!touch()||!device||!ctx)throw new Error('PIN e connessione richiesti.');
  const {data,error}=await client.rpc('offline_ready_order_manifest',{p_school:ctx.schoolId});
  if(error)throw error;
  if(!data||!Array.isArray(data.orders)||data.school_id!==ctx.schoolId)
   throw new Error('Manifest non verificabile.');
  manifest=data;device.ordersEncrypted=await sealOffline(key,data);
  await saveDevice(db,device);pickupCandidate=null;renderManifest();
  return data.orders.length;
 }
 $('offline-refresh-manifest').addEventListener('click',async()=>{
  try{const n=await refreshManifest();info(n+' ordini pronti sincronizzati e cifrati.');}
  catch(e){info(e.message||'Manifest non disponibile.',true);}
 });
 $('offline-pickup-find').addEventListener('click',()=>{
  if(!touch()||!hasLease()||manifest?.service_date!==todayRome())
   return info('PIN, lease valido e manifest odierno richiesti.',true);
  const token=$('offline-pickup-token').value.trim();
  pickupCandidate=(manifest.orders||[]).find(o=>o.pickup_token===token)||null;
  $('offline-pickup-preview').textContent=pickupCandidate
   ?'Ordine '+pickupCandidate.display_no+' · '+formatEuro(pickupCandidate.total_cents)+
    ' · '+(pickupCandidate.payment_status==='paid'?'già saldato':
     'saldo in contanti da ricevere prima della consegna')
   :'QR non presente tra gli ordini pronti cifrati di oggi.';
 });
 manifestForm.addEventListener('submit',async event=>{
  event.preventDefault();
  if(!touch()||!hasLease()||manifest?.service_date!==todayRome()||!pickupCandidate)
   return info('Verifica prima un ordine pronto con QR valido.',true);
  const o=pickupCandidate;
  if(o.can_pickup_at&&Date.parse(o.can_pickup_at)>Date.now())return info('Attendi la fascia prenotata prima della consegna.',true);
  if(o.pickup_token!==$('offline-pickup-token').value.trim())
   return info('Il QR è cambiato: riverifica il codice.',true);
  const amount=Number(o.due_cents??(o.payment_status==='paid'?0:o.total_cents));
  if(!Number.isSafeInteger(amount)||amount<0||amount>1000000)
   return info('Totale non valido.',true);
  if(!confirm(amount
   ?'Hai ricevuto fisicamente '+formatEuro(amount)+' in contanti e consegnato l’ordine '+o.display_no+'?'
   :'Hai verificato il QR e consegnato fisicamente l’ordine già pagato '+o.display_no+'?'))return;
  const pending=await readPending(db,contextKey());
  for(const p of pending){
   const data=await unsealOffline(key,p.encrypted);
   if(['cash_pickup','group_pickup'].includes(data.kind)&&data.order_id===o.id)
    return info('La consegna è già nella coda locale.',true);
  }
  const eventId=crypto.randomUUID(),now=new Date().toISOString();
  const sessionId=currentCashSession(o.bar_id);
  if(amount&&!sessionId)return info('Apri prima il turno nella sezione Cassa.',true);
  const payload={kind:o.kind==='group'?'group_pickup':'cash_pickup',snapshot_id:manifest.snapshot_id,order_id:o.id,pickup_token:o.pickup_token,
   bar_id:o.bar_id,collected_cents:amount,
   cash_session_id:sessionId,
   snapshot_payment_status:o.payment_status,local_recorded_at:now,request_key:eventId};
  await queueLocal(payload);
  window.dispatchEvent(new CustomEvent('breakapp:cash-recorded',{detail:{sessionId,amount}}));
  manifest.orders=manifest.orders.filter(row=>row.id!==o.id);
  device.ordersEncrypted=await sealOffline(key,manifest);await saveDevice(db,device);
  pickupCandidate=null;manifestForm.reset();$('offline-pickup-preview').textContent='';
  renderManifest();await renderQueue();
  info('Consegna fisica registrata e cifrata: sincronizza appena possibile.');
 });
 const barInput=$('offline-sale-bar'),productInput=$('offline-sale-product'),
  quantityInput=$('offline-sale-quantity'),saleView=$('offline-sale-items');
 const saleSum=()=>saleItems.reduce((sum,item)=>sum+item.quantity*item.unit_cents,0);
 const renderSale=()=>{
  saleView.replaceChildren();
  for(const item of saleItems){
   const row=make('div','','service-list-item');
   row.append(make('span',item.quantity+' × '+item.name+' · '+formatEuro(item.quantity*item.unit_cents)));
   const remove=make('button','Rimuovi','button button-outline button-small');remove.type='button';
   remove.addEventListener('click',()=>{
    saleItems=saleItems.filter(x=>x.product_id!==item.product_id);onlineCashKey=null;renderSale();
   });row.append(remove);saleView.append(row);
  }
  $('offline-entry-amount').value=(saleSum()/100).toFixed(2).replace('.',',');
 };
 const renderCatalog=()=>{
  barInput.replaceChildren();productInput.replaceChildren();
  for(const bar of catalog?.bars||[]){
   const option=document.createElement('option');option.value=bar.id;option.textContent=bar.name;
   barInput.append(option);
  }
  if(ctx?.barId&&[...barInput.options].some(o=>o.value===ctx.barId))barInput.value=ctx.barId;
  const fillProducts=()=>{
   productInput.replaceChildren();
   for(const p of catalog?.products||[]){
    if(p.bar_id!==barInput.value)continue;
    const option=document.createElement('option');option.value=p.id;
    option.textContent=p.name+' · '+formatEuro(p.unit_cents);
    productInput.append(option);
   }
   saleItems=[];onlineCashKey=null;renderSale();
  };
  barInput.onchange=fillProducts;fillProducts();
  entryForm.querySelector('button[type=submit]').disabled=!catalog?.products?.length;
 };
 async function refreshCatalog(){
  if(!navigator.onLine||!key||!ctx||!device)return false;
  const {data,error}=await client.rpc('offline_bartender_catalog',{p_school:ctx.schoolId});
  if(error)throw error;
  if(!data||!Array.isArray(data.bars)||!Array.isArray(data.products))
   throw new Error('Catalogo offline non valido.');
  catalog=data;device.catalogEncrypted=await sealOffline(key,catalog);
  await saveDevice(db,device);renderCatalog();return true;
 }
 $('offline-refresh-catalog').addEventListener('click',async()=>{
  try{await refreshCatalog();info('Catalogo del giorno aggiornato e cifrato.');}
  catch(e){info(e.message||'Catalogo non aggiornabile.',true);}
 });
 $('offline-add-item').addEventListener('click',()=>{
  if(!touch()||!hasLease()||!catalog)return info('PIN e lease validi richiesti.',true);
  const product=(catalog.products||[]).find(p=>p.id===productInput.value&&p.bar_id===barInput.value);
  const qty=Number(quantityInput.value);
  if(!product||!Number.isInteger(qty)||qty<1||qty>1000)
   return info('Prodotto o quantità non validi.',true);
  if(catalog.service_date!==new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Rome',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date()))
   return info('Catalogo di un altro giorno: aggiornalo online.',true);
  const existing=saleItems.find(x=>x.product_id===product.id);
  if(existing){if(existing.quantity+qty>1000)return info('Quantità troppo elevata.',true);
   existing.quantity+=qty;}
  else saleItems.push({product_id:product.id,quantity:qty,
    unit_cents:product.unit_cents,name:product.name});
  onlineCashKey=null;renderSale();info('Riga aggiunta. La vendita viene salvata solo dopo conferma.');
 });
 const renderLease=()=>{
  leaseView.textContent=device
   ?'Dispositivo '+device.deviceId.slice(0,8)+
    ' · generazione '+device.generation+
    ' · lease fino al '+new Date(device.expiresAt).toLocaleString('it-IT')+
    (hasLease()?' · attivo localmente':' · scaduto')
   :'Nessun dispositivo registrato su questo browser.';
  // A locally expired lease must be renewable online after queued drafts
  // have been safely handed to the server.
  activateForm.hidden=Boolean(device&&hasLease());
  unlockForm.hidden=!device||Boolean(key);
  entryForm.hidden=!key;
  renderManifest();
  syncButton.disabled=!key||!navigator.onLine;
  $('offline-lock').disabled=!key;
  window.dispatchEvent(new Event('breakapp:offline-vault-state'));
 };
 async function renderQueue(){
  queueView.replaceChildren();
  if(!db||!contextKey())return;
  const records=await readPending(db,contextKey());
  if(!records.length){
    queueView.append(make('p','Nessuna operazione locale in attesa.'));
    return;
  }
  queueView.append(make('strong',
    records.length+' operazioni locali cifrate, non contabilizzate'));
  for(const record of records){
    const line=make('div','','service-list-item');
    line.append(make('span',record.createdAt+' · ID '+record.id.slice(0,8)),
      make('span','In attesa di invio/verifica server'));
    queueView.append(line);
  }
 }
 async function selectContext(next){
   const id=++authVersion;lock();ctx=next;db=null;device=null;user=null;catalog=null;saleItems=[];
   panel.hidden=next?.role!=='bartender'||!next?.schoolId;
   manifest=null;pickupCandidate=null;renderManifest();
   if(panel.hidden)return;
   info('Verifica autenticazione e dispositivo…');
   try{
     let identity;
     if(navigator.onLine){
      const {data,error}=await client.auth.getUser();
      if(error||!data?.user)throw new Error('Autenticazione online necessaria.');
      identity=data.user;
     }else{
      const {data}=await client.auth.getSession();
      identity=data?.session?.user;
      if(!identity)throw new Error('Nessuna sessione locale: riconnettiti per autenticarti.');
     }
     if(id!==authVersion)return;
     user=identity;db=await openOfflineDB();
     if(id!==authVersion)return;
     device=await readDevice(db,contextKey())||null;
     renderLease();await renderQueue();
     info(device?'Dispositivo trovato: inserisci il PIN per visualizzare le operazioni cifrate.':
       'Autorizza online un dispositivo per usare la coda locale offline.');
   }catch(err){
     if(id!==authVersion)return;
     info(err.message||'Dispositivo non verificabile.',true);
   }
 }
 activateForm.addEventListener('submit',async event=>{
   event.preventDefault();
   const pin=$('offline-activate-pin').value;
   if(!ctx||!user||!db||!navigator.onLine||!validateOfflinePin(pin)){
      return info('Per autorizzare un dispositivo servono connessione, account Barista e PIN valido.',true);
   }
   const pending=await readPending(db,contextKey());
   if(pending.length)return info('Prima di cambiare PIN o dispositivo invia la coda locale in sospeso.',true);
   const button=activateForm.querySelector('button[type=submit]');button.disabled=true;
   try{
     // Reuse physical device ID where present. The backend always advances
     // its generation, revoking a different device without admin approval.
     const deviceId=device?.deviceId||localStorage.getItem('breakapp:physical-device')||crypto.randomUUID();
     localStorage.setItem('breakapp:physical-device',deviceId);
     const {data,error}=await client.rpc('transfer_my_offline_device',{
       p_school:ctx.schoolId,p_device:deviceId
     });
     if(error)throw error;
     if(data?.device_id!==deviceId||!Number.isSafeInteger(Number(data?.generation)))
       throw new Error('Lease server non coerente.');
     const salt=pinSalt();
     const unlocked=await deriveOfflineKey(pin,salt);
     const verifier=await sealOffline(unlocked,verifierText);
     device={
       context:contextKey(),schoolId:ctx.schoolId,deviceId,
       generation:Number(data.generation),expiresAt:data.expires_at,
       salt,verifier
     };
     await saveDevice(db,device);
     localStorage.removeItem('breakapp:offline-start');
     key=unlocked;lastTouch=Date.now();
     activateForm.reset();
     try{await refreshCatalog();}
     catch{info('Dispositivo autorizzato, ma catalogo non sincronizzato. Aggiornalo online.',true);}
     renderLease();
     info('Autorizzazione server attiva. Scadenza massima 8 ore; i dati locali sono cifrati.');
   }catch(err){info(err.message||'Attivazione fallita.',true);}
   finally{button.disabled=false;}
 });
 unlockForm.addEventListener('submit',async event=>{
   event.preventDefault();
     if(Date.now()<Math.max(blockedUntil,device?.pinBlockedUntil||0))return info('Troppi tentativi PIN. Riprova dopo cinque minuti.',true);
   try{
     const next=await deriveOfflineKey($('offline-unlock-pin').value,device.salt);
     const proof=await unsealOffline(next,device.verifier);
     if(proof!==verifierText)throw new Error('PIN errato.');
     key=next;lastTouch=Date.now();pinFailures=0;
     device.pinFailures=0;device.pinBlockedUntil=0;await saveDevice(db,device);
     unlockForm.reset();
     if(device.catalogEncrypted){
      catalog=await unsealOffline(key,device.catalogEncrypted);
      if(catalog?.school_id!==ctx.schoolId)catalog=null;
     }
     if(catalog)renderCatalog();
     if(device.ordersEncrypted){
      manifest=await unsealOffline(key,device.ordersEncrypted);
      if(manifest?.school_id!==ctx.schoolId)manifest=null;
     }
     if(device.cashEncrypted)cashSnapshot=await unsealOffline(key,device.cashEncrypted);
     renderManifest();renderLease();
     info(hasLease()?'Coda sbloccata. Le operazioni restano da verificare sul server.':
       'Coda sbloccata per invio, ma lease scaduto: nessuna nuova operazione offline autorizzata.');
   }catch{
     lock();
     pinFailures=(device?.pinFailures||0)+1;
     if(pinFailures>=5){blockedUntil=Date.now()+5*60*1000;pinFailures=0;}
     if(device){device.pinFailures=pinFailures;device.pinBlockedUntil=blockedUntil;
      try{await saveDevice(db,device);}catch{/* Preserve the in-memory lock if storage fails. */}}
     info('PIN non valido o dati locali non decifrabili.',true);
   }
 });
 $('offline-entry-online').addEventListener('click',async()=>{
  if(!touch()||!navigator.onLine||!hasLease()||!catalog||!saleItems.length)
   return info('Catalogo, PIN, connessione e prodotti validi richiesti.',true);
  const amount=saleSum(),barId=barInput.value;
  if(!Number.isSafeInteger(amount)||amount<=0||amount>1000000)
   return info('Totale non valido.',true);
  if(!confirm('Confermi di avere già incassato '+formatEuro(amount)+
    ' in contanti? Il server registrerà ora la vendita.'))return;
  onlineCashKey ||=crypto.randomUUID();
  const button=$('offline-entry-online');button.disabled=true;
  try{
   const {data,error}=await client.rpc('record_online_bar_cash_sale',{
    p_bar:barId,p_items:saleItems.map(({product_id,quantity})=>({product_id,quantity})),
    p_request_key:onlineCashKey,p_note:$('offline-entry-note').value.trim()
   });
   if(error)throw error;
   if(!data?.sale_id)throw new Error('Ricevuta contabile non disponibile');
   onlineCashKey=null;saleItems=[];renderSale();
   info('Vendita contabilizzata: '+formatEuro(amount)+
    '. Riferimento '+data.sale_id.slice(0,8)+'. Documento fiscale separato.');
   window.dispatchEvent(new Event('breakapp:cash-refresh'));
  }catch(e){info(e.message||'Registrazione non riuscita, controlla la cassa.',true);}
  finally{button.disabled=false;}
 });
 entryForm.addEventListener('submit',async event=>{
   event.preventDefault();
   if(!touch())return info('Coda bloccata: sblocca con PIN.',true);
   if(!hasLease())return info('Il lease è scaduto: riconnettiti e riattiva prima di acquisire altre operazioni.',true);
   try{
     if(!catalog||!saleItems.length||!barInput.value||
       catalog.school_id!==ctx.schoolId||
       catalog.service_date!==new Date().toLocaleDateString('en-CA',{timeZone:'Europe/Rome'}))
       throw new Error('Seleziona prodotti da un catalogo valido per oggi.');
     const amount=saleSum();
     if(!Number.isSafeInteger(amount)||amount<=0||amount>1000000)
       throw new Error('Totale contanti non consentito.');
     const note=$('offline-entry-note').value.trim();
     if(/[<>{}]/.test(note))throw new Error('Caratteri non consentiti nella nota.');
     if(!confirm('Confermi di avere realmente incassato '+formatEuro(amount)+
        ' in contanti? La vendita potrà richiedere riconciliazione.'))return;
     const eventId=crypto.randomUUID();
     const sessionId=currentCashSession(barInput.value);
     if(!sessionId)throw new Error('Apri prima il turno nella sezione Cassa.');
     const eventData={kind:'counter_sale',bar_id:barInput.value,method:'cash',
       cash_session_id:sessionId,
       amount_cents:amount,note,items:saleItems.map(({product_id,quantity,unit_cents})=>({
        product_id,quantity,unit_cents
       })),local_recorded_at:new Date().toISOString(),request_key:eventId};
     await queueLocal(eventData);
     window.dispatchEvent(new CustomEvent('breakapp:cash-recorded',{detail:{sessionId,amount}}));
     saleItems=[];renderSale();entryForm.reset();
     barInput.value=catalog.bars[0]?.id||'';renderCatalog();
     await renderQueue();
     info('Incasso fisico '+formatEuro(amount)+
      ' registrato nella coda locale cifrata; sincronizza appena online.');
   }catch(err){info(err.message||'Operazione locale non salvata.',true);}
 });
 syncButton.addEventListener('click',async()=>{
   if(!touch()||!db||!navigator.onLine||!device)
     return info('Sblocca la coda e riconnettiti prima di inviare.',true);
   const records=await readPending(db,contextKey());
   const identity=await client.auth.getUser();
   if(identity.error||identity.data?.user?.id!==user?.id)return info('Per sincronizzare questa coda accedi online come operatore '+String(user?.id).slice(0,8)+'. I dati restano conservati.',true);
   syncButton.disabled=true;
   let ok=0;let errors=0;
   for(const record of records){
     try{
       const data=await unsealOffline(key,record.encrypted);
       const payload=data.kind==='shift_change'
        ?{bar_id:data.bar_id,session_id:data.session_id,action:data.action,
          amount_cents:data.amount_cents,reason:data.reason}
        :['cash_pickup','group_pickup'].includes(data.kind)
        ?{order_id:data.order_id,pickup_token:data.pickup_token,bar_id:data.bar_id,
          collected_cents:data.collected_cents,snapshot_payment_status:data.snapshot_payment_status,
          ...(data.snapshot_id?{snapshot_id:data.snapshot_id}:{}),...(data.cash_session_id?{cash_session_id:data.cash_session_id}:{})}
        :{bar_id:data.bar_id,method:'cash',amount_cents:data.amount_cents,
          note:data.note,items:data.items,...(data.cash_session_id?{cash_session_id:data.cash_session_id}:{})};
       const {data:receipt,error}=await client.rpc('stage_my_offline_event',{
         p_device:record.deviceId,p_generation:record.generation,
         p_request_key:record.id,p_kind:data.kind,
         p_local_recorded_at:data.local_recorded_at,p_payload:payload
       });
       if(error||!['quarantined','applied','approved'].includes(receipt?.status))
         throw error||new Error('Il server non ha confermato l’evento.');
       if(receipt.status==='approved')throw new Error('Attendi la contabilizzazione della revisione Admin.');
       if(receipt.status==='quarantined'){
        const rpc=data.kind==='group_pickup'?'reconcile_my_offline_group_pickup':data.kind==='shift_change'?'reconcile_my_cash_shift_event':data.kind==='cash_pickup'
         ?'reconcile_my_offline_pickup_event':'reconcile_my_offline_cash_event';
        const {data:reconciled,error:reconcileError}=await client.rpc(rpc,{p_event:receipt.id});
        if(reconcileError)throw reconcileError;
        if(reconciled?.status==='quarantined'){
         throw new Error('Evento in revisione: conserva localmente gli eventi successivi.');
        }
       }
       // Only an applied event may be removed from the protected local queue.
       await deletePending(db,record.id);ok++;
     }catch{errors++;break;}
   }
   await renderQueue();renderLease();
   window.dispatchEvent(new Event('breakapp:cash-refresh'));
   info(ok+' eventi trasferiti al server con ricevuta; '+errors+
     ' ancora locali. Controlla il pannello Admin per eventuali conflitti.',errors>0);
 });
 $('offline-lock').addEventListener('click',()=>{
   lock();renderLease();info('Dispositivo bloccato. Inserisci il PIN per continuare.');
 });
 $('offline-refresh').addEventListener('click',()=>void renderQueue());
 window.addEventListener('breakapp:workspace-context',event=>{
   void selectContext(event.detail);
 });
 client.auth.onAuthStateChange((_e,session)=>queueMicrotask(()=>{
   if(!session){authVersion++;lock();user=null;ctx=null;db=null;device=null;panel.hidden=true;}
 }));
 window.addEventListener('offline',()=>{if(!localStorage.getItem('breakapp:offline-start'))localStorage.setItem('breakapp:offline-start',String(Date.now()));syncButton.disabled=true;info('Connessione assente: operazioni locali cifrate.');});
 window.addEventListener('online',()=>{renderLease();info('Connessione ripristinata: invia la coda per verifica.');});
 setInterval(()=>{
   if(key && Date.now()-lastTouch>=MAX_IDLE_MS){
     lock();renderLease();info('Blocco automatico dopo cinque minuti di inattività.');
   }
 },15000);
 window.addEventListener('pagehide',()=>{lock();});
 const operators=make('select');operators.setAttribute('aria-label','Operatore già configurato su questo dispositivo');
 const switcher=make('button','Cambia operatore offline','button button-outline button-small');switcher.type='button';
 panel.append(make('h3','Tablet condiviso'),operators,switcher);
 switcher.addEventListener('click',async()=>{
  if(!db||navigator.onLine)return info('Il cambio con PIN è disponibile offline per operatori già configurati. Online accedi con il relativo account.',true);
  const selected=(await readConfiguredOperators(db)).find(d=>d.context===operators.value&&d.schoolId===ctx?.schoolId);
  if(!selected)return info('Operatore non configurato su questo dispositivo.',true);
  lock();user={id:selected.context.split(':')[0]};device=selected;renderLease();await renderQueue();
  info('Operatore '+user.id.slice(0,8)+' selezionato: sblocca con il suo PIN. Il limite delle otto ore non riparte.');
 });
 $('offline-refresh').addEventListener('click',async()=>{
  if(!db)return;operators.replaceChildren();
  for(const d of await readConfiguredOperators(db))if(d.schoolId===ctx?.schoolId&&d.deviceId===(device?.deviceId||localStorage.getItem('breakapp:physical-device')))
   operators.add(new Option('Operatore '+d.context.split(':')[0].slice(0,8),d.context));
 });
 return {
  isUnlocked:()=>Boolean(key&&device&&ctx),
  getSnapshot:()=>cashSnapshot,
  async cacheSnapshot(snapshot){
   if(!key||!device||snapshot.school_id!==ctx?.schoolId)return;
   cashSnapshot=snapshot;device.cashEncrypted=await sealOffline(key,snapshot);await saveDevice(db,device);
  },
  queueShift:payload=>queueLocal({...payload,kind:'shift_change'}),
  hasPending:async()=>Boolean(db&&contextKey()&&(await readPending(db,contextKey())).length)
 };
}
