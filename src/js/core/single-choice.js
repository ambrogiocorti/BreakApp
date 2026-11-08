// Regola confermata: ogni account (tranne il Super Admin) ha una sola scuola.
// Un selettore con una sola voce non è una scelta: lo nascondiamo, ma resta
// nel DOM con il suo valore, così i controller continuano a leggerlo.
// Ricompare da solo se il controller aggiunge altre voci (per esempio uno
// studente registrato che vede più scuole nel menu).
export function isSingleChoice(select){
 return [...(select?.options||[])].filter(option=>option.value!=='').length<=1;
}

export function hideWhenSingleChoice(select,onChange=()=>{}){
 if(!select)return null;
 const field=select.closest('.field')||select;
 const sync=()=>{const single=isSingleChoice(select);field.hidden=single;onChange(single);};
 const observer=new MutationObserver(sync);
 observer.observe(select,{childList:true});
 sync();
 return observer;
}

export function initializeSingleChoiceFields(root=document){
 for(const select of root.querySelectorAll('select[data-hide-single]'))hideWhenSingleChoice(select);
 // Menu: se scuola e bar sono entrambi fissi, «Cambia» non ha nulla da cambiare.
 const picker=root.getElementById?.('menu-place');
 const school=root.getElementById?.('menu-school'),bar=root.getElementById?.('menu-bar');
 if(picker&&school&&bar){
  const summary=picker.querySelector('summary');
  const sync=()=>{
   const fixed=isSingleChoice(school)&&isSingleChoice(bar);
   picker.toggleAttribute('data-fixed',fixed);
   if(fixed){picker.open=false;summary?.setAttribute('tabindex','-1');}
   else summary?.removeAttribute('tabindex');
  };
  hideWhenSingleChoice(school,sync);hideWhenSingleChoice(bar,sync);
  picker.addEventListener('toggle',()=>{if(picker.hasAttribute('data-fixed')&&picker.open)picker.open=false;});
 }
}
