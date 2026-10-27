export function initializeGuestAccess(client){
 if(!client)return;
 const make=(tag,text='')=>{const n=document.createElement(tag);n.textContent=text;return n;};
 const form=make('form'),heading=make('h3','Continua come ospite'),school=make('select'),name=make('input'),klass=make('input'),status=make('p');
 school.setAttribute('aria-label','Scuola dell’ospite');name.placeholder='Nome e cognome';name.setAttribute('aria-label','Nome e cognome');name.required=true;name.maxLength=100;
 klass.placeholder='Classe (facoltativa)';klass.setAttribute('aria-label','Classe facoltativa');klass.maxLength=80;
 const submit=make('button','Accedi come ospite');submit.className='button button-outline';submit.type='submit';status.setAttribute('role','status');
 form.append(heading,school,name,klass,make('p','Conserva il link privato per ritrovare ordini e pagamenti. Come ospite puoi partecipare a gruppi, ma non coordinarli.'),submit,status);
 document.getElementById('signed-out-view').append(form);
 const recovery=make('div'),link=make('input');link.readOnly=true;link.setAttribute('aria-label','Link privato personale');
 const copy=make('button','Copia link privato');copy.type='button';copy.className='button button-outline button-small';recovery.hidden=true;recovery.append(make('p','Questo link dà accesso al tuo profilo ospite. Conservalo in un luogo privato.'),link,copy);
 document.getElementById('signed-in-view').append(recovery);copy.addEventListener('click',()=>void navigator.clipboard.writeText(link.value));
 const emailForm=make('form'),email=make('input'),emailButton=make('button','Aggiungi email verificata per recuperare l’accesso'),emailStatus=make('p');
 email.type='email';email.required=true;email.setAttribute('aria-label','Email di recupero dell’ospite');emailForm.hidden=true;emailButton.className='button button-outline button-small';emailForm.append(email,emailButton,emailStatus);document.getElementById('signed-in-view').append(emailForm);
 emailForm.addEventListener('submit',async e=>{e.preventDefault();emailButton.disabled=true;
  const r=await client.auth.updateUser({email:email.value.trim()},{emailRedirectTo:new URL(import.meta.env.BASE_URL,location.origin).href});
  emailStatus.textContent=r.error?r.error.message:'Conferma il nuovo indirizzo tramite l’email ricevuta.';emailButton.disabled=false;});
 const recover=make('form'),recoverEmail=make('input'),recoverButton=make('button','Ricevi il link di accesso via email'),recoverStatus=make('p');recoverEmail.type='email';recoverEmail.required=true;recoverEmail.setAttribute('aria-label','Email già verificata per recuperare l’accesso');recoverButton.className='button button-outline button-small';recover.append(make('h3','Recupera un accesso con email verificata'),recoverEmail,recoverButton,recoverStatus);document.getElementById('signed-out-view').append(recover);
 recover.addEventListener('submit',async e=>{e.preventDefault();recoverButton.disabled=true;await client.auth.signInWithOtp({email:recoverEmail.value.trim(),options:{shouldCreateUser:false,emailRedirectTo:new URL(import.meta.env.BASE_URL,location.origin).href}});recoverStatus.textContent='Se l’indirizzo è associato a un accesso verificato riceverai un link. Controlla anche lo spam.';recoverButton.disabled=false;});
 async function login(body){
  const {data,error}=await client.functions.invoke('guest-access',{body});if(error||data?.error)throw new Error(data?.error||error.message||'Accesso non disponibile');
  const session=await client.auth.setSession({access_token:data.access_token,refresh_token:data.refresh_token});if(session.error)throw session.error;
  if(data.private_token){const url=new URL(location.href);url.hash='guest='+data.private_token;link.value=url.href;recovery.hidden=false;}
 }
 form.addEventListener('submit',async e=>{e.preventDefault();submit.disabled=true;
  try{await login({action:'create',name:name.value.trim(),school_id:school.value,class_name:klass.value.trim()});status.textContent='Accesso ospite creato. Conserva il link privato.';}
  catch(error){status.textContent=error.message;}finally{submit.disabled=false;}});
 client.from('schools').select('id,name').eq('is_active',true).order('name').then(({data,error})=>{if(!error)for(const s of data||[])school.add(new Option(s.name,s.id));});
 const token=location.hash.startsWith('#guest=')?location.hash.slice(7):null;
 if(token){history.replaceState(null,'',location.pathname+location.search+'#accesso');void login({action:'resume',token}).catch(error=>{status.textContent=error.message;});}
 client.auth.onAuthStateChange((_event,session)=>{emailForm.hidden=!session?.user?.app_metadata?.guest;if(!session){recovery.hidden=true;link.value='';}});
}
