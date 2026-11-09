// The server enforces the same accuracy limit (set per school by its Admin,
// 100 m by default) and the school's radius.
// Keep listening briefly: the first position from a phone is often approximate.
// Each error carries a `code` so the interface can explain what to do; the
// checks themselves are unchanged and the server still decides.
const geoError=(message,code,extra={})=>Object.assign(new Error(message),{code,...extra});
export const DEFAULT_ACCURACY_M=100;
/** A school's accuracy tolerance in metres (10–1000), else the 100 m default. */
export function accuracyLimit(value){
  const n=Number(value);
  return value!=null&&Number.isInteger(n)&&n>=10&&n<=1000?n:DEFAULT_ACCURACY_M;
}
/** Reads the school's tolerance; any failure falls back to the default. */
export async function schoolAccuracyLimit(client,schoolId){
  if(!client||!schoolId)return DEFAULT_ACCURACY_M;
  try{
    const {data,error}=await client.from('schools').select('location_accuracy_m').eq('id',schoolId).maybeSingle();
    return error?DEFAULT_ACCURACY_M:accuracyLimit(data?.location_accuracy_m);
  }catch{return DEFAULT_ACCURACY_M;}
}
/** Fail closed if the school's policy cannot be read. Only the server decides. */
export async function schoolRequiresGeolocation(client,schoolId){
  if(!client||!schoolId)return true;
  try{
    const {data,error}=await client.from('schools').select('require_geolocation').eq('id',schoolId).maybeSingle();
    return error||typeof data?.require_geolocation!=='boolean'?true:data.require_geolocation;
  }catch{return true;}
}
export function accuratePosition({
  geolocation=globalThis.navigator?.geolocation,
  timeoutMs=20000,
  maxAccuracy=DEFAULT_ACCURACY_M,
  onProgress=()=>{},
  signal
}={}) {
  return new Promise((resolve,reject)=>{
    if(!geolocation?.watchPosition){
      reject(geoError('La posizione non è disponibile su questo dispositivo o browser.','unsupported'));
      return;
    }
    let watchId=null,settled=false,bestAccuracy=Infinity,lastError=null,invalidClock=false,stalePosition=false;
    let timer;
    const abort=()=>finish(new DOMException('Richiesta annullata.','AbortError'));
    const finish=(error,position)=>{
      if(settled)return;
      settled=true;
      clearTimeout(timer);
      signal?.removeEventListener('abort',abort);
      if(watchId!==null)geolocation.clearWatch(watchId);
      if(error)reject(error);else resolve(position);
    };
    const timeout=()=>{
      if(Number.isFinite(bestAccuracy)){
        finish(geoError('Posizione ancora imprecisa (circa ±'+Math.ceil(bestAccuracy)+' m). Serve una precisione entro '+maxAccuracy+' m: attiva la posizione precisa e riprova vicino a una finestra o all’aperto.','accuracy',{accuracy:Math.ceil(bestAccuracy)}));
      }else if(invalidClock){
        finish(geoError('La posizione riporta un orario non valido. Controlla data e ora automatiche del dispositivo oppure riprova con un altro browser.','clock'));
      }else if(stalePosition){
        finish(geoError('La posizione ricevuta non è recente. Attiva la localizzazione e riprova.','stale'));
      }else if(lastError?.code===2){
        finish(geoError('Non riusciamo a rilevare la posizione. Attiva i servizi di localizzazione e riprova vicino a una finestra o all’aperto.','unavailable'));
      }else{
        finish(geoError('La posizione non è arrivata in tempo. Controlla la localizzazione del dispositivo e riprova vicino a una finestra o all’aperto.','timeout'));
      }
    };
    if(signal?.aborted){abort();return;}
    signal?.addEventListener('abort',abort,{once:true});
    timer=setTimeout(timeout,timeoutMs);
    try{
      watchId=geolocation.watchPosition(position=>{
        if(settled)return;
        const {latitude,longitude,accuracy}=position.coords||{};
        const observed=Number(position.timestamp);
        const age=Date.now()-observed;
        if(!Number.isFinite(latitude)||latitude < -90||latitude > 90||
          !Number.isFinite(longitude)||longitude < -180||longitude > 180||
          !Number.isFinite(accuracy)||accuracy < 0)return;
        if(!Number.isFinite(observed)||age < -10000){invalidClock=true;return;}
        if(age > 110000){stalePosition=true;return;}
        bestAccuracy=Math.min(bestAccuracy,accuracy);
        if(accuracy<=maxAccuracy){finish(null,position);return;}
        onProgress(Math.ceil(bestAccuracy));
      },error=>{
        if(settled)return;
        lastError=error;
        if(error.code===1)finish(geoError('Per confermare, consenti la posizione nelle impostazioni del browser e del dispositivo.','permission'));
      },{enableHighAccuracy:true,maximumAge:0,timeout:timeoutMs});
      // A test double may invoke its callback synchronously; never leak its watch.
      if(settled&&watchId!==null)geolocation.clearWatch(watchId);
    }catch{
      finish(geoError('Impossibile avviare la localizzazione. Controlla le impostazioni del browser e riprova.','unsupported'));
    }
  });
}
