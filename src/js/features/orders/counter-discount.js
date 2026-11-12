// Sconto per chi paga al banco, deciso dall'Admin della scuola (0-10%).
// Il server calcola sempre l'importo: qui si sceglie solo cosa mostrare.

export function counterDiscountPercent(bps){
  const value=Number(bps);
  if(!Number.isFinite(value)||value<=0)return '';
  return (value/100).toLocaleString('it-IT',{maximumFractionDigits:2});
}

// Importo da incassare al banco: quello scontato quando il server lo indica.
export function counterDueCents(details){
  const counter=Number(details?.counter_due_cents);
  if(Number.isSafeInteger(counter)&&counter>=0)return counter;
  return Number(details?.due_cents??0);
}

// Breve nota da aggiungere alla conferma del barista.
export function counterDiscountNote(details){
  const percent=counterDiscountPercent(details?.counter_discount_bps);
  const due=Number(details?.due_cents??0);
  if(!percent||!(due>0)||counterDueCents(details)>=due)return '';
  return ` (sconto al banco del ${percent}% già applicato)`;
}

// Frase per il cliente: quanto paga online e quanto al banco.
export function counterPriceSentence(totalCents,bps,formatEuro){
  const percent=counterDiscountPercent(bps);
  const total=Number(totalCents);
  if(!percent||!(total>0))return '';
  const discount=Math.min(total-1,Math.floor((total*Number(bps)+5000)/10000));
  if(!(discount>0))return '';
  return `Online ${formatEuro(total)} · al banco ${formatEuro(total-discount)} (sconto ${percent}%)`;
}
