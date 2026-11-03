/**
 * Pure presentation helpers for the school bar workbench.
 * No economic state changes or authorization decisions belong in this module.
 */
export const ORDER_STATUS = Object.freeze({
  confirmed: { label: 'Da preparare', group: 'pending' },
  preparing: { label: 'In preparazione', group: 'preparing' },
  ready: { label: 'Pronto al ritiro', group: 'ready' },
  delivered: { label: 'Consegnato', group: 'closed' },
  no_show: { label: 'Non ritirato', group: 'closed' },
  cancelled: { label: 'Annullato', group: 'closed' }
});
export const BOARD_COLUMNS = Object.freeze([
  { key:'pending', label:'Da preparare' },
  { key:'preparing', label:'In preparazione' },
  { key:'ready', label:'Pronti' },
  { key:'closed', label:'Conclusi' }
]);
export function orderStatusLabel(status) {
  return ORDER_STATUS[status]?.label || 'Stato da verificare';
}
export function orderStatusGroup(status) {
  return ORDER_STATUS[status]?.group || 'closed';
}
export function slotKey(order) {
  const pickup=order.pickup_windows;
  return pickup?.service_date && pickup?.starts_at
    ? pickup.service_date+'|'+pickup.starts_at.slice(0,5)
    : 'unknown';
}
export function slotLabel(order) {
  const pickup=order.pickup_windows;
  if(!pickup?.service_date || !pickup?.starts_at) return 'Fascia non disponibile';
  const date=pickup.service_date;
  const parts=/^(\d{4})-(\d{2})-(\d{2})$/.exec(date);
  if(!parts)return 'Ritiro '+date+' · '+pickup.starts_at.slice(0,5);
  const value=new Date(Date.UTC(+parts[1],+parts[2]-1,+parts[3],12));
  const display=new Intl.DateTimeFormat('it-IT',{
    weekday:'short',day:'numeric',month:'short',timeZone:'UTC'
  }).format(value);
  return display+' · '+pickup.starts_at.slice(0,5);
}
export function availableSlots(orders) {
  const m=new Map();
  for(const order of orders||[]) {
    const key=slotKey(order);
    if(!m.has(key))m.set(key,slotLabel(order));
  }
  return [...m].sort(([a],[b])=>a.localeCompare(b)).map(([key,label])=>({key,label}));
}
export function boardOrders(orders,{slot='all',visibility='active',search=''}={}) {
  const q=String(search||'').trim().toLocaleLowerCase('it-IT');
  const stages=BOARD_COLUMNS.map(column=>({...column,orders:[]}));
  const byStage=new Map(stages.map(stage=>[stage.key,stage]));
  for(const order of orders||[]) {
    const group=orderStatusGroup(order.status);
    if(slot!=='all'&&slotKey(order)!==slot)continue;
    if(visibility==='active'&&group==='closed')continue;
    if(visibility==='closed'&&group!=='closed')continue;
    const items=(order.order_items||[]).map(i=>i.product_name).join(' ');
    if(q&&!String(order.display_no).includes(q)&&
      !items.toLocaleLowerCase('it-IT').includes(q))continue;
    byStage.get(group).orders.push(order);
  }
  for(const stage of stages){
    stage.orders.sort((a,b)=>{
      const ka=slotKey(a),kb=slotKey(b);
      return ka.localeCompare(kb)||Number(a.display_no||0)-Number(b.display_no||0);
    });
  }
  return stages;
}
export function productionTotals(orders,{slot='all'}={}) {
  const totals=new Map();
  for(const order of orders||[]) {
    if(!['confirmed','preparing'].includes(order.status))continue;
    if(slot!=='all'&&slotKey(order)!==slot)continue;
    for(const item of order.order_items||[]) {
      const name=String(item.product_name||'Prodotto');
      const qty=Number(item.quantity);
      if(!Number.isSafeInteger(qty)||qty<1)continue;
      const key=name.toLocaleLowerCase('it-IT');
      if(!totals.has(key))totals.set(key,{name,quantity:0});
      totals.get(key).quantity+=qty;
    }
  }
  return [...totals.values()].sort((a,b)=>
    b.quantity-a.quantity||a.name.localeCompare(b.name,'it-IT'));
}
