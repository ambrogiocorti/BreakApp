// BreakApp offline vault: encrypted *pending* events, not a cash ledger.
// Keys remain in RAM while unlocked. No customer details in offline payloads.
const STORE='breakapp-offline-v1';
const utf8=new TextEncoder();
const dec=new TextDecoder();
export function validateOfflinePin(pin){
 return /^[0-9]{6,12}$/.test(String(pin||''));
}
export function pinSalt(){
 return Array.from(crypto.getRandomValues(new Uint8Array(16)));
}
export async function deriveOfflineKey(pin,salt){
 if(!validateOfflinePin(pin))throw new Error('Il PIN deve contenere 6–12 cifre.');
 if(!Array.isArray(salt)||salt.length!==16||salt.some(x=>!Number.isInteger(x)||x<0||x>255))
  throw new Error('Configurazione cifratura non valida.');
 const material=await crypto.subtle.importKey('raw',utf8.encode(pin),'PBKDF2',false,['deriveKey']);
 return crypto.subtle.deriveKey({
   name:'PBKDF2',salt:Uint8Array.from(salt),iterations:310000,hash:'SHA-256'
 },material,{name:'AES-GCM',length:256},false,['encrypt','decrypt']);
}
export async function sealOffline(key,object){
 const iv=crypto.getRandomValues(new Uint8Array(12));
 const bytes=utf8.encode(JSON.stringify(object));
 const ciphertext=await crypto.subtle.encrypt({name:'AES-GCM',iv},key,bytes);
 return {iv:Array.from(iv),sealed:Array.from(new Uint8Array(ciphertext))};
}
export async function unsealOffline(key,envelope){
 if(!Array.isArray(envelope?.iv)||envelope.iv.length!==12||
    !Array.isArray(envelope?.sealed)||envelope.sealed.length<16)throw new Error('Coda locale danneggiata.');
 const plain=await crypto.subtle.decrypt({name:'AES-GCM',iv:Uint8Array.from(envelope.iv)},
  key,Uint8Array.from(envelope.sealed));
 return JSON.parse(dec.decode(plain));
}
export async function openOfflineDB(){
 if(typeof indexedDB==='undefined')throw new Error('IndexedDB non disponibile.');
 return new Promise((resolve,reject)=>{
  const request=indexedDB.open(STORE,1);
  request.onupgradeneeded=()=>{
   const db=request.result;
   db.createObjectStore('devices',{keyPath:'context'});
   const events=db.createObjectStore('pending',{keyPath:'id'});
   events.createIndex('context','context',{unique:false});
  };
  request.onsuccess=()=>resolve(request.result);
  request.onerror=()=>reject(request.error);
 });
}
export async function transact(db,storeName,mode,operation){
 return new Promise((resolve,reject)=>{
  const tx=db.transaction(storeName,mode);
  const request=operation(tx.objectStore(storeName));
  let result;
  request.onsuccess=()=>{result=request.result;};
  request.onerror=()=>reject(request.error);
  tx.oncomplete=()=>resolve(result);
  tx.onerror=()=>reject(tx.error);
  tx.onabort=()=>reject(tx.error||new Error('Transazione locale annullata.'));
 });
}
export const readDevice=(db,context)=>transact(db,'devices','readonly',s=>s.get(context));
export const saveDevice=(db,entry)=>transact(db,'devices','readwrite',s=>s.put(entry));
export const savePending=(db,entry)=>transact(db,'pending','readwrite',s=>s.put(entry));
export const deletePending=(db,id)=>transact(db,'pending','readwrite',s=>s.delete(id));
export const readPending=(db,context)=>transact(db,'pending','readonly',s=>s.index('context').getAll(context));
