export function initializeGuestAccess(client){
 if(!client)return;
 const make=(tag,text='')=>{const n=document.createElement(tag);n.textContent=text;return n;};
 const label=(text,field)=>{const wrapper=make('label',text);wrapper.append(field);return wrapper;};
 const form=make('form'),heading=make('h4','Continua come ospite'),school=make('select'),name=make('input'),klass=make('input'),status=make('p');form.className='guest-access-form';
 const classLabel=label('Classe (facoltativa)',klass);
 school.setAttribute('aria-label','Scuola dell’ospite');name.placeholder='Nome e cognome';name.setAttribute('aria-label','Nome e cognome');name.required=true;name.maxLength=100;
 school.required=true;
 klass.placeholder='Classe (facoltativa)';klass.setAttribute('aria-label','Classe facoltativa');klass.maxLength=80;
 const classList=make('datalist');classList.id='guest-class-options';klass.setAttribute('list',classList.id);form.append(classList);let schoolRows=[];
 let activeIdentity=null,identityGeneration=0;
 async function updateClasses(){
  const selected=schoolRows.find(s=>s.id===school.value);klass.required=Boolean(selected?.require_guest_class);klass.placeholder=klass.required?'Classe della scuola':'Classe (facoltativa)';klass.setAttribute('aria-label',klass.placeholder);classLabel.firstChild.textContent=klass.placeholder;
  const selectedId=school.value,r=await client.from('school_classes').select('name').eq('school_id',selectedId).eq('active',true).order('name');if(school.value!==selectedId)return;classList.replaceChildren();
  for(const c of r.data||[])classList.append(new Option(c.name,c.name));
 }
 school.addEventListener('change',()=>void updateClasses());
 const submit=make('button','Accedi come ospite');submit.className='button button-outline';submit.type='submit';status.setAttribute('role','status');
 form.append(heading,label('Scuola',school),label('Nome e cognome',name),classLabel,make('p','Conserva il link privato per ritrovare ordini e pagamenti. Come ospite puoi partecipare a gruppi, ma non coordinarli.'),submit,status);
 document.getElementById('signed-out-view').append(form);
 const recovery=make('div'),link=make('input');recovery.className='guest-private-link';link.readOnly=true;link.setAttribute('aria-label','Link privato personale');
 const copy=make('button','Copia link privato');copy.type='button';copy.className='button button-outline button-small';recovery.hidden=true;recovery.append(make('p','Questo link dà accesso al tuo profilo ospite. Conservalo in un luogo privato.'),link,copy);
 document.getElementById('signed-in-view').append(recovery);copy.addEventListener('click',async()=>{try{await navigator.clipboard.writeText(link.value);copy.textContent='Link copiato';}catch{link.select();copy.textContent='Copia il link selezionato';}});
 const emailForm=make('form'),email=make('input'),emailButton=make('button','Verifica email di recupero'),emailStatus=make('p');emailForm.className='guest-recovery-form';
 email.type='email';email.required=true;email.setAttribute('aria-label','Email di recupero dell’ospite');emailForm.hidden=true;emailButton.className='button button-outline button-small';emailForm.append(email,emailButton,emailStatus);document.getElementById('signed-in-view').append(emailForm);
 emailStatus.setAttribute('role','status');
 const removeEmail=make('button','Rimuovi collegamento email');removeEmail.type='button';removeEmail.className='button button-outline button-small';removeEmail.hidden=true;emailForm.append(removeEmail);
 removeEmail.addEventListener('click',async()=>{removeEmail.disabled=true;const r=await client.rpc('remove_my_guest_email_recovery');emailStatus.textContent=r.error?r.error.message:'Collegamento rimosso. Conserva il tuo link privato per rientrare.';if(!r.error)removeEmail.hidden=true;removeEmail.disabled=false;});
 emailForm.addEventListener('submit',async e=>{e.preventDefault();emailButton.disabled=true;
  try{
   const {data,error}=await client.functions.invoke('guest-access',{body:{action:'prepare_recovery',email:email.value.trim()}});
   if(error||data?.error)throw new Error(data?.error||error.message);
   const sent=await client.auth.signInWithOtp({email:email.value.trim(),options:{shouldCreateUser:true,emailRedirectTo:new URL(import.meta.env.BASE_URL,location.origin).href}});
   if(sent.error)throw sent.error;
   emailStatus.textContent='Apri il link ricevuto, poi scegli «Verifica o recupera accesso ospite» e conferma il tuo profilo. La verifica scade dopo un’ora.';
  }catch(error){emailStatus.textContent='Verifica non completata: '+error.message;}finally{emailButton.disabled=false;}});
 const recover=make('form'),recoverEmail=make('input'),recoverButton=make('button','Ricevi il link di accesso via email'),recoverStatus=make('p');recover.className='guest-recovery-form';recoverEmail.type='email';recoverEmail.required=true;recoverEmail.setAttribute('aria-label','Email già verificata per recuperare l’accesso');recoverButton.className='button button-outline button-small';recover.append(make('h4','Recupera un accesso con email verificata'),label('Email verificata',recoverEmail),recoverButton,recoverStatus);document.getElementById('signed-out-view').append(recover);
 recover.addEventListener('submit',async e=>{e.preventDefault();recoverButton.disabled=true;await client.auth.signInWithOtp({email:recoverEmail.value.trim(),options:{shouldCreateUser:false,emailRedirectTo:new URL(import.meta.env.BASE_URL,location.origin).href}});recoverStatus.textContent='Se l’indirizzo è associato a un accesso verificato riceverai un link. Dopo l’accesso scegli «Verifica o recupera accesso ospite». Controlla anche lo spam.';recoverButton.disabled=false;});
 const chooser=make('details'),summary=make('summary','Recupero ospite con email verificata'),find=make('button','Verifica o recupera accesso ospite'),choices=make('div'),choiceStatus=make('p');
 chooser.className='guest-recovery-form';chooser.hidden=true;find.type='button';find.className='button button-outline button-small';choiceStatus.setAttribute('role','status');chooser.append(summary,find,choices,choiceStatus);document.getElementById('signed-in-view').append(chooser);
 find.addEventListener('click',async()=>{
  find.disabled=true;choices.replaceChildren();choiceStatus.textContent='Verifica della tua email…';
  try{
   const {data,error}=await client.functions.invoke('guest-access',{body:{action:'list_recovery'}});if(error||data?.error)throw new Error(data?.error||error.message);
   for(const entry of data.pending||[])addChoice('Conferma collegamento: '+entry.name+' · '+entry.school,{action:'confirm_recovery',request_id:entry.id});
   for(const entry of data.linked||[])addChoice('Riprendi ospite: '+entry.name+' · '+entry.school,{action:'recover_verified'});
   choiceStatus.textContent=choices.childElementCount?'Seleziona soltanto il tuo profilo ospite.':'Nessun profilo ospite o richiesta attiva collegato a questa email.';
  }catch(error){choiceStatus.textContent=error.message;}finally{find.disabled=false;}
 });
 function addChoice(text,body){const b=make('button',text);b.type='button';b.className='button button-outline button-small';
  b.addEventListener('click',async()=>{b.disabled=true;try{await login(body);choices.replaceChildren();emailStatus.textContent='Email verificata collegata. Conserva il nuovo link privato: quello precedente non è più valido.';choiceStatus.textContent='Accesso ospite ripristinato. Conserva il nuovo link privato.';}catch(error){choiceStatus.textContent=error.message;}finally{b.disabled=false;}});choices.append(b);}
 async function login(body){
  const {data,error}=await client.functions.invoke('guest-access',{body});if(error||data?.error)throw new Error(data?.error||error.message||'Accesso non disponibile');
  const session=await client.auth.setSession({access_token:data.access_token,refresh_token:data.refresh_token});if(session.error)throw session.error;
  if(data.private_token){const url=new URL(location.href);url.hash='guest='+data.private_token;link.value=url.href;recovery.hidden=false;}
 }
 form.addEventListener('submit',async e=>{e.preventDefault();submit.disabled=true;
  try{await login({action:'create',name:name.value.trim(),school_id:school.value,class_name:klass.value.trim()});status.textContent='Accesso ospite creato. Conserva il link privato.';}
  catch(error){status.textContent=error.message;}finally{submit.disabled=false;}});
 client.from('schools').select('id,name,require_guest_class').eq('is_active',true).order('name').then(({data,error})=>{if(!error){schoolRows=data||[];for(const s of schoolRows)school.add(new Option(s.name,s.id));if(schoolRows.length)void updateClasses();}});
 const token=location.hash.startsWith('#guest=')?location.hash.slice(7):null;
 if(token){history.replaceState(null,'',location.pathname+location.search+'#accesso');void login({action:'resume',token}).catch(error=>{status.textContent=error.message;});}
 client.auth.onAuthStateChange((_event,session)=>{emailForm.hidden=!session?.user?.app_metadata?.guest;chooser.hidden=!session||!session.user.email_confirmed_at||!session.user.email||session.user.email.endsWith('@guest.breakapp.invalid');
  const userId=session?.user?.id||null,version=++identityGeneration;
  if(userId!==activeIdentity){activeIdentity=userId;recovery.hidden=true;link.value='';email.value='';emailStatus.textContent='';choices.replaceChildren();choiceStatus.textContent='';removeEmail.hidden=true;}
  if(session?.user?.app_metadata?.guest)queueMicrotask(()=>{void client.rpc('my_guest_email_recovery_status').then(({data,error})=>{if(version===identityGeneration&&!emailForm.hidden&&!error){removeEmail.hidden=!data;if(data&&!emailStatus.textContent)emailStatus.textContent='Email di recupero verificata collegata.';}});});
  if(!userId){name.value='';klass.value='';recoverEmail.value='';recoverStatus.textContent='';}});
}
