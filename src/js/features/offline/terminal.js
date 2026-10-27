import {formatEuro} from '../catalog/utils.js';
import {validateOfflinePin,pinSalt,deriveOfflineKey,sealOffline,unsealOffline,
 openOfflineDB,readDevice,saveDevice,savePending,deletePending,readPending} from './vault.js';

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
  catalog=null,saleItems=[];
 const info=(text,error=false)=>{status.textContent=text;status.dataset.type=error?'error':'information';};
 const lock=()=>{
  key=null;lastTouch=0;catalog=null;saleItems=[];
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
   &&device.schoolId===ctx?.schoolId);
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
    saleItems=saleItems.filter(x=>x.product_id!==item.product_id);renderSale();
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
   saleItems=[];renderSale();
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
  renderSale();info('Riga aggiunta. La vendita viene salvata solo dopo conferma.');
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
  syncButton.disabled=!key||!navigator.onLine;
  $('offline-lock').disabled=!key;
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
   if(panel.hidden)return;
   info('Verifica autenticazione e dispositivo…');
   try{
     const {data,error}=await client.auth.getUser();
     if(id!==authVersion)return;
     if(error||!data?.user)throw new Error('Autenticazione online necessaria per inizializzare il dispositivo.');
     user=data.user;db=await openOfflineDB();
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
     const deviceId=device?.deviceId||crypto.randomUUID();
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
   if(Date.now()<blockedUntil)return info('Troppi tentativi PIN. Riprova dopo il blocco temporaneo.',true);
   try{
     const next=await deriveOfflineKey($('offline-unlock-pin').value,device.salt);
     const proof=await unsealOffline(next,device.verifier);
     if(proof!==verifierText)throw new Error('PIN errato.');
     key=next;lastTouch=Date.now();pinFailures=0;
     unlockForm.reset();
     if(device.catalogEncrypted){
      catalog=await unsealOffline(key,device.catalogEncrypted);
      if(catalog?.school_id!==ctx.schoolId)catalog=null;
     }
     if(catalog)renderCatalog();
     renderLease();
     info(hasLease()?'Coda sbloccata. Le operazioni restano da verificare sul server.':
       'Coda sbloccata per invio, ma lease scaduto: nessuna nuova operazione offline autorizzata.');
   }catch{
     pinFailures++;
     if(pinFailures>=5){blockedUntil=Date.now()+5*60*1000;pinFailures=0;}
     info('PIN non valido o dati locali non decifrabili.',true);
   }
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
     const eventData={kind:'counter_sale',bar_id:barInput.value,method:'cash',
       amount_cents:amount,note,items:saleItems.map(({product_id,quantity,unit_cents})=>({
        product_id,quantity,unit_cents
       })),local_recorded_at:new Date().toISOString(),request_key:eventId};
     const encrypted=await sealOffline(key,eventData);
     await savePending(db,{id:eventId,context:contextKey(),
       createdAt:eventData.local_recorded_at,encrypted,
       deviceId:device.deviceId,generation:device.generation});
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
   syncButton.disabled=true;
   let ok=0;let errors=0;
   for(const record of records){
     try{
       const data=await unsealOffline(key,record.encrypted);
       const {data:receipt,error}=await client.rpc('stage_my_offline_event',{
         p_device:record.deviceId,p_generation:record.generation,
         p_request_key:record.id,p_kind:data.kind,
         p_local_recorded_at:data.local_recorded_at,
         p_payload:{bar_id:data.bar_id,method:'cash',amount_cents:data.amount_cents,
          note:data.note,items:data.items}
       });
       if(error||!['quarantined','applied','approved'].includes(receipt?.status))
         throw error||new Error('Il server non ha confermato l’evento.');
       if(receipt.status==='quarantined'&&Array.isArray(data.items)){
        const {error:reconcileError}=await client.rpc('reconcile_my_offline_cash_event',{
         p_event:receipt.id
        });
        if(reconcileError)throw reconcileError;
       }
       // Durable server receipt is the authority, even for queued Admin review.
       await deletePending(db,record.id);ok++;
     }catch{errors++;}
   }
   await renderQueue();renderLease();
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
 window.addEventListener('offline',()=>{syncButton.disabled=true;info('Connessione assente: solo bozze locali cifrate.');});
 window.addEventListener('online',()=>{renderLease();info('Connessione ripristinata: invia la coda per verifica.');});
 const interval=setInterval(()=>{
   if(key && Date.now()-lastTouch>=MAX_IDLE_MS){
     lock();renderLease();info('Blocco automatico dopo cinque minuti di inattività.');
   }
 },15000);
 window.addEventListener('pagehide',()=>{lock();});
}
