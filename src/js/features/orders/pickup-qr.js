import { makePickupQrValue, parsePickupQrValue, parseOrderDisplayNumber } from './qr-utils.js';

const el=(tag,text,cls='')=>{
  const node=document.createElement(tag);
  node.textContent=text;node.className=cls;return node;
};
export function initializePickupQr(client) {
  if(!client)return;
  const ticket=document.querySelector('#customer-qr-dialog');
  const ticketCode=document.querySelector('#customer-qr-code');
  const ticketMeta=document.querySelector('#customer-qr-meta');
  const scanDialog=document.querySelector('#staff-scan-dialog');
  const cameraBtn=document.querySelector('#staff-start-camera');
  const video=document.querySelector('#staff-camera-video');
  const manual=document.querySelector('#staff-number-form');
  const manualInput=document.querySelector('#staff-number-input');
  const status=document.querySelector('#staff-scan-status');
  const result=document.querySelector('#staff-scan-result');
  let stream=null,frameId=null,active=false,inFlight=false;
  let queryVersion=0,currentUser=null;

  function report(message,error=false) {
    status.textContent=message;status.dataset.type=error?'error':'information';
  }
  window.addEventListener('breakapp:pickup-ticket',event=>{
    if(!currentUser)return;
    const {pickupToken,displayNo}=event.detail||{};
    ticketCode.replaceChildren();
    try{
      const value=makePickupQrValue(pickupToken);
      if(typeof window.QRCode!=='function')throw new Error('Generatore QR non disponibile.');
      new window.QRCode(ticketCode,{
        text:value,width:225,height:225,colorDark:'#080f21',colorLight:'#ffffff',
        correctLevel:window.QRCode.CorrectLevel.M
      });
      ticketMeta.textContent='Ordine #'+displayNo;
      ticket.showModal();
    }catch(err){
      ticketMeta.textContent='Impossibile generare il QR: '+err.message
        +'. Puoi comunicare al barista il numero ordine #'+displayNo+'.';
      ticket.showModal();
    }
  });

  function stopCamera(){
    active=false;
    if(frameId!==null){cancelAnimationFrame(frameId);frameId=null;}
    if(stream){stream.getTracks().forEach(track=>track.stop());stream=null;}
    video.pause();video.srcObject=null;video.hidden=true;inFlight=false;
    cameraBtn.disabled=false;cameraBtn.textContent='Apri fotocamera';
  }
  scanDialog.addEventListener('close',()=>{
    stopCamera();queryVersion+=1;
    window.dispatchEvent(new CustomEvent('breakapp:counter-scan-closed'));
  });

  async function allowedStaff(schoolId) {
    if(!currentUser)return false;
    const [memberships,assurance]=await Promise.all([
      client.from('school_memberships')
        .select('school_id,role_assignments(role_code)')
        .eq('user_id',currentUser.id).eq('membership_status','active'),
      client.auth.mfa.getAuthenticatorAssuranceLevel()
    ]);
    if(memberships.error)return false;
    const aal2=!assurance.error && assurance.data.currentLevel==='aal2';
    return (memberships.data||[]).some(m=>m.school_id===schoolId&&
      (m.role_assignments||[]).some(r=>r.role_code==='bartender'
        ||(r.role_code==='school_admin'&&aal2)));
  }
  // Il cliente mostra il QR: l'ordine compare qui con gli stessi pulsanti del
  // banco (un tocco per incassare e consegnare). Dopo il tocco la fotocamera
  // torna a leggere da sola per il cliente successivo.
  let lastToken='',lastTokenAt=0;
  async function lookup(filter) {
    const version=++queryVersion;
    result.replaceChildren();report('Cerco l’ordine…');
    try{
      let q=client.from('orders').select('id,school_id,display_no');
      q=filter.token?q.eq('pickup_token',filter.token):q.eq('display_no',filter.displayNo);
      const {data,error}=await q.maybeSingle();
      if(version!==queryVersion || !scanDialog.open)return;
      if(error)throw error;
      if(!data)throw new Error('Ordine non trovato.');
      if(!await allowedStaff(data.school_id))throw new Error('Questo ordine è di un’altra scuola.');
      if(version!==queryVersion || !scanDialog.open)return;
      report('Ordine #'+data.display_no);
      inFlight=true;
      window.dispatchEvent(new CustomEvent('breakapp:counter-scan',{detail:{orderId:data.id,container:result,done:resume}}));
    }catch(err){if(version===queryVersion){report(err.message||'Ricerca non riuscita.',true);resume();}}
  }
  // Dopo il tocco (o l'annullamento) si torna a leggere i QR.
  function resume(){
    inFlight=false;
    if(active&&scanDialog.open&&frameId===null)frameId=requestAnimationFrame(()=>void readLoop?.());
  }
  let readLoop=null;

  async function startCamera(){
    if(active||inFlight)return;
    cameraBtn.disabled=true;
    report('Verifica disponibilità scanner QR…');
    try{
      if(!('BarcodeDetector' in window) || !navigator.mediaDevices?.getUserMedia)
        throw new Error('Scanner fotografico non disponibile in questo browser. Usa la ricerca per numero.');
      const available=await window.BarcodeDetector.getSupportedFormats();
      if(!available.includes('qr_code'))
        throw new Error('Il browser non supporta la lettura QR. Usa il numero ordine.');
      const detector=new window.BarcodeDetector({formats:['qr_code']});
      stream=await navigator.mediaDevices.getUserMedia({
        video:{facingMode:{ideal:'environment'}},audio:false
      });
      video.srcObject=stream;video.hidden=false;
      await video.play();
      active=true;cameraBtn.textContent='Fotocamera attiva';
      report('Inquadra il QR personale del cliente.');
      const read=async()=>{
        frameId=null;
        if(!active||inFlight||!scanDialog.open)return;
        try{
          const codes=await detector.detect(video);
          if(!active||!scanDialog.open)return;
          for(const code of codes){
            const groupMatch=/^breakapp:group:([0-9a-f-]{36})$/i.exec(String(code.rawValue));
            if(groupMatch){
              stopCamera();scanDialog.close();
              window.dispatchEvent(new CustomEvent('breakapp:group-pickup-scanned',{
                detail:{token:groupMatch[1]}
              }));
              return;
            }
            const token=parsePickupQrValue(code.rawValue);
            // Lo stesso QR ancora inquadrato non riapre l'ordine appena gestito.
            if(token&&(token!==lastToken||Date.now()-lastTokenAt>8000)){
              lastToken=token;lastTokenAt=Date.now();
              await lookup({token});
              return;
            }
          }
        }catch(err){report('Lettura non riuscita. Riprova oppure cerca il numero ordine.',true);}
        if(active&&!inFlight)frameId=requestAnimationFrame(()=>void read());
      };
      readLoop=read;
      frameId=requestAnimationFrame(()=>void read());
    }catch(err){
      stopCamera();
      report(err.message||'Non è stato possibile aprire la fotocamera.',true);
    }finally{cameraBtn.disabled=false;}
  }
  window.addEventListener('breakapp:workspace-context',()=>{
    // Role/school switches invalidate a visible scanner and release its camera.
    if(scanDialog.open)scanDialog.close();
    stopCamera();
  });
  cameraBtn.addEventListener('click',()=>void startCamera());
  manual.addEventListener('submit',event=>{
    event.preventDefault();
    const displayNo=parseOrderDisplayNumber(manualInput.value);
    if(!displayNo)return report('Inserisci un numero d’ordine valido.',true);
    void lookup({displayNo});
  });
  document.querySelector('#staff-scan-open').addEventListener('click',()=>{
    if(!currentUser)return;
    result.replaceChildren();
    manual.reset();
    scanDialog.showModal();
    // La fotocamera parte subito: niente tocco in piu'. Senza scanner si usa il numero.
    if('BarcodeDetector' in window&&navigator.mediaDevices?.getUserMedia){report('Inquadra il QR del cliente.');void startCamera();}
    else{report('Scrivi il numero dell’ordine.');manualInput.focus();}
  });
  client.auth.onAuthStateChange((_event,session)=>queueMicrotask(()=>{
    currentUser=session?.user||null;
    if(!currentUser){stopCamera();if(scanDialog.open)scanDialog.close();if(ticket.open)ticket.close();}
  }));
  client.auth.getUser().then(({data,error})=>{
    if(!error)currentUser=data?.user||null;
  });
}
