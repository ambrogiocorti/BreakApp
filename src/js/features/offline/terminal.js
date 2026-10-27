import {parseEuroToCents,formatEuro} from '../catalog/utils.js';
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
  authVersion=0,pinFailures=0,blockedUntil=0;
 const info=(text,error=false)=>{status.textContent=text;status.dataset.type=error?'error':'information';};
 const lock=()=>{
  key=null;lastTouch=0;
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
   const id=++authVersion;lock();ctx=next;db=null;device=null;user=null;
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
     unlockForm.reset();renderLease();
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
     const amount=parseEuroToCents($('offline-entry-amount').value);
     if(!Number.isSafeInteger(amount)||amount<=0||amount>100000)
       throw new Error('Importo dichiarato non valido (massimo 1.000 €).');
     const note=$('offline-entry-note').value.trim();
     if(/[<>{}]/.test(note))throw new Error('Caratteri non consentiti nella nota.');
     const eventId=crypto.randomUUID();
     const eventData={kind:'counter_sale',amount_cents:amount,note,
       local_recorded_at:new Date().toISOString(),request_key:eventId};
     const encrypted=await sealOffline(key,eventData);
     await savePending(db,{id:eventId,context:contextKey(),
       createdAt:eventData.local_recorded_at,encrypted,
       deviceId:device.deviceId,generation:device.generation});
     entryForm.reset();
     await renderQueue();
     info('Bozza di '+formatEuro(amount)+' salvata e cifrata. NON è un incasso registrato.');
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
         p_payload:{amount_cents:data.amount_cents,note:data.note}
       });
       if(error||receipt?.status!=='quarantined')
         throw error||new Error('Il server non ha confermato la quarantena.');
       // Delete only after a durable server-side quarantine acknowledgement.
       await deletePending(db,record.id);ok++;
     }catch{errors++;}
   }
   await renderQueue();renderLease();
   info(ok+' inviate in quarantena server; '+errors+
     ' ancora in coda. Nessun incasso o scarico scorte applicato.',errors>0);
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
