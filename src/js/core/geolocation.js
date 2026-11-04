// The server enforces the same 100 m accuracy limit and the school's radius.
// Keep listening briefly: the first position from a phone is often approximate.
export function accuratePosition({
  geolocation=globalThis.navigator?.geolocation,
  timeoutMs=20000,
  maxAccuracy=100,
  onProgress=()=>{},
  signal
}={}) {
  return new Promise((resolve,reject)=>{
    if(!geolocation?.watchPosition){
      reject(new Error('La posizione non è disponibile su questo dispositivo o browser.'));
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
        finish(new Error('Posizione ancora imprecisa (circa ±'+Math.ceil(bestAccuracy)+' m). Serve una precisione entro 100 m: attiva la posizione precisa e riprova vicino a una finestra o all’aperto.'));
      }else if(invalidClock){
        finish(new Error('La posizione riporta un orario non valido. Controlla data e ora automatiche del dispositivo oppure riprova con un altro browser.'));
      }else if(stalePosition){
        finish(new Error('La posizione ricevuta non è recente. Attiva la localizzazione e riprova.'));
      }else if(lastError?.code===2){
        finish(new Error('Non riusciamo a rilevare la posizione. Attiva i servizi di localizzazione e riprova vicino a una finestra o all’aperto.'));
      }else{
        finish(new Error('La posizione non è arrivata in tempo. Controlla la localizzazione del dispositivo e riprova vicino a una finestra o all’aperto.'));
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
        if(error.code===1)finish(new Error('Per confermare, consenti la posizione nelle impostazioni del browser e del dispositivo.'));
      },{enableHighAccuracy:true,maximumAge:0,timeout:timeoutMs});
      // A test double may invoke its callback synchronously; never leak its watch.
      if(settled&&watchId!==null)geolocation.clearWatch(watchId);
    }catch{
      finish(new Error('Impossibile avviare la localizzazione. Controlla le impostazioni del browser e riprova.'));
    }
  });
}
