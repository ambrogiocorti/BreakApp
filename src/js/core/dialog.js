// Shared confirmation and input dialog. It replaces native confirm()/prompt(),
// which are unstyled, block the page and are hard to use on phones.
let pending=null;
function parts(){
  const dialog=document.getElementById('app-confirm-dialog');
  if(!dialog)return null;
  return {
    dialog,
    form:document.getElementById('app-confirm-form'),
    title:document.getElementById('app-confirm-title'),
    message:document.getElementById('app-confirm-message'),
    field:document.getElementById('app-confirm-field'),
    label:document.getElementById('app-confirm-label'),
    input:document.getElementById('app-confirm-input'),
    error:document.getElementById('app-confirm-error'),
    cancel:document.getElementById('app-confirm-cancel'),
    ok:document.getElementById('app-confirm-ok')
  };
}
let wired=false;
function wire(p){
  if(wired)return;wired=true;
  const settle=value=>{const resolve=pending;pending=null;if(p.dialog.open)p.dialog.close();resolve?.(value);};
  p.cancel.addEventListener('click',()=>settle(null));
  p.dialog.addEventListener('close',()=>{if(pending&&!p.dialog.open)settle(null);});
  p.form.addEventListener('submit',event=>{
    event.preventDefault();
    if(!p.field.hidden){
      const value=p.input.value.trim();
      const min=Number(p.input.dataset.min||0);
      if(p.input.required&&!value){p.error.textContent='Questo campo è obbligatorio.';p.input.focus();return;}
      if(min&&value&&value.length<min){p.error.textContent='Scrivi almeno '+min+' caratteri.';p.input.focus();return;}
      settle(value);return;
    }
    settle(true);
  });
}
function open({title,message='',confirmLabel='Conferma',cancelLabel='Annulla',danger=false,input=null,focusConfirm=false}){
  const p=parts();
  if(!p){
    // Defensive fallback for pages without the shared dialog markup.
    if(input)return Promise.resolve(window.prompt(message||title)??null);
    return Promise.resolve(window.confirm(message||title)||null);
  }
  wire(p);
  if(pending){const previous=pending;pending=null;previous(null);}
  p.title.textContent=title||'Confermi?';
  p.message.textContent=message;p.message.hidden=!message;
  p.ok.textContent=confirmLabel;p.cancel.textContent=cancelLabel;
  p.ok.className='button '+(danger?'button-danger':'button-primary');
  p.error.textContent='';
  p.field.hidden=!input;
  if(input){
    p.label.textContent=input.label||'Motivo';
    p.input.value=input.value||'';
    p.input.required=Boolean(input.required);
    p.input.dataset.min=String(input.minLength||0);
    p.input.maxLength=input.maxLength||1000;
    p.input.placeholder=input.placeholder||'';
  }
  if(p.dialog.open)p.dialog.close();
  p.dialog.showModal();
  // Cancel is the safe default; routine counter steps may ask to focus Confirm.
  (input?p.input:(focusConfirm&&!danger?p.ok:p.cancel)).focus();
  return new Promise(resolve=>{pending=resolve;});
}
/** Resolves true when confirmed, false otherwise. */
export async function confirmDialog(options){
  if(typeof options==='string')options={title:'Confermi?',message:options};
  return (await open(options))===true;
}
/** Resolves the trimmed text, or null when cancelled. Empty string is allowed unless required. */
export function promptDialog(options){
  if(typeof options==='string')options={title:'Serve un dato',label:options};
  const {label,required=false,minLength=0,maxLength,placeholder,value,...rest}=options||{};
  return open({...rest,input:{label,required,minLength,maxLength,placeholder,value}});
}
/** Short, non-blocking message. Important states must also stay visible in the page. */
export function toast(message,{type='information',timeout=4200}={}){
  const region=document.getElementById('toast-region');
  if(!region||!message)return;
  const item=document.createElement('p');
  item.className='toast';item.dataset.type=type;item.textContent=message;
  region.append(item);
  while(region.childElementCount>3)region.firstElementChild.remove();
  setTimeout(()=>item.remove(),timeout);
}
