import {confirmDialog} from '../../core/dialog.js';
import {membershipLabel} from '../../core/status-labels.js';

// Personale di una scuola: chi è già in servizio e chi è stato aggiunto ma
// non ha ancora fatto il primo accesso. Le autorizzazioni sono tutte sul
// server (list_school_staff, invite_school_staff, update/remove invite):
// l'Admin scuola gestisce baristi e magazzinieri, il Super Admin anche gli
// Admin scuola. Usato dal pannello dell'Admin e dalla Configurazione.
export const STAFF_ROLE_LABELS={school_admin:'Admin scuola',bartender:'Barista',warehouse_manager:'Magazziniere'};
export const roleLabel=role=>STAFF_ROLE_LABELS[role]||'Ruolo da verificare';
export const staffRoleOptions=platform=>Object.entries(STAFF_ROLE_LABELS)
 .filter(([role])=>platform||role!=='school_admin');

const el=(tag,text='',cls='')=>{const x=document.createElement(tag);x.textContent=text;if(cls)x.className=cls;return x;};
function smallButton(text,cls='button button-outline button-small'){const b=el('button',text,cls);b.type='button';return b;}

export function createStaffDirectory({client,list,notice,say,platform=false,onChange=async()=>{}}){
 let schoolId=null,epoch=0;
 async function rpc(name,args){const r=await client.rpc(name,args);if(r.error)throw r.error;return r.data;}
 async function guarded(button,fn){
  button.disabled=true;
  try{await fn();}catch(err){say(err?.message||'Operazione non riuscita.',true);}
  finally{button.disabled=false;}
 }
 function showResult(result){
  if(!notice)return;
  notice.replaceChildren();notice.hidden=false;
  if(result.status==='assigned'){
   notice.dataset.type='success';
   notice.append(el('strong',result.email+' è ora '+roleLabel(result.role).toLowerCase()+'.'),
    el('p','Aveva già un account BreakApp: può entrare subito.'));
   return;
  }
  notice.dataset.type='information';
  notice.append(el('strong','Codice di attivazione per '+result.email+': '),
   el('code',result.code,'staff-invite-code'),
   el('p','Al primo accesso con questa email la persona viene collegata alla scuola come '+roleLabel(result.role).toLowerCase()+'. '+
    'Se usa un indirizzo @admin.breakapp.it deve inserire questo codice nel Profilo. Il codice compare solo ora: comunicalo di persona.'));
 }
 function clearNotice(){if(notice){notice.replaceChildren();notice.hidden=true;}}

 function editForm(row,invite){
  const form=el('form','','form-grid staff-invite-edit');
  const email=el('input');email.type='email';email.required=true;email.value=invite.email;email.autocomplete='off';
  email.setAttribute('aria-label','Email di '+invite.email);
  const role=el('select');role.setAttribute('aria-label','Ruolo di '+invite.email);
  for(const [value,label] of staffRoleOptions(platform))role.add(new Option(label,value));
  role.value=invite.role;
  const save=el('button','Salva','button button-primary button-small');save.type='submit';
  const cancel=smallButton('Annulla','button button-ghost button-small');
  const actions=el('div','','button-row');actions.append(save,cancel);
  form.append(email,role,actions);
  cancel.addEventListener('click',()=>void load(schoolId));
  form.addEventListener('submit',event=>{
   event.preventDefault();if(!form.reportValidity())return;
   void guarded(save,async()=>{
    await rpc('update_school_staff_invite',{p_invite:invite.id,p_email:email.value,p_role:role.value,p_renew_code:false});
    clearNotice();say('Invito aggiornato.');await load(schoolId);await onChange();
   });
  });
  row.replaceChildren(form);email.focus();
 }

 function render(data){
  list.replaceChildren();
  const members=data?.members||[],invites=data?.invites||[];
  if(!members.length&&!invites.length){list.append(el('p','Nessun membro del personale per questa scuola.'));return;}
  for(const member of members){
   const row=el('div','','staff-row');
   const info=el('div','','staff-row-info');
   info.append(el('strong',member.email),el('span',roleLabel(member.role)+' · '+membershipLabel(member.status)));
   row.append(info);
   if(platform){
    const revoke=smallButton('Revoca');
    revoke.addEventListener('click',()=>void guarded(revoke,async()=>{
     if(!await confirmDialog('Revocare il ruolo '+roleLabel(member.role)+' a '+member.email+'?'))return;
     await rpc('platform_revoke_school_staff',{p_school_id:schoolId,p_user_id:member.user_id,p_role:member.role});
     say('Ruolo revocato sul server.');await load(schoolId);await onChange();
    }));
    const actions=el('div','','button-row');actions.append(revoke);row.append(actions);
   }
   list.append(row);
  }
  for(const invite of invites){
   const row=el('div','','staff-row');
   const info=el('div','','staff-row-info');
   info.append(el('strong',invite.email),el('span',roleLabel(invite.role)+' · Non ha ancora fatto il primo accesso'));
   row.append(info);
   if(invite.can_edit){
    const edit=smallButton('Modifica'),renew=smallButton('Nuovo codice'),remove=smallButton('Rimuovi');
    edit.addEventListener('click',()=>editForm(row,invite));
    renew.addEventListener('click',()=>void guarded(renew,async()=>{
     if(!await confirmDialog('Creare un nuovo codice per '+invite.email+'? Il codice precedente smette di funzionare.'))return;
     const result=await rpc('update_school_staff_invite',{p_invite:invite.id,p_email:invite.email,p_role:invite.role,p_renew_code:true});
     showResult({status:'invited',email:result.email,role:result.role,code:result.code});
     say('Nuovo codice creato.');
    }));
    remove.addEventListener('click',()=>void guarded(remove,async()=>{
     if(!await confirmDialog('Rimuovere '+invite.email+'? Non potrà più collegarsi a questa scuola con questo invito.'))return;
     await rpc('remove_school_staff_invite',{p_invite:invite.id});
     clearNotice();say('Invito rimosso.');await load(schoolId);await onChange();
    }));
    const actions=el('div','','button-row');actions.append(edit,renew,remove);row.append(actions);
   }
   list.append(row);
  }
 }

 async function load(id){
  schoolId=id;const mine=++epoch;
  if(!id){list.replaceChildren();return null;}
  const data=await rpc('list_school_staff',{p_school:id});
  if(mine!==epoch)return null;
  render(data);return data;
 }
 async function invite(id,email,role){
  const result=await rpc('invite_school_staff',{p_school:id,p_email:email,p_role:role});
  showResult(result);
  return result;
 }
 function reset(){epoch++;schoolId=null;list.replaceChildren();clearNotice();}
 return {load,invite,reset,clearNotice};
}

// Pannello completo per l'Admin scuola: modulo di aggiunta ed elenco.
export function renderSchoolStaffPanel(parent,{client,schoolId}){
 const box=el('article','','order-card school-staff-panel');
 box.append(el('h3','Personale della scuola'),
  el('p','Aggiungi baristi e magazzinieri, anche prima che abbiano fatto il primo accesso. Gli Admin scuola li aggiunge il Super Admin; gli studenti si registrano da soli.','help'));
 const form=el('form','','form-grid');
 const emailField=el('div','','field'),emailLabel=el('label','Email'),email=el('input');
 email.type='email';email.required=true;email.autocomplete='off';email.placeholder='persona@scuola.it';
 email.id='school-staff-email';emailLabel.htmlFor=email.id;emailField.append(emailLabel,email);
 const roleField=el('div','','field'),roleLabelNode=el('label','Ruolo'),role=el('select');
 role.id='school-staff-role';roleLabelNode.htmlFor=role.id;
 for(const [value,label] of staffRoleOptions(false))role.add(new Option(label,value));
 roleField.append(roleLabelNode,role);
 const submitWrap=el('div','','field-wide'),submit=el('button','Aggiungi','button button-primary');submit.type='submit';submitWrap.append(submit);
 form.append(emailField,roleField,submitWrap);
 const status=el('p','','feedback');status.setAttribute('role','status');status.setAttribute('aria-live','polite');
 const notice=el('div','','alert staff-invite-notice');notice.hidden=true;notice.setAttribute('role','status');
 const list=el('div','','row-list staff-list');
 box.append(form,status,notice,list);parent.append(box);
 const say=(text,error=false)=>{status.textContent=text;status.dataset.type=error?'error':'information';};
 const directory=createStaffDirectory({client,list,notice,say,platform:false});
 form.addEventListener('submit',event=>{
  event.preventDefault();if(!form.reportValidity())return;
  submit.disabled=true;
  void (async()=>{
   try{await directory.invite(schoolId,email.value.trim(),role.value);email.value='';say('');await directory.load(schoolId);}
   catch(err){say(err?.message||'Operazione non riuscita.',true);}
   finally{submit.disabled=false;}
  })();
 });
 void directory.load(schoolId).catch(err=>say(err?.message||'Impossibile leggere il personale.',true));
 return box;
}

// Profilo di chi non ha ancora un ruolo: inserisce il codice ricevuto.
export function renderStaffClaimForm(parent,{client,onClaimed}){
 const form=el('form','','staff-claim-form');
 const label=el('label','Hai ricevuto un codice di attivazione dal personale della scuola?'),code=el('input');
 code.id='staff-claim-code';label.htmlFor=code.id;code.required=true;code.autocomplete='one-time-code';
 code.placeholder='ABCD-1234-EF56';code.maxLength=20;code.setAttribute('autocapitalize','characters');
 const submit=el('button','Attiva','button button-primary button-small');submit.type='submit';
 const status=el('p','','feedback');status.setAttribute('role','status');status.setAttribute('aria-live','polite');
 const row=el('div','','staff-claim-row');row.append(code,submit);
 form.append(label,row,status);parent.append(form);
 form.addEventListener('submit',event=>{
  event.preventDefault();if(!form.reportValidity())return;
  submit.disabled=true;
  void (async()=>{
   try{
    const {data,error}=await client.rpc('claim_school_staff_invite',{p_code:code.value});
    if(error)throw error;
    if(!data?.ok){status.textContent='Codice non valido per questo account. Controlla il codice e l’email con cui sei entrato.';status.dataset.type='error';return;}
    status.textContent='Account collegato come '+roleLabel(data.role).toLowerCase()+'.';status.dataset.type='success';
    await onClaimed?.();
   }catch(err){status.textContent=err?.message||'Attivazione non riuscita.';status.dataset.type='error';}
   finally{submit.disabled=false;}
  })();
 });
 return form;
}
